
#include "spdk_reader.h"

#include <iostream>
#include <string>
#include <list>
#include <stdexcept>
#include <infiniband/verbs.h>
#include <rdma/rdma_cma.h>
#include <linux/fiemap.h>
#include <linux/fs.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

static constexpr uint32_t g_queue_depth = 8;

class spdk_ibv_device {
	public:
	explicit spdk_ibv_device(ibv_context *ctx) : context(ctx) {
		if (!ctx) {
			std::cerr << "null context" << std::endl;
		}
		pd = ibv_alloc_pd(context);
		if (!pd) {
			throw std::runtime_error("Failed to alloc pd");
		}
	}

	ibv_mr *get_mr(void *addr, size_t size, size_t &available_size) {
		char *address = reinterpret_cast<char *>(addr);
		for (auto mr : mrs) {
			char *mr_start = reinterpret_cast<char *>(mr->addr);
			char *mr_end = mr_start + mr->length;
			if (mr_start <= address && address <= mr_end) {
				available_size = mr_end - address;
				return mr;
			}
		}
		return nullptr;
	}

	~spdk_ibv_device() {
		for (auto mr : mrs) {
			ibv_dereg_mr(mr);
		}
		ibv_dealloc_pd(pd);
	}

	ibv_context *context;
	ibv_pd *pd;

	ibv_mr *reg_mr(void *addr, size_t size) {
		auto mr = ibv_reg_mr(pd, addr, size, IBV_ACCESS_REMOTE_WRITE | IBV_ACCESS_LOCAL_WRITE |
											 IBV_ACCESS_REMOTE_READ);
		if (!mr) {
			throw std::runtime_error("failed to register MR\n");
		}
		mrs.push_back(std::move(mr));
		return mr;
	}

	void dereg_mr(void *addr) {
		char *address = reinterpret_cast<char *>(addr);
		for (auto it = mrs.begin(); it != mrs.end(); ++it) {
			char *mr_start = reinterpret_cast<char *>((*it)->addr);
			char *mr_end = mr_start + (*it)->length;
			if (mr_start <= address && address <= mr_end) {
				mrs.erase(it);
				return;
			}
		}
	}

	private:
	//list of mrs registered for this pd/device
	std::list<ibv_mr *> mrs;
};

class spdk_ibv_device_storage {
	public:
	spdk_ibv_device_storage() {
		int num;
		ibv_context **contexts = rdma_get_devices(&num);
		for (int i = 0; i < num; i++) {
			std::unique_ptr<spdk_ibv_device> dev{new spdk_ibv_device(contexts[i])};
			devices_by_ctx[contexts[i]] = dev.get();
			devices_by_pd[dev->pd] = dev.get();
			devices.push_back(std::move(dev));
		}
		rdma_free_devices(contexts);
	}

	static ibv_pd *get_ibv_pd(const struct spdk_nvme_transport_id *trid,
							  struct ibv_context *verbs);

	static ibv_mr *get_user_mr(struct ibv_pd *pd, void *buf, size_t *size);

	std::vector<std::unique_ptr<spdk_ibv_device>> devices;
	std::map<ibv_context *, spdk_ibv_device *> devices_by_ctx;
	std::map<ibv_pd *, spdk_ibv_device *> devices_by_pd;
};

static spdk_ibv_device_storage g_ibv_devices;

ibv_pd *spdk_ibv_device_storage::get_ibv_pd(const struct spdk_nvme_transport_id *trid,
											struct ibv_context *verbs) {
	auto dev_iter = g_ibv_devices.devices_by_ctx.find(verbs);
	if (dev_iter != g_ibv_devices.devices_by_ctx.end()) {
		return dev_iter->second->pd;
	}
	std::cerr << "Can't find PD for device " << verbs;
	return nullptr;
}

ibv_mr *spdk_ibv_device_storage::get_user_mr(struct ibv_pd *pd, void *buf, size_t *size) {
	auto dev_iter = g_ibv_devices.devices_by_pd.find(pd);
	if (dev_iter != g_ibv_devices.devices_by_pd.end()) {
		auto requested = *size;
		return dev_iter->second->get_mr(buf, requested, *size);
	}
	std::cerr << "Can't find PD " << pd;
	return nullptr;
}

//////////////////////

class spdk_do_read;

struct spdk_io_ctx {
	spdk_do_read *main;
	uint32_t lba_count; //count of lba's to be read in this request
};

