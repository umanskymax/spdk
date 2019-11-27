/*-
 *   BSD LICENSE
 *
 *   Copyright (c) Intel Corporation.
 *   All rights reserved.
 *
 *   Copyright (c) 2019 Mellanox Technologies LTD. All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "spdk/stdinc.h"

#include "spdk/env.h"
#include "spdk/fd.h"
#include "spdk/nvme.h"
#include "spdk/vmd.h"
#include "spdk/queue.h"
#include "spdk/string.h"
#include "spdk/nvme_intel.h"
#include "spdk/histogram_data.h"
#include "spdk/endian.h"
#include "spdk/dif.h"
#include "spdk/util.h"
#include "spdk/log.h"
#include "spdk/likely.h"

#if HAVE_LIBAIO
#include <libaio.h>
#endif

#include <sys/fcntl.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <linux/fiemap.h>
#include <infiniband/verbs.h>

#include <cuda_runtime_api.h>
#include <cuda.h>
#include <rdma/rdma_cma.h>

struct ctrlr_entry {
	struct spdk_nvme_ctrlr			*ctrlr;
	enum spdk_nvme_transport_type		trtype;
	struct spdk_nvme_intel_rw_latency_page	*latency_page;

	struct spdk_nvme_qpair			**unused_qpairs;

	struct ctrlr_entry			*next;
	char					name[1024];
};

enum entry_type {
	ENTRY_TYPE_NVME_NS,
	ENTRY_TYPE_AIO_FILE,
};

struct ns_fn_table;

struct ns_entry {
	enum entry_type		type;
	const struct ns_fn_table	*fn_table;

	union {
		struct {
			struct spdk_nvme_ctrlr	*ctrlr;
			struct spdk_nvme_ns	*ns;
		} nvme;
#if HAVE_LIBAIO
		struct {
			int			fd;
		} aio;
#endif
	} u;

	struct ns_entry		*next;
	uint32_t		io_size_blocks;
	uint32_t		num_io_requests;
	uint64_t		size_in_ios;
	uint32_t		block_size;
	uint32_t		md_size;
	bool			md_interleave;
	bool			pi_loc;
	enum spdk_nvme_pi_type	pi_type;
	uint32_t		io_flags;
	char			name[1024];
};


struct ns_fn_table {
	void	(*setup_payload)(struct perf_task *task, uint8_t pattern);

	int	(*submit_io)(struct perf_task *task, struct ns_worker_ctx *ns_ctx,
			     struct ns_entry *entry, uint64_t offset_in_ios);

	void	(*check_io)(struct ns_worker_ctx *ns_ctx);

	void	(*verify_io)(struct perf_task *task, struct ns_entry *entry);

	int	(*init_ns_worker_ctx)(struct ns_worker_ctx *ns_ctx);

	void	(*cleanup_ns_worker_ctx)(struct ns_worker_ctx *ns_ctx);
};

static int g_outstanding_commands;

static bool g_latency_ssd_tracking_enable = false;
static int g_latency_sw_tracking_level = 0;

static bool g_vmd = false;

static struct ctrlr_entry *g_controllers = NULL;
static struct ns_entry *g_namespaces = NULL;
static int g_num_namespaces = 0;
static struct worker_thread *g_workers = NULL;
static int g_num_workers = 0;
static uint32_t g_master_core;

static uint64_t g_tsc_rate;

static uint32_t g_io_align = 0x200;
static uint32_t g_io_size_bytes;
static uint32_t g_max_io_md_size;
static uint32_t g_max_io_size_blocks;
static uint32_t g_metacfg_pract_flag;
static uint32_t g_metacfg_prchk_flags;
static int g_rw_percentage;
static int g_is_random;
static int g_queue_depth;
static int g_nr_io_queues_per_ns = 1;
static int g_nr_unused_io_queues = 0;
static int g_time_in_sec;
static uint32_t g_max_completions;
static int g_dpdk_mem;
static int g_shm_id = -1;
static uint32_t g_disable_sq_cmb;
static bool g_no_pci;
static bool g_warn;
static bool g_header_digest;
static bool g_data_digest;
static bool g_no_shn_notification = false;
static uint32_t g_keep_alive_timeout_in_ms = 0;

static const char *g_core_mask;

struct trid_entry {
	struct spdk_nvme_transport_id	trid;
	uint16_t			nsid;
	TAILQ_ENTRY(trid_entry)		tailq;
};

static TAILQ_HEAD(, trid_entry) g_trid_list = TAILQ_HEAD_INITIALIZER(g_trid_list);

static int g_aio_optind; /* Index of first AIO filename in argv */


static void
build_nvme_name(char *name, size_t length, struct spdk_nvme_ctrlr *ctrlr)
{
	const struct spdk_nvme_transport_id *trid;

	trid = spdk_nvme_ctrlr_get_transport_id(ctrlr);

	switch (trid->trtype) {
	case SPDK_NVME_TRANSPORT_PCIE:
		snprintf(name, length, "PCIE (%s)", trid->traddr);
		break;
	case SPDK_NVME_TRANSPORT_RDMA:
		snprintf(name, length, "RDMA (addr:%s subnqn:%s)", trid->traddr, trid->subnqn);
		break;
	case SPDK_NVME_TRANSPORT_TCP:
		snprintf(name, length, "TCP  (addr:%s subnqn:%s)", trid->traddr, trid->subnqn);
		break;
	default:
		fprintf(stderr, "Unknown transport type %d\n", trid->trtype);
		break;
	}
}

