#ifndef _RDMA_HOOKS_
#define  _RDMA_HOOKS_

#include <rdma/rdma_cma.h>

struct nvme_file_read_ibv {
	struct ibv_context* context;
	struct ibv_pd* pd;
	struct ibv_mr* mr;
};


extern struct nvme_file_read_ibv* g_perf_ibv;
extern int g_perf_ibv_num_contexts;
extern struct spdk_nvme_rdma_hooks g_perf_hooks;
void free_mr_and_pd(struct nvme_file_read_ibv * ctx, int num);
int alloc_ctx_and_pd(struct nvme_file_read_ibv** ctx, int* num);
struct ibv_pd* perf_get_pd(const struct spdk_nvme_transport_id *trid,
							 struct ibv_context *verbs);
struct ibv_mr* perf_get_mr(struct ibv_pd *pd, void *buf, size_t* size);

#endif