class spdk_do_read {
	public:
	spdk_do_read() = delete;

	spdk_do_read(const char *filepath, spdk_nvme_ns *_ns, spdk_nvme_qpair *_qpair, uint32_t qdepth)
		: ns(_ns), qpair(_qpair), queue_depth(qdepth),
		  sector_size(spdk_nvme_ns_get_sector_size(_ns)),
		  max_lbas_per_io(
			  spdk_nvme_ctrlr_get_max_xfer_size(spdk_nvme_ns_get_ctrlr(ns)) / sector_size),
		  io_ctx(qdepth) {
		int flags = O_DIRECT | O_RDONLY;
		int fd = open(filepath, flags);
		if (fd < 0) {
			throw std::runtime_error("Failed to open file " + std::string(filepath));
		}
		struct stat st;
		if (fstat(fd, &st) != 0) {
			throw std::runtime_error("Failed to stat file " + std::string(filepath));
		}
		file_size = st.st_size;
		total_lba_count = (file_size + (sector_size - 1)) / sector_size;
		uint32_t sector_log2 = spdk_u32log2(sector_size);

		union {
			struct fiemap f;
			char c[4096];
		} fiemap_buf = {};
		fiemap *fiemap = &fiemap_buf.f;
		fiemap_extent *fm_extents = &fiemap->fm_extents[0];
		fiemap->fm_extent_count = (sizeof fiemap_buf - sizeof(*fiemap)) / sizeof(*fm_extents);
		fiemap->fm_length = FIEMAP_MAX_OFFSET;
		auto rc = ioctl(fd, FS_IOC_FIEMAP, fiemap);
		if (rc) {
			throw std::runtime_error(
				"FIEMAP failed, rc " + std::to_string(rc) + " errno" + std::to_string(errno));
		}
		close(fd);

		std::cout << "File " << filepath << ", size " << file_size << ", lbas " << total_lba_count
				  <<
				  ", extents " << fiemap->fm_mapped_extents << std::endl;

		for (uint32_t j = 0; j < fiemap->fm_mapped_extents; j++) {
			auto length = fm_extents[j].fe_length >> sector_log2;
			auto logical_start = fm_extents[j].fe_logical >> sector_log2;
			auto physical_start = fm_extents[j].fe_physical >> sector_log2;
			printf("[%4u]: logical %8llu .. %8llu \tphysical %8llu .. %8llu \tlen %8llu\n",
				   j, logical_start, logical_start + length - 1,
				   physical_start, physical_start + length - 1, length);

			lbas.emplace_back(std::make_pair(physical_start, length));
		}
	}

	static void io_complete_cb(void *ctx, const struct spdk_nvme_cpl *cpl) {
		auto entry = static_cast<spdk_io_ctx *>(ctx);
		spdk_do_read *reader = entry->main;

		if (spdk_nvme_cpl_is_error(cpl)) {
			throw std::runtime_error(
				"read completed with error (sct=" + std::to_string(cpl->status.sct) +
				", sc=" + std::to_string(cpl->status.sc) + ")");
		}

		reader->lba_read += entry->lba_count;
		assert(reader->lba_read <= reader->total_lba_count);

		if (reader->lba_read < reader->total_lba_count) {
			reader->submit_io(*entry);
		}
	}

	void submit_io(spdk_io_ctx &ctx) {

		if (lba_read >= total_lba_count || lba_array_idx >= lbas.size()) {
			return;
		}

		uint32_t lba_count = spdk_min(lbas[lba_array_idx].second - lba_idx, max_lbas_per_io);
		void *payload_ptr = static_cast<char *>(buffer) + lba_submitted_to_read * sector_size;
		uint32_t start_lba = lbas[lba_array_idx].first + lba_idx;
		lba_submitted_to_read += lba_count;

		lba_idx += lba_count;
		ctx.lba_count = lba_count;

		if (lba_idx >= lbas[lba_array_idx].second) {
			lba_array_idx++;
			lba_idx = 0;
		}

		int rc = spdk_nvme_ns_cmd_read_with_md(ns, qpair, payload_ptr, nullptr, start_lba,
											   lba_count, &spdk_do_read::io_complete_cb,
											   &ctx, 0, 0, 0);
		if (rc) {
			fprintf(stderr, "nvme read failed with %d\n", rc);
		}
	}