static void
register_ns(struct spdk_nvme_ctrlr *ctrlr, struct spdk_nvme_ns *ns)
{
	struct ns_entry *entry;
	const struct spdk_nvme_ctrlr_data *cdata;
	uint32_t max_xfer_size, entries, sector_size;
	uint64_t ns_size;
	struct spdk_nvme_io_qpair_opts opts;

	cdata = spdk_nvme_ctrlr_get_data(ctrlr);

	if (!spdk_nvme_ns_is_active(ns)) {
		printf("Controller %-20.20s (%-20.20s): Skipping inactive NS %u\n",
		       cdata->mn, cdata->sn,
		       spdk_nvme_ns_get_id(ns));
		g_warn = true;
		return;
	}

	ns_size = spdk_nvme_ns_get_size(ns);
	sector_size = spdk_nvme_ns_get_sector_size(ns);

	if (ns_size < g_io_size_bytes || sector_size > g_io_size_bytes) {
		printf("WARNING: controller %-20.20s (%-20.20s) ns %u has invalid "
		       "ns size %" PRIu64 " / block size %u for I/O size %u\n",
		       cdata->mn, cdata->sn, spdk_nvme_ns_get_id(ns),
		       ns_size, spdk_nvme_ns_get_sector_size(ns), g_io_size_bytes);
		g_warn = true;
		return;
	}

	max_xfer_size = spdk_nvme_ns_get_max_io_xfer_size(ns);
	spdk_nvme_ctrlr_get_default_io_qpair_opts(ctrlr, &opts, sizeof(opts));
	/* NVMe driver may add additional entries based on
	 * stripe size and maximum transfer size, we assume
	 * 1 more entry be used for stripe.
	 */
	entries = (g_io_size_bytes - 1) / max_xfer_size + 2;
	if ((g_queue_depth * entries) > opts.io_queue_size) {
		printf("controller IO queue size %u less than required\n",
		       opts.io_queue_size);
		printf("Consider using lower queue depth or small IO size because "
		       "IO requests may be queued at the NVMe driver.\n");
	}
	/* For requests which have children requests, parent request itself
	 * will also occupy 1 entry.
	 */
	entries += 1;

	entry = (struct ns_entry *)calloc(1, sizeof(struct ns_entry));
	if (entry == NULL) {
		perror("ns_entry malloc");
		exit(1);
	}

	entry->type = ENTRY_TYPE_NVME_NS;
	entry->u.nvme.ctrlr = ctrlr;
	entry->u.nvme.ns = ns;
	entry->num_io_requests = g_queue_depth * entries;

	entry->size_in_ios = ns_size / g_io_size_bytes;
	entry->io_size_blocks = g_io_size_bytes / sector_size;

	entry->block_size = spdk_nvme_ns_get_extended_sector_size(ns);
	entry->md_size = spdk_nvme_ns_get_md_size(ns);
	entry->md_interleave = spdk_nvme_ns_supports_extended_lba(ns);
	entry->pi_loc = spdk_nvme_ns_get_data(ns)->dps.md_start;
	entry->pi_type = spdk_nvme_ns_get_pi_type(ns);

	if (spdk_nvme_ns_get_flags(ns) & SPDK_NVME_NS_DPS_PI_SUPPORTED) {
		entry->io_flags = g_metacfg_pract_flag | g_metacfg_prchk_flags;
	}

	/* If metadata size = 8 bytes, PI is stripped (read) or inserted (write),
	 *  and so reduce metadata size from block size.  (If metadata size > 8 bytes,
	 *  PI is passed (read) or replaced (write).  So block size is not necessary
	 *  to change.)
	 */
	if ((entry->io_flags & SPDK_NVME_IO_FLAGS_PRACT) && (entry->md_size == 8)) {
		entry->block_size = spdk_nvme_ns_get_sector_size(ns);
	}

	if (g_max_io_md_size < entry->md_size) {
		g_max_io_md_size = entry->md_size;
	}

	if (g_max_io_size_blocks < entry->io_size_blocks) {
		g_max_io_size_blocks = entry->io_size_blocks;
	}

	build_nvme_name(entry->name, sizeof(entry->name), ctrlr);

	g_num_namespaces++;
	entry->next = g_namespaces;
	g_namespaces = entry;
}

static void
unregister_namespaces(void)
{
	struct ns_entry *entry = g_namespaces;

	while (entry) {
		struct ns_entry *next = entry->next;
		free(entry);
		entry = next;
	}
}


static void
register_ctrlr(struct spdk_nvme_ctrlr *ctrlr, struct trid_entry *trid_entry)
{
	struct spdk_nvme_ns *ns;
	struct ctrlr_entry *entry = (struct ctrlr_entry *)malloc(sizeof(struct ctrlr_entry));
	uint32_t nsid;

	if (entry == NULL) {
		perror("ctrlr_entry malloc");
		exit(1);
	}

	entry->latency_page = (struct spdk_nvme_intel_rw_latency_page *)spdk_dma_zmalloc(sizeof(struct spdk_nvme_intel_rw_latency_page),
					       4096, NULL);
	if (entry->latency_page == NULL) {
		printf("Allocation error (latency page)\n");
		exit(1);
	}

	build_nvme_name(entry->name, sizeof(entry->name), ctrlr);

	entry->ctrlr = ctrlr;
	entry->trtype = trid_entry->trid.trtype;
	entry->next = g_controllers;
	g_controllers = entry;

	if (trid_entry->nsid == 0) {
		for (nsid = spdk_nvme_ctrlr_get_first_active_ns(ctrlr);
		     nsid != 0; nsid = spdk_nvme_ctrlr_get_next_active_ns(ctrlr, nsid)) {
			ns = spdk_nvme_ctrlr_get_ns(ctrlr, nsid);
			if (ns == NULL) {
				continue;
			}
			register_ns(ctrlr, ns);
		}
	} else {
		ns = spdk_nvme_ctrlr_get_ns(ctrlr, trid_entry->nsid);
		if (!ns) {
			perror("Namespace does not exist.");
			exit(1);
		}

		register_ns(ctrlr, ns);
	}

	if (g_nr_unused_io_queues) {
		int i;

		printf("Creating %u unused qpairs for controller %s\n", g_nr_unused_io_queues, entry->name);

		entry->unused_qpairs = (struct spdk_nvme_qpair **)calloc(g_nr_unused_io_queues, sizeof(struct spdk_nvme_qpair *));
		if (!entry->unused_qpairs) {
			fprintf(stderr, "Unable to allocate memory for qpair array\n");
			exit(1);
		}

		for (i = 0; i < g_nr_unused_io_queues; i++) {
			entry->unused_qpairs[i] = spdk_nvme_ctrlr_alloc_io_qpair(ctrlr, NULL, 0);
			if (!entry->unused_qpairs[i]) {
				fprintf(stderr, "Unable to allocate unused qpair. Did you request too many?\n");
				exit(1);
			}
		}
	}

}

