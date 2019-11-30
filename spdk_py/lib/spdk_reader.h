//
// Created by alexeymar on 29-Nov-19.
//

#pragma once

#include <vector>
#include <map>
#include <thread>
#include <memory>
#include <atomic>
#include <cuda_runtime_api.h>
#include <spdk/nvme.h>


class spdk_reader_ctx {
	public:
	spdk_reader_ctx(const char* transport);
	spdk_reader_ctx(const spdk_reader_ctx& other) = delete;
	spdk_reader_ctx& operator=(const spdk_reader_ctx& other) = delete;

	spdk_reader_ctx(spdk_reader_ctx&& other) noexcept {
		env_opts = other.env_opts;
		ctrlr_trid = other.ctrlr_trid;
		ctrlr = other.ctrlr;
		namespaces = std::move(other.namespaces);
		ns = other.ns;
		qpair = other.qpair;
		sector_size = other.sector_size;
		ctrlr_poller = std::move(other.ctrlr_poller);
		thread_run.store(true, std::memory_order::memory_order_release);
	}

	spdk_reader_ctx& operator=(spdk_reader_ctx&& other) {
		if(&other == this) {
			return *this;
		}
		if(ctrlr_poller.joinable()) {
			thread_run.store(false, std::memory_order::memory_order_release);
			ctrlr_poller.join();
		}
		if(ctrlr) {
			spdk_nvme_detach(ctrlr);
		}
		if(qpair) {
			spdk_nvme_ctrlr_free_io_qpair(qpair);
		}

		env_opts = other.env_opts;
		ctrlr_trid = other.ctrlr_trid;
		ctrlr = other.ctrlr;
		namespaces = std::move(other.namespaces);
		ns = other.ns;
		qpair = other.qpair;
		sector_size = other.sector_size;
		ctrlr_poller = std::move(other.ctrlr_poller);
		thread_run.store(true, std::memory_order::memory_order_release);

		return *this;
	}

	~spdk_reader_ctx() {
		if(ctrlr_poller.joinable()) {
			thread_run.store(false, std::memory_order::memory_order_release);
			ctrlr_poller.join();
		}
		if(qpair) {
			spdk_nvme_ctrlr_free_io_qpair(qpair);
		}
		if(ctrlr) {
			spdk_nvme_detach(ctrlr);
		}
	}

	static std::shared_ptr<void> get_cpu_mem(size_t size);

	static std::shared_ptr<void> get_gpu_mem(size_t size);

	void* alloc_cpu_mem(size_t size);
	void free_cpu_mem(void* ptr);

	void* alloc_gpu_mem(size_t size);
	void free_gpu_mem(void* ptr);

	int do_read(const char *file, void *output);

	size_t get_aligned_file_size(const char* file);

	void register_controller(spdk_nvme_ctrlr* contoller);

	static bool	probe_cb(void *cb_ctx, const struct spdk_nvme_transport_id *trid,
							struct spdk_nvme_ctrlr_opts *opts);

	static void	attach_cb(void *cb_ctx, const struct spdk_nvme_transport_id *trid,
							 struct spdk_nvme_ctrlr *ctrlr, const struct spdk_nvme_ctrlr_opts *opts);

	void poll_controllers();

	private:
	spdk_env_opts env_opts = {};

	spdk_nvme_transport_id ctrlr_trid = {};
	spdk_nvme_ctrlr* ctrlr = {};
	std::vector<spdk_nvme_ns*> namespaces = {};
	spdk_nvme_ns* ns = {};
	spdk_nvme_qpair* qpair = {};
	uint32_t sector_size = {};

	private:
	std::thread ctrlr_poller;
	std::atomic_bool thread_run;
};