	int do_read(void *buf) {
		buffer = buf;

		for (uint32_t i = 0; i < queue_depth; i++) {
			io_ctx[i].main = this;
			io_ctx[i].lba_count = 0;
			submit_io(io_ctx[i]);
		}

		while (lba_read < total_lba_count) {
			int completions = spdk_nvme_qpair_process_completions(qpair, queue_depth);
			if (completions < 0) {
				std::cerr << "process_completions failed with " << completions << std::endl;
				return completions;
			}
		}
		std::cout << "Done" << std::endl;
		reset_state();

		return 0;
	}

	spdk_nvme_ns *ns;
	spdk_nvme_qpair *qpair;

	uint32_t queue_depth;
	uint32_t sector_size;
	uint32_t max_lbas_per_io;
	std::vector<spdk_io_ctx> io_ctx;

	//lba start, lba count
	std::vector<std::pair<uint64_t, uint64_t>> lbas;
	uint32_t file_size = 0;
	void *buffer;

	uint32_t total_lba_count = 0;
	uint32_t lba_array_idx = 0;    //current idx in lbas
	uint32_t lba_idx = 0;        //current number of lba in lbas
	uint32_t lba_read = 0;        //number of lba already read
	uint32_t lba_submitted_to_read = 0;    //number of lba's submitted to read but not completted yet

	private:
	void reset_state() {
		lba_array_idx = 0;
		lba_idx = 0;
		lba_read = 0;
		lba_submitted_to_read = 0;
	}
};

//////////////////////

bool spdk_reader_ctx::probe_cb(void *cb_ctx, const struct spdk_nvme_transport_id *trid,
							   struct spdk_nvme_ctrlr_opts *opts) {
	std::cout << "probe_cb, addr " << trid->traddr << std::endl;
	opts->io_queue_size = UINT16_MAX;
	opts->keep_alive_timeout_ms = 10000;

	return true;
}

void spdk_reader_ctx::attach_cb(void *cb_ctx, const struct spdk_nvme_transport_id *trid,
								struct spdk_nvme_ctrlr *ctrlr,
								const struct spdk_nvme_ctrlr_opts *opts) {
	std::cout << "attach_cb, addr " << trid->traddr << std::endl;
	auto instance = reinterpret_cast<spdk_reader_ctx *>(cb_ctx);
	instance->register_controller(ctrlr);
}

void spdk_reader_ctx::register_controller(spdk_nvme_ctrlr *contoller) {
	ctrlr = contoller;

	std::cout << "Getting namespaces" << std::endl;
	for (uint32_t nsid = spdk_nvme_ctrlr_get_first_active_ns(ctrlr);
		 nsid != 0; nsid = spdk_nvme_ctrlr_get_next_active_ns(ctrlr, nsid)) {
		auto _ns = spdk_nvme_ctrlr_get_ns(ctrlr, nsid);
		if (_ns == nullptr) {
			continue;
		}
		if (!spdk_nvme_ns_is_active(_ns)) {
			continue;
		}
		namespaces.push_back(_ns);
	}
	if (namespaces.empty()) {
		throw std::runtime_error("Can't find any namespace");
	}

	std::cout << "Found " << namespaces.size() << " namespaces, will use the first one"
			  << std::endl;
	ns = namespaces[0];

	std::cout << "Creating IO queue" << std::endl;
	spdk_nvme_io_qpair_opts qopts{};
	spdk_nvme_ctrlr_get_default_io_qpair_opts(ctrlr, &qopts, sizeof(qopts));
	qopts.io_queue_requests = g_queue_depth * 4;
	qopts.io_queue_size = g_queue_depth;

	qpair = spdk_nvme_ctrlr_alloc_io_qpair(ctrlr, &qopts, sizeof(qopts));
	if (!qpair) {
		throw std::runtime_error("Failed to create IO qpair");
	}

	sector_size = spdk_nvme_ns_get_sector_size(ns);
}

size_t spdk_reader_ctx::get_aligned_file_size(const char *file) {
	int flags = O_DIRECT | O_RDONLY;
	int fd = open(file, flags);
	if (fd < 0) {
		std::cerr << "Failed to open file " << file << std::endl;
		return 0;
	}
	struct stat st;
	if (fstat(fd, &st) != 0) {
		std::cerr << "Failed to stat file " << file << std::endl;
	}
	size_t mask = sector_size - 1;
	return (st.st_size + mask) & ~mask;
}