static __thread unsigned int seed = 0;


static void usage(char *program_name)
{
	printf("%s options", program_name);
#if HAVE_LIBAIO
	printf(" [AIO device(s)]...");
#endif
	printf("\n");
	printf("\t[-q io depth]\n");
	printf("\t[-o io size in bytes]\n");
	printf("\t[-n number of io queues per namespace. default: 1]\n");
	printf("\t[-U number of unused io queues per controller. default: 0]\n");
	printf("\t[-w io pattern type, must be one of\n");
	printf("\t\t(read, write, randread, randwrite, rw, randrw)]\n");
	printf("\t[-M rwmixread (100 for reads, 0 for writes)]\n");
	printf("\t[-L enable latency tracking via sw, default: disabled]\n");
	printf("\t\t-L for latency summary, -LL for detailed histogram\n");
	printf("\t[-l enable latency tracking via ssd (if supported), default: disabled]\n");
	printf("\t[-t time in seconds]\n");
	printf("\t[-c core mask for I/O submission/completion.]\n");
	printf("\t\t(default: 1)\n");
	printf("\t[-D disable submission queue in controller memory buffer, default: enabled]\n");
	printf("\t[-H enable header digest for TCP transport, default: disabled]\n");
	printf("\t[-I enable data digest for TCP transport, default: disabled]\n");
	printf("\t[-N no shutdown notification process for controllers, default: disabled]\n");
	printf("\t[-r Transport ID for local PCIe NVMe or NVMeoF]\n");
	printf("\t Format: 'key:value [key:value] ...'\n");
	printf("\t Keys:\n");
	printf("\t  trtype      Transport type (e.g. PCIe, RDMA)\n");
	printf("\t  adrfam      Address family (e.g. IPv4, IPv6)\n");
	printf("\t  traddr      Transport address (e.g. 0000:04:00.0 for PCIe or 192.168.100.8 for RDMA)\n");
	printf("\t  trsvcid     Transport service identifier (e.g. 4420)\n");
	printf("\t  subnqn      Subsystem NQN (default: %s)\n", SPDK_NVMF_DISCOVERY_NQN);
	printf("\t Example: -r 'trtype:PCIe traddr:0000:04:00.0' for PCIe or\n");
	printf("\t          -r 'trtype:RDMA adrfam:IPv4 traddr:192.168.100.8 trsvcid:4420' for NVMeoF\n");
	printf("\t[-e metadata configuration]\n");
	printf("\t Keys:\n");
	printf("\t  PRACT      Protection Information Action bit (PRACT=1 or PRACT=0)\n");
	printf("\t  PRCHK      Control of Protection Information Checking (PRCHK=GUARD|REFTAG|APPTAG)\n");
	printf("\t Example: -e 'PRACT=0,PRCHK=GUARD|REFTAG|APPTAG'\n");
	printf("\t          -e 'PRACT=1,PRCHK=GUARD'\n");
	printf("\t[-k keep alive timeout period in millisecond]\n");
	printf("\t[-s DPDK huge memory size in MB.]\n");
	printf("\t[-m max completions per poll]\n");
	printf("\t\t(default: 0 - unlimited)\n");
	printf("\t[-i shared memory group ID]\n");
	printf("\t");
	spdk_log_usage(stdout, "-T");
	printf("\t[-V enable VMD enumeration]\n");
#ifdef DEBUG
	printf("\t[-G enable debug logging]\n");
#else
	printf("\t[-G enable debug logging (flag disabled, must reconfigure with --enable-debug)\n");
#endif
}


static void
unregister_trids(void)
{
	struct trid_entry *trid_entry, *tmp;

	TAILQ_FOREACH_SAFE(trid_entry, &g_trid_list, tailq, tmp) {
		TAILQ_REMOVE(&g_trid_list, trid_entry, tailq);
		free(trid_entry);
	}
}

static int
add_trid(const char *trid_str)
{
	struct trid_entry *trid_entry;
	struct spdk_nvme_transport_id *trid;
	const char *ns;

	trid_entry = (struct trid_entry *)calloc(1, sizeof(*trid_entry));
	if (trid_entry == NULL) {
		return -1;
	}

	trid = &trid_entry->trid;
	trid->trtype = SPDK_NVME_TRANSPORT_PCIE;
	snprintf(trid->subnqn, sizeof(trid->subnqn), "%s", SPDK_NVMF_DISCOVERY_NQN);

	if (spdk_nvme_transport_id_parse(trid, trid_str) != 0) {
		fprintf(stderr, "Invalid transport ID format '%s'\n", trid_str);
		free(trid_entry);
		return 1;
	}

	ns = strcasestr(trid_str, "ns:");
	if (ns) {
		char nsid_str[6]; /* 5 digits maximum in an nsid */
		int len;
		int nsid;

		ns += 3;

		len = strcspn(ns, " \t\n");
		if (len > 5) {
			fprintf(stderr, "NVMe namespace IDs must be 5 digits or less\n");
			free(trid_entry);
			return 1;
		}

		memcpy(nsid_str, ns, len);
		nsid_str[len] = '\0';

		nsid = spdk_strtol(nsid_str, 10);
		if (nsid <= 0 || nsid > 65535) {
			fprintf(stderr, "NVMe namespace IDs must be less than 65536 and greater than 0\n");
			free(trid_entry);
			return 1;
		}

		trid_entry->nsid = (uint16_t)nsid;
	}

	TAILQ_INSERT_TAIL(&g_trid_list, trid_entry, tailq);
	return 0;
}

