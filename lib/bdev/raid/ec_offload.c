#include "ec_offload.h"
#include "spdk/stdinc.h"
#include "spdk_internal/log.h"


struct ec_offload_context *
ec_offload_init_ctx(struct ec_offload_opts *opts)
{
	struct ec_offload_context *ctx;
	int err;

	ctx = calloc(1, sizeof(*ctx));
	if (!ctx) {
		fprintf(stderr, "Failed to allocate EC context\n");
		return NULL;
	}

	ctx->dev = find_device(opts->devname);
	if (!ctx->dev) {
		fprintf(stderr, "Couldn't find device %s\n",
			opts->devname);
		goto free_ctx;
	}

	ctx->context = ibv_open_device(ctx->dev);
	if (!ctx->context) {
		fprintf(stderr, "Couldn't get context for %s\n",
			ibv_get_device_name(ctx->dev));
		goto free_ctx;
	}

	ctx->pd = ibv_alloc_pd(ctx->context);
	if (!ctx->pd) {
		fprintf(stderr, "Failed to allocate PD\n");
		goto close_device;
	}

	SPDK_NOTICELOG("EC offload: allocate context: frame size %u, K %d, M %d, W %d, failed blocks %s\n",
		       opts->frame_size,
		       opts->k,
		       opts->m,
		       opts->w,
		       opts->failed_blocks);
	ctx->ec_ctx = alloc_ec_ctx(ctx->pd,
				   opts->frame_size,
				   opts->k, opts->m, opts->w,
				   0, /* affinity */
				   1, /* max_inflight_calcs */
				   opts->failed_blocks,
				   NULL, NULL);
	if (!ctx->ec_ctx) {
		fprintf(stderr, "Failed to allocate EC context\n");
		goto dealloc_pd;
	}

	return ctx;

 free_ec:
	free_ec_ctx(ctx->ec_ctx);
 dealloc_pd:
	ibv_dealloc_pd(ctx->pd);
 close_device:
	ibv_close_device(ctx->context);
 free_ctx:
	free(ctx);

	return NULL;
}

void
ec_offload_close_ctx(struct ec_offload_context *ctx)
{
	free_ec_ctx(ctx->ec_ctx);
	ibv_dealloc_pd(ctx->pd);

	if (ibv_close_device(ctx->context))
		fprintf(stderr, "Couldn't release context\n");

	free(ctx);
}

int
ec_offload_decode_block_sync(struct ec_offload_context *ctx,
			     char* data,
			     char* code)
{
	struct ec_context *ec_ctx = ctx->ec_ctx;
	int err;

	memcpy(ec_ctx->data.buf, data,
	       ec_ctx->block_size * ec_ctx->attr.k);

	memcpy(ec_ctx->code.buf, code,
	       ec_ctx->block_size * ec_ctx->attr.m);

	err = ibv_exp_ec_decode_sync(ec_ctx->calc, &ec_ctx->mem,
				     ec_ctx->erasures, ec_ctx->de_mat);
	if (err) {
		fprintf(stderr, "Failed ibv_exp_ec_decode (%d)\n", err);
		return err;
	}

	memcpy(data, ec_ctx->data.buf,
	       ec_ctx->block_size * ec_ctx->attr.k);

	memcpy(code, ec_ctx->code.buf,
	       ec_ctx->block_size * ec_ctx->attr.m);

	return 0;
}

int
ec_offload_encode_block_sync(struct ec_offload_context *ctx,
			     char* data,
			     char* code)
{
	struct ec_context *ec_ctx = ctx->ec_ctx;
	int err;

	memcpy(ec_ctx->data.buf, data,
	       ec_ctx->block_size * ec_ctx->attr.k);

	err = ibv_exp_ec_encode_sync(ec_ctx->calc, &ec_ctx->mem);
	if (err) {
		fprintf(stderr, "Failed ibv_exp_ec_encode (%d)\n", err);
		return err;
	}

	memcpy(code, ec_ctx->code.buf,
	       ec_ctx->block_size * ec_ctx->attr.m);

	return 0;
}