spdk_reader_ctx::spdk_reader_ctx(const char *transport) {

	spdk_env_opts_init(&env_opts);
	env_opts.name = "spdk_py";

	int rc = spdk_env_init(&env_opts);
	if (rc) {
		throw std::runtime_error("Failed to init dpdk env, result " + std::to_string(rc));
	}

	struct spdk_nvme_rdma_hooks g_spdk_reader_hooks = {
		.get_ibv_pd = &spdk_ibv_device_storage::get_ibv_pd,
		.get_rkey = nullptr,
		.get_user_mr = &spdk_ibv_device_storage::get_user_mr
	};

	spdk_nvme_rdma_init_hooks(&g_spdk_reader_hooks);

	//start controller initialization
	rc = spdk_nvme_transport_id_parse(&ctrlr_trid, transport);
	snprintf(ctrlr_trid.subnqn, sizeof(ctrlr_trid.subnqn), "%s", SPDK_NVMF_DISCOVERY_NQN);
	if (rc) {
		throw std::runtime_error(
			"Failed to parse trid " + std::string(transport) + " result " + std::to_string(rc));
	}
	if (spdk_nvme_probe(&ctrlr_trid, this, &spdk_reader_ctx::probe_cb, &spdk_reader_ctx::attach_cb,
						NULL) != 0) {
		throw std::runtime_error("Failed to probe controller " + std::string(ctrlr_trid.traddr));
	}

	if (!ctrlr) {
		throw std::runtime_error("Controller is not created");
	}

	thread_run.store(true, std::memory_order::memory_order_release);
	ctrlr_poller = std::thread(&spdk_reader_ctx::poll_controllers, this);
}

void spdk_reader_ctx::poll_controllers() {
	while (thread_run.load(std::memory_order::memory_order_acquire)) {
		spdk_nvme_ctrlr_process_admin_completions(ctrlr);
		sleep(1);
	}
}

int spdk_reader_ctx::do_read(const char *file, void *output) {
	spdk_do_read task{file, ns, qpair, g_queue_depth};
	return task.do_read(output);
}

std::shared_ptr<void> spdk_reader_ctx::get_cpu_mem(size_t size) {
	auto mem = std::shared_ptr<void>(spdk_dma_zmalloc(size, 512, nullptr), [&](void *ptr) {
		spdk_dma_free(ptr);
		for (auto &it: g_ibv_devices.devices_by_pd) {
			it.second->dereg_mr(ptr);
		}
	});

	for (auto &it: g_ibv_devices.devices_by_pd) {
		it.second->reg_mr(mem.get(), size);
	}

	return mem;
}

std::shared_ptr<void> spdk_reader_ctx::get_gpu_mem(size_t size) {
	void *ptr;
	auto rc = cudaMalloc(&ptr, size);
	if (rc) {
		return std::shared_ptr<void>(nullptr);
	}

	auto mem = std::shared_ptr<void>(ptr, [&](void *ptr) {
		cudaFree(ptr);
		for (auto &it: g_ibv_devices.devices_by_pd) {
			it.second->dereg_mr(ptr);
		}
	});

	for (auto &it: g_ibv_devices.devices_by_pd) {
		it.second->reg_mr(ptr, size);
	}

	return mem;
}

void *spdk_reader_ctx::alloc_cpu_mem(size_t size) {
	auto ptr = spdk_dma_zmalloc(size, 512, nullptr);
	for (auto &it: g_ibv_devices.devices_by_pd) {
		it.second->reg_mr(ptr, size);
	}
	return ptr;
}

void spdk_reader_ctx::free_cpu_mem(void *ptr) {
	spdk_dma_free(ptr);
	for (auto &it: g_ibv_devices.devices_by_pd) {
		it.second->dereg_mr(ptr);
	}
}

void *spdk_reader_ctx::alloc_gpu_mem(size_t size) {
	void *ptr;
	auto rc = cudaMalloc(&ptr, size);
	if (rc) {
		return nullptr;
	}
	for (auto &it: g_ibv_devices.devices_by_pd) {
		it.second->reg_mr(ptr, size);
	}
	return ptr;
}

void spdk_reader_ctx::free_gpu_mem(void *ptr) {
	cudaFree(ptr);
	for (auto &it: g_ibv_devices.devices_by_pd) {
		it.second->dereg_mr(ptr);
	}
}