static size_t
parse_next_key(const char **str, char *key, char *val, size_t key_buf_size,
	       size_t val_buf_size)
{
	const char *sep;
	const char *separator = ", \t\n";
	size_t key_len, val_len;

	*str += strspn(*str, separator);

	sep = strchr(*str, '=');
	if (!sep) {
		fprintf(stderr, "Key without '=' separator\n");
		return 0;
	}

	key_len = sep - *str;
	if (key_len >= key_buf_size) {
		fprintf(stderr, "Key length %zu is greater than maximum allowed %zu\n",
			key_len, key_buf_size - 1);
		return 0;
	}

	memcpy(key, *str, key_len);
	key[key_len] = '\0';

	*str += key_len + 1;	/* Skip key */
	val_len = strcspn(*str, separator);
	if (val_len == 0) {
		fprintf(stderr, "Key without value\n");
		return 0;
	}

	if (val_len >= val_buf_size) {
		fprintf(stderr, "Value length %zu is greater than maximum allowed %zu\n",
			val_len, val_buf_size - 1);
		return 0;
	}

	memcpy(val, *str, val_len);
	val[val_len] = '\0';

	*str += val_len;

	return val_len;
}

static int
parse_metadata(const char *metacfg_str)
{
	const char *str;
	size_t val_len;
	char key[32];
	char val[1024];

	if (metacfg_str == NULL) {
		return -EINVAL;
	}

	str = metacfg_str;

	while (*str != '\0') {
		val_len = parse_next_key(&str, key, val, sizeof(key), sizeof(val));
		if (val_len == 0) {
			fprintf(stderr, "Failed to parse metadata\n");
			return -EINVAL;
		}

		if (strcmp(key, "PRACT") == 0) {
			if (*val == '1') {
				g_metacfg_pract_flag = SPDK_NVME_IO_FLAGS_PRACT;
			}
		} else if (strcmp(key, "PRCHK") == 0) {
			if (strstr(val, "GUARD") != NULL) {
				g_metacfg_prchk_flags |= SPDK_NVME_IO_FLAGS_PRCHK_GUARD;
			}
			if (strstr(val, "REFTAG") != NULL) {
				g_metacfg_prchk_flags |= SPDK_NVME_IO_FLAGS_PRCHK_REFTAG;
			}
			if (strstr(val, "APPTAG") != NULL) {
				g_metacfg_prchk_flags |= SPDK_NVME_IO_FLAGS_PRCHK_APPTAG;
			}
		} else {
			fprintf(stderr, "Unknown key '%s'\n", key);
		}
	}

	return 0;
}

