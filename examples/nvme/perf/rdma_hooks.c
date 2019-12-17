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
#include <rdma/rdma_cma.h>
#include "rdma_hooks.h"

struct nvme_file_read_ibv* g_perf_ibv;
int g_perf_ibv_num_contexts;

struct ibv_mr* perf_get_mr(struct ibv_pd *pd, void *buf, size_t* size)
{
	assert(g_perf_ibv);
//	printf("DEBUG !!!! pd %p addr %p size %zu\n",pd,  buf, *size);

//	printf("DEBUG !!!! g_perf_ibv_num_contexts = %d\n", g_perf_ibv_num_contexts);

	for (int i = 0; i < g_perf_ibv_num_contexts; i++) {
		if(g_perf_ibv[i].pd == pd) {
			if(g_perf_ibv[i].mr) {
//				printf("DEBUG !!! match %d\n", i);
//				assert((char*)buf >= (char*)g_perf_ibv[i].mr->addr);
				if ((char*)buf < (char*)g_perf_ibv[i].mr->addr || (char*)buf > (char*)g_perf_ibv[i].mr->addr + (int64_t)g_perf_ibv[i].mr->length) {
//					*size = 0;
					return NULL;
				}
				int64_t available = (int64_t)g_perf_ibv[i].mr->length - ((char*)g_perf_ibv[i].mr->addr - (char*)buf);
				if (available < 0 || available < (int64_t)*size) {
					fprintf(stderr, "request %zu bytes, available %ld\n", *size, available);
//					*size = 0;
					return NULL;
				}
				*size = (size_t)available;

//				printf("buf = %p, size = %d mr = %p \n", buf, *size, g_perf_ibv[i].mr);

				return g_perf_ibv[i].mr;
			}
		} else {
//fprintf(stderr, "NO PD FOUND\n");
		}
	}
//	assert(0);
//	*size = 0;
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