static int
parse_args(int argc, char **argv)
{
	const char *workload_type;
	int op;
	bool mix_specified = false;
	long int val;
	int rc;

	/* default value */
	g_queue_depth = 0;
	g_io_size_bytes = 0;
	workload_type = NULL;
	g_time_in_sec = 0;
	g_rw_percentage = -1;
	g_core_mask = NULL;
	g_max_completions = 0;

	while ((op = getopt(argc, argv, "c:e:i:lm:n:o:q:r:k:s:t:w:DGHILM:NT:U:V")) != -1) {
		switch (op) {
		case 'i':
		case 'm':
		case 'n':
		case 'o':
		case 'q':
		case 'k':
		case 's':
		case 't':
		case 'M':
		case 'U':
			val = spdk_strtol(optarg, 10);
			if (val < 0) {
				fprintf(stderr, "Converting a string to integer failed\n");
				return val;
			}
			switch (op) {
			case 'i':
				g_shm_id = val;
				break;
			case 'm':
				g_max_completions = val;
				break;
			case 'n':
				g_nr_io_queues_per_ns = val;
				break;
			case 'o':
				g_io_size_bytes = val;
				break;
			case 'q':
				g_queue_depth = val;
				break;
			case 'k':
				g_keep_alive_timeout_in_ms = val;
				break;
			case 's':
				g_dpdk_mem = val;
				break;
			case 't':
				g_time_in_sec = val;
				break;
			case 'M':
				g_rw_percentage = val;
				mix_specified = true;
				break;
			case 'U':
				g_nr_unused_io_queues = val;
				break;
			}
			break;
		case 'c':
			g_core_mask = optarg;
			break;
		case 'e':
			if (parse_metadata(optarg)) {
				usage(argv[0]);
				return 1;
			}
			break;
		case 'l':
			g_latency_ssd_tracking_enable = true;
			break;
		case 'r':
			if (add_trid(optarg)) {
				usage(argv[0]);
				return 1;
			}
			break;
		case 'w':
			workload_type = optarg;
			break;
		case 'D':
			g_disable_sq_cmb = 1;
			break;
		case 'G':
#ifndef DEBUG
			fprintf(stderr, "%s must be configured with --enable-debug for -G flag\n",
				argv[0]);
			usage(argv[0]);
			return 1;
#else
			spdk_log_set_flag("nvme");
			spdk_log_set_print_level(SPDK_LOG_DEBUG);
			break;
#endif
		case 'H':
			g_header_digest = 1;
			break;
		case 'I':
			g_data_digest = 1;
			break;
		case 'L':
			g_latency_sw_tracking_level++;
			break;
		case 'N':
			g_no_shn_notification = true;
			break;
		case 'T':
			rc = spdk_log_set_flag(optarg);
			if (rc < 0) {
				fprintf(stderr, "unknown flag\n");
				usage(argv[0]);
				exit(EXIT_FAILURE);
			}
			spdk_log_set_print_level(SPDK_LOG_DEBUG);
#ifndef DEBUG
			fprintf(stderr, "%s must be rebuilt with CONFIG_DEBUG=y for -T flag.\n",
				argv[0]);
			usage(argv[0]);
			return 0;
#endif
			break;
		case 'V':
			g_vmd = true;
			break;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	if (!g_nr_io_queues_per_ns) {
		usage(argv[0]);
		return 1;
	}

	if (!g_queue_depth) {
		usage(argv[0]);
		return 1;
	}
	if (!g_io_size_bytes) {
		usage(argv[0]);
		return 1;
	}
	if (!workload_type) {
		usage(argv[0]);
		return 1;
	}
	if (!g_time_in_sec) {
		usage(argv[0]);
		return 1;
	}

	if (strcmp(workload_type, "read") &&
	    strcmp(workload_type, "write") &&
	    strcmp(workload_type, "randread") &&
	    strcmp(workload_type, "randwrite") &&
	    strcmp(workload_type, "rw") &&
	    strcmp(workload_type, "randrw")) {
		fprintf(stderr,
			"io pattern type must be one of\n"
			"(read, write, randread, randwrite, rw, randrw)\n");
		return 1;
	}

	if (!strcmp(workload_type, "read") ||
	    !strcmp(workload_type, "randread")) {
		g_rw_percentage = 100;
	}

	if (!strcmp(workload_type, "write") ||
	    !strcmp(workload_type, "randwrite")) {
		g_rw_percentage = 0;
	}

	if (!strcmp(workload_type, "read") ||
	    !strcmp(workload_type, "randread") ||
	    !strcmp(workload_type, "write") ||
	    !strcmp(workload_type, "randwrite")) {
		if (mix_specified) {
			fprintf(stderr, "Ignoring -M option... Please use -M option"
				" only when using rw or randrw.\n");
		}
	}

	if (!strcmp(workload_type, "rw") ||
	    !strcmp(workload_type, "randrw")) {
		if (g_rw_percentage < 0 || g_rw_percentage > 100) {
			fprintf(stderr,
				"-M must be specified to value from 0 to 100 "
				"for rw or randrw.\n");
			return 1;
		}
	}

	if (!strcmp(workload_type, "read") ||
	    !strcmp(workload_type, "write") ||
	    !strcmp(workload_type, "rw")) {
		g_is_random = 0;
	} else {
		g_is_random = 1;
	}

	if (TAILQ_EMPTY(&g_trid_list)) {
		/* If no transport IDs specified, default to enumerating all local PCIe devices */
		add_trid("trtype:PCIe");
	} else {
		struct trid_entry *trid_entry, *trid_entry_tmp;

		g_no_pci = true;
		/* check whether there is local PCIe type */
		TAILQ_FOREACH_SAFE(trid_entry, &g_trid_list, tailq, trid_entry_tmp) {
			if (trid_entry->trid.trtype == SPDK_NVME_TRANSPORT_PCIE) {
				g_no_pci = false;
				break;
			}
		}
	}

	g_aio_optind = optind;

	return 0;
}

static bool
probe_cb(void *cb_ctx, const struct spdk_nvme_transport_id *trid,
	 struct spdk_nvme_ctrlr_opts *opts)
{
	if (trid->trtype == SPDK_NVME_TRANSPORT_PCIE) {
		if (g_disable_sq_cmb) {
			opts->use_cmb_sqs = false;
		}
		if (g_no_shn_notification) {
			opts->no_shn_notification = true;
		}
	}

	/* Set io_queue_size to UINT16_MAX, NVMe driver
	 * will then reduce this to MQES to maximize
	 * the io_queue_size as much as possible.
	 */
	opts->io_queue_size = UINT16_MAX;

	/* Set the header and data_digest */
	opts->header_digest = g_header_digest;
	opts->data_digest = g_data_digest;
	opts->keep_alive_timeout_ms = spdk_max(opts->keep_alive_timeout_ms,
					       g_keep_alive_timeout_in_ms);

	return true;
}

static void
attach_cb(void *cb_ctx, const struct spdk_nvme_transport_id *trid,
	  struct spdk_nvme_ctrlr *ctrlr, const struct spdk_nvme_ctrlr_opts *opts)
{
	struct trid_entry	*trid_entry = (struct trid_entry *)cb_ctx;
	struct spdk_pci_addr	pci_addr;
	struct spdk_pci_device	*pci_dev;
	struct spdk_pci_id	pci_id;

	if (trid->trtype != SPDK_NVME_TRANSPORT_PCIE) {
		printf("Attached to NVMe over Fabrics controller at %s:%s: %s\n",
		       trid->traddr, trid->trsvcid,
		       trid->subnqn);
	} else {
		if (spdk_pci_addr_parse(&pci_addr, trid->traddr)) {
			return;
		}

		pci_dev = spdk_nvme_ctrlr_get_pci_device(ctrlr);
		if (!pci_dev) {
			return;
		}

		pci_id = spdk_pci_device_get_id(pci_dev);

		printf("Attached to NVMe Controller at %s [%04x:%04x]\n",
		       trid->traddr,
		       pci_id.vendor_id, pci_id.device_id);
	}

	register_ctrlr(ctrlr, trid_entry);
}

static int
register_controllers(void)
{
	struct trid_entry *trid_entry;

	printf("Initializing NVMe Controllers\n");

	if (g_vmd && spdk_vmd_init()) {
		fprintf(stderr, "Failed to initialize VMD."
			" Some NVMe devices can be unavailable.\n");
	}

	TAILQ_FOREACH(trid_entry, &g_trid_list, tailq) {
		if (spdk_nvme_probe(&trid_entry->trid, trid_entry, probe_cb, attach_cb, NULL) != 0) {
			fprintf(stderr, "spdk_nvme_probe() failed for transport address '%s'\n",
				trid_entry->trid.traddr);
			return -1;
		}
	}

	return 0;
}

static void
unregister_controllers(void)
{
	struct ctrlr_entry *entry = g_controllers;

	while (entry) {
		struct ctrlr_entry *next = entry->next;
		spdk_dma_free(entry->latency_page);

		if (g_nr_unused_io_queues) {
			int i;

			for (i = 0; i < g_nr_unused_io_queues; i++) {
				spdk_nvme_ctrlr_free_io_qpair(entry->unused_qpairs[i]);
			}

			free(entry->unused_qpairs);
		}

		spdk_nvme_detach(entry->ctrlr);
		free(entry);
		entry = next;
	}
}

static void *
nvme_poll_ctrlrs(void *arg)
{
	struct ctrlr_entry *entry;
	int oldstate;

	spdk_unaffinitize_thread();

	while (true) {
		pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &oldstate);

		entry = g_controllers;
		while (entry) {
			if (entry->trtype != SPDK_NVME_TRANSPORT_PCIE) {
				spdk_nvme_ctrlr_process_admin_completions(entry->ctrlr);
			}
			entry = entry->next;
		}

		pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, &oldstate);

		/* This is a pthread cancellation point and cannot be removed. */
		sleep(1);
	}

	return NULL;
}

struct lba_ranges {
	uint32_t phys_lba_start;
	uint32_t lba_count;
};

struct nvme_file_reader_ctx;

struct nvme_file_read_io_ctx {
	struct nvme_file_reader_ctx* main;
	uint32_t idx;			//idx of this IO request
	uint32_t lba_count;		//count of lba's to be read in this request
};

struct nvme_file_reader_ctx {
	struct spdk_nvme_ctrlr*	ctrlr;
	struct spdk_nvme_ns*	ns;
	struct spdk_nvme_qpair*	qpair;

	uint32_t				qdepth;
	struct nvme_file_read_io_ctx* reqs;

	uint32_t 				max_lba_per_io;

	struct iovec			data;

	uint32_t				lba_ranges_count;
	struct lba_ranges*		lba_ranges;

	uint32_t				lba_array_idx;	//current idx in lba_ranges
	uint32_t 				lba_idx;		//current number of lba in lba_ranges
	uint32_t 				lba_count;		//total number of lba's
	uint32_t 				lba_read;		//number of lba already read
	uint32_t 				lba_submitted_to_read;	//number of lba's submitted to read but not completted yet

	uint32_t 				file_size;		//in bytes
	uint32_t 				dev_block_size;
};

int fill_lba_ranges(const char* filepath, struct nvme_file_reader_ctx* ctx)
{
	int flags, fd;
	int bs;
	uint32_t bs_log2;
	int rc = 0;

	flags = O_DIRECT | O_RDONLY;

	fd = open(filepath, flags);
	if (fd < 0) {
		fprintf(stderr, "Could not open AIO device %s: %s\n", filepath, strerror(errno));
		return -1;
	}

	ctx->file_size = spdk_fd_get_size(fd);
	printf("file size %lu\n", ctx->file_size);
	if (ctx->file_size == 0) {
		fprintf(stderr, "Could not determine size of AIO device %s\n", filepath);
		close(fd);
		return -1;
	}

	if (ioctl(fd, FIGETBSZ, &bs) < 0) {
		printf("failed to get block size\n");
		close(fd);
		return -1;
	}

	ctx->lba_count = (ctx->file_size + (ctx->dev_block_size - 1)) / ctx->dev_block_size;
	bs_log2 = spdk_u32log2(ctx->dev_block_size);
	printf("device block size %d (%u)\n", bs, bs_log2);
	printf("file uses %u blocks\n", ctx->lba_count);

	union { struct fiemap f; char c[4096]; } fiemap_buf;
	struct fiemap *fiemap = &fiemap_buf.f;
	struct fiemap_extent *fm_extents = &fiemap->fm_extents[0];
	enum { count = (sizeof fiemap_buf - sizeof (*fiemap))/sizeof (*fm_extents) };
	memset (&fiemap_buf, 0, sizeof fiemap_buf);

	fiemap->fm_extent_count = count;
	fiemap->fm_length = FIEMAP_MAX_OFFSET;

	rc = ioctl (fd, FS_IOC_FIEMAP, fiemap);
	if(rc) {
		printf("ioctl failed, rc %d errno %d\n", rc, errno);
		return rc;
	}

	printf("fiemap: extents %u fm_flags %u\n",
		   fiemap->fm_mapped_extents, fiemap->fm_flags);

	if(fiemap->fm_mapped_extents == 0) {
		fprintf(stderr, "fiemap contains 0 extents\n");
		return -1;
	}
	ctx->lba_ranges_count = fiemap->fm_mapped_extents;
	ctx->lba_ranges = (struct lba_ranges*)calloc(ctx->lba_ranges_count, sizeof(*ctx->lba_ranges));

	for(uint32_t j = 0; j < fiemap->fm_mapped_extents; j++) {
		uint32_t length = fm_extents[j].fe_length >> bs_log2;
		uint32_t logical_start = fm_extents[j].fe_logical >> bs_log2;
		uint32_t physical_start = fm_extents[j].fe_physical >> bs_log2;
		printf("[%4u]: logical %8u .. %8u \tphysical %8u .. %8u \tlen %8u\n",
			   j, logical_start, logical_start + length -1,
			   physical_start, physical_start + length - 1, length);

		ctx->lba_ranges[j].phys_lba_start = physical_start;
		ctx->lba_ranges[j].lba_count = length;
	}

	close(fd);

	return 0;
}

int file_read_submit_io(struct nvme_file_read_io_ctx* ctx);

void file_read_complete_io(void *ctx , const struct spdk_nvme_cpl *cpl)
{
	struct nvme_file_read_io_ctx* req_ctx = (struct nvme_file_read_io_ctx*)ctx;
	struct nvme_file_reader_ctx* read_ctx = req_ctx->main;
	if (spdk_unlikely(spdk_nvme_cpl_is_error(cpl))) {
		fprintf(stderr, "read completed with error (sct=%d, sc=%d)\n",
				cpl->status.sct, cpl->status.sc);
	}

//	printf("completed req %u with lbas %u. Total %u/%u\n", req_ctx->idx,
//			req_ctx->lba_count, read_ctx->lba_read, read_ctx->lba_count);
	read_ctx->lba_read += req_ctx->lba_count;
	assert(read_ctx->lba_read <= read_ctx->lba_count);

	if(read_ctx->lba_read < read_ctx->lba_count) {
		file_read_submit_io(req_ctx);
	}
}

int file_read_submit_io(struct nvme_file_read_io_ctx* req_ctx)
{
	struct nvme_file_reader_ctx* ctx = req_ctx->main;
	int rc = 0;
//	printf("submit start, read %u / %u, array %u / %u\n",
//		   ctx->lba_read, ctx->lba_count, ctx->lba_array_idx, ctx->lba_ranges_count);
	if (ctx->lba_read >= ctx->lba_count || ctx->lba_array_idx >= ctx->lba_ranges_count) {
//		printf("all io requests already issued\n");
		return rc;
	}

	uint32_t lba_count = spdk_min(ctx->lba_ranges[ctx->lba_array_idx].lba_count - ctx->lba_idx, ctx->max_lba_per_io);
	void* payload_ptr = ((char*)ctx->data.iov_base) + ctx->lba_submitted_to_read * ctx->dev_block_size;
	uint32_t start_lba = ctx->lba_ranges[ctx->lba_array_idx].phys_lba_start + ctx->lba_idx;
	ctx->lba_submitted_to_read += lba_count;

//	printf("iov_base %p, current %p; lba[%u] start %u, count %u - read %u/%u\n",
//		   ctx->data.iov_base, payload_ptr, ctx->lba_array_idx, start_lba, lba_count, ctx->lba_read, ctx->lba_count);

	ctx->lba_idx += lba_count;
	req_ctx->lba_count = lba_count;
	assert(ctx->lba_idx <= ctx->lba_ranges[ctx->lba_array_idx].lba_count);

	if(ctx->lba_idx  >= ctx->lba_ranges[ctx->lba_array_idx].lba_count) {
//		printf("range %u completed, switch to the next\n", ctx->lba_array_idx);
		ctx->lba_array_idx++;
		ctx->lba_idx = 0;
	}

	rc = spdk_nvme_ns_cmd_read_with_md(ctx->ns, ctx->qpair, payload_ptr, NULL, start_lba, lba_count, file_read_complete_io,
									   req_ctx, 0, 0, 0);
	if(rc) {
		fprintf(stderr,"nvme read failed with %d\n", rc);
	}

	return rc;
}

__global__
void print_gpu_mem(char* c, int n)
{
	for (int i = 0; i < n; i++) {
		printf("%c", c[i]);
	}
	printf("\n");
}

struct nvme_file_read_ibv {
	struct ibv_context* context;
	struct ibv_pd* pd;
	struct ibv_mr* mr;
};

struct nvme_file_read_ibv* g_perf_ibv;
int g_perf_ibv_num_contexts;

struct ibv_mr* perf_get_mr(struct ibv_pd *pd, void *buf, size_t* size)
{
	assert(g_perf_ibv);
//	printf("addr %p size %zu\n", buf, size);
	for (int i = 0; i < g_perf_ibv_num_contexts; i++) {
		if(g_perf_ibv[i].pd == pd) {
			if(g_perf_ibv[i].mr) {
//				printf("match %d\n", i);
				assert((char*)buf >= (char*)g_perf_ibv[i].mr->addr);
				int64_t available = (int64_t)g_perf_ibv[i].mr->length - ((char*)g_perf_ibv[i].mr->addr - (char*)buf);
				if (available < 0 || available < (int64_t)*size) {
					fprintf(stderr, "request %zu bytes, available %ld\n", *size, available);
					*size = 0;
					return NULL;
				}
				*size = (size_t)available;
				return g_perf_ibv[i].mr;
			}
		}
	}
//	assert(0);
	return NULL;
}

struct ibv_pd* perf_get_pd(const struct spdk_nvme_transport_id *trid,
							 struct ibv_context *verbs)
{
	assert(g_perf_ibv);
	printf("verbs %p\n", verbs);
	for(uint32_t i = 0; i < g_perf_ibv_num_contexts; i++) {
		if(g_perf_ibv[i].context == verbs) {
			printf("match at idx %u\n", i);
			return g_perf_ibv[i].pd;
		}
	}
	assert(0);
	return NULL;
}

struct spdk_nvme_rdma_hooks g_perf_hooks = {
		.get_ibv_pd = perf_get_pd,
		.get_rkey = NULL,
		.get_user_mr = perf_get_mr
};

int alloc_ctx_and_pd(struct nvme_file_read_ibv** ctx, int* num)
{
	struct ibv_context ** contexts = rdma_get_devices(num);
	if (contexts == NULL) {
		fprintf(stderr, "failed to retrieve ibv devices\n");
		return -1;
	}
	printf("got %u ibv devices\n", *num);
	*ctx = (struct nvme_file_read_ibv*)calloc(*num, sizeof(struct nvme_file_read_ibv));

	for (int i = 0; i < *num; i++) {
		(*ctx)[i].context = contexts[i];
		(*ctx)[i].pd = ibv_alloc_pd(contexts[i]);
		if (!(*ctx)[i].pd) {
			fprintf(stderr, "failed to alloc PD\n");
			return -1;
		}
	}

	rdma_free_devices(contexts);

	return 0;
}

void free_mr_and_pd(struct nvme_file_read_ibv * ctx, int num)
{
	if(ctx) {
		for (int i = 0; i < num; i++) {
			if(ctx[i].pd) {
				ibv_dealloc_pd(ctx[i].pd);
			}
			if(ctx[i].mr) {
				ibv_dereg_mr(ctx[i].mr);
			}
		}
	}

	free(ctx);
}

int main(int argc, char **argv)
{
	int rc;
	struct worker_thread *worker, *master_worker;
	struct spdk_env_opts opts;
	struct nvme_file_reader_ctx read_ctx = {};
	struct spdk_nvme_io_qpair_opts qopts;

	int num_ibv_devices;
	pthread_t thread_id = 0;
	cudaError_t res;

	rc = parse_args(argc, argv);
	if (rc != 0) {
		return rc;
	}

	spdk_env_opts_init(&opts);
	opts.name = "perf";
	opts.shm_id = g_shm_id;
	if (g_core_mask) {
		opts.core_mask = g_core_mask;
	}

	if (g_dpdk_mem) {
		opts.mem_size = g_dpdk_mem;
	}
	if (g_no_pci) {
		opts.no_pci = g_no_pci;
	}
	if (spdk_env_init(&opts) < 0) {
		fprintf(stderr, "Unable to initialize SPDK env\n");
		rc = -1;
		goto cleanup;
	}

	g_tsc_rate = spdk_get_ticks_hz();

	////////////////////////////////////////////////////////

	if (alloc_ctx_and_pd(&g_perf_ibv, &g_perf_ibv_num_contexts) != 0) {
		fprintf(stderr, "failed to alloc PDs\n");
		rc = -1;
		goto cleanup;
	}

	spdk_nvme_rdma_init_hooks(&g_perf_hooks);

	if (register_controllers() != 0) {
		rc = -1;
		goto cleanup;
	}

	if (g_warn) {
		printf("WARNING: Some requested NVMe devices were skipped\n");
	}

	if (g_num_namespaces == 0) {
		fprintf(stderr, "No valid NVMe controllers or AIO devices found\n");
		goto cleanup;
	}

	rc = pthread_create(&thread_id, NULL, &nvme_poll_ctrlrs, NULL);
	if (rc != 0) {
		fprintf(stderr, "Unable to spawn a thread to poll admin queues.\n");
		goto cleanup;
	}

	read_ctx.ctrlr	= g_controllers->ctrlr;
	read_ctx.ns		= g_namespaces->u.nvme.ns;


	spdk_nvme_ctrlr_get_default_io_qpair_opts(read_ctx.ctrlr, &qopts, sizeof(qopts));
	qopts.io_queue_requests = g_queue_depth * 4;
	qopts.io_queue_size = g_queue_depth;
	read_ctx.qdepth = qopts.io_queue_size;
	printf("creating io qpair, depth %u num_requests %u\n", qopts.io_queue_size, qopts.io_queue_requests);

	read_ctx.qpair = spdk_nvme_ctrlr_alloc_io_qpair(read_ctx.ctrlr, &qopts, sizeof(qopts));
	if(!read_ctx.qpair) {
		fprintf(stderr, "failed to create IO qpair\n");
		rc = -1;
		goto cleanup;
	}

	read_ctx.reqs = (struct nvme_file_read_io_ctx*)calloc(read_ctx.qdepth, sizeof(*read_ctx.reqs));
	for (uint32_t i = 0; i < read_ctx.qdepth; i++) {
		read_ctx.reqs[i].main = &read_ctx;
		read_ctx.reqs[i].idx = i;
	}

	read_ctx.dev_block_size = spdk_nvme_ns_get_sector_size(read_ctx.ns);

	////////////////////////////////////////////////////////

	printf("treat argv[%d] = %s as a file name\n", g_aio_optind, argv[g_aio_optind]);

	rc = fill_lba_ranges(argv[g_aio_optind], &read_ctx);
	if (rc) {
		fprintf(stderr, "file parsing failed");
		goto cleanup;
	}
	////////////////////////////////////////////////////////

	read_ctx.max_lba_per_io = spdk_nvme_ctrlr_get_max_xfer_size(read_ctx.ctrlr) / read_ctx.dev_block_size;
	read_ctx.data.iov_len = read_ctx.lba_count * read_ctx.dev_block_size;

#ifdef CUDA_DRAM
	read_ctx.data.iov_base = spdk_dma_zmalloc(read_ctx.data.iov_len, g_io_align, NULL);

	res = cudaHostRegister(read_ctx.data.iov_base, read_ctx.data.iov_len, cudaHostRegisterDefault);
	if(res != cudaSuccess) {
		fprintf(stderr, "cudaHostRegister failed with %d\n", res);
		rc = -1;
		goto cleanup;
	}
#else
	 res = cudaMalloc(&read_ctx.data.iov_base, read_ctx.data.iov_len);
	if (res != CUDA_SUCCESS) {
		fprintf(stderr, "failed to allocate GPU memory\n");
		rc = -1;
		goto cleanup;
	}

#endif

	for (int i = 0; i < g_perf_ibv_num_contexts; i++) {
		g_perf_ibv[i].mr = ibv_reg_mr(g_perf_ibv[i].pd, read_ctx.data.iov_base, read_ctx.data.iov_len,
				IBV_ACCESS_REMOTE_WRITE | IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_READ);
		if (g_perf_ibv[i].mr == NULL) {
			fprintf(stderr, "failed to register MR, errno %d\n", errno);
			rc = -1;
			goto cleanup;
		}
	}

	for(uint32_t i = 0; i < read_ctx.qdepth; i++) {
		file_read_submit_io(&read_ctx.reqs[i]);
	}

	while (read_ctx.lba_read < read_ctx.lba_count)
	{
		int completions = spdk_nvme_qpair_process_completions(read_ctx.qpair, read_ctx.qdepth);
		if(completions < 0) {
			fprintf(stderr, "process_completions failed with %d\n", completions);
			exit(1);
		}
	}

	printf("Done!\n");

#ifdef CUDA_DRAM
	printf("CPU 150 symbols:\n\n");

	for(uint32_t i = 0; i < 150; i++) {
		printf("%c", ((char*)read_ctx.data.iov_base)[i]);
	}
	printf("\n");
#endif

	printf("Running kernel to print 150 symbols\n");
	print_gpu_mem<<<1, 1>>>((char*)read_ctx.data.iov_base, 150);

cleanup:
	if (thread_id && pthread_cancel(thread_id) == 0) {
		pthread_join(thread_id, NULL);
	}

	if (read_ctx.lba_ranges) {
		free(read_ctx.lba_ranges);
	}

	if (g_perf_ibv) {
		free_mr_and_pd(g_perf_ibv, g_perf_ibv_num_contexts);
	}

	if (read_ctx.data.iov_base) {
#ifdef CUDA_DRAM
		cudaHostUnregister(read_ctx.data.iov_base);
		spdk_dma_free(read_ctx.data.iov_base);
#else
		cudaFree(read_ctx.data.iov_base);
#endif
	}

	if(read_ctx.qpair) {
		spdk_nvme_ctrlr_free_io_qpair(read_ctx.qpair);
	}

	unregister_trids();
	unregister_namespaces();
	unregister_controllers();

	if (rc != 0) {
		fprintf(stderr, "%s: errors occured\n", argv[0]);
	}

	return rc;
}
