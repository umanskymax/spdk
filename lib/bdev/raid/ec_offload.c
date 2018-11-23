#include "ec_offload.h"
#include "spdk/stdinc.h"
#include "spdk/util.h"
#include "spdk_internal/log.h"


static int
async_encode_poll(void *ctx);

struct ec_offload_context *
ec_offload_init_ctx(struct ec_offload_opts *opts)
{
	struct ec_offload_context *ctx;

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

static void
async_encode_done(struct ibv_exp_ec_comp *ib_comp);

struct ec_offload_context *
ec_offload_init_async_ctx(struct ec_offload_opts *opts)
{
	struct ec_offload_context *ctx;
	int i;

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

	SPDK_NOTICELOG("EC offload ctx %p: allocate async context: frame size %u, K %d, M %d, W %d, failed blocks %s, max_inflight %d\n",
		       ctx,
		       opts->frame_size,
		       opts->k,
		       opts->m,
		       opts->w,
		       opts->failed_blocks,
		       opts->max_inflight_calcs);
	ctx->ec_async_ctx = alloc_async_ec_ctx(ctx->pd,
					       opts->frame_size,
					       opts->k, opts->m, opts->w,
					       0, /* affinity */
					       opts->max_inflight_calcs,
					       1, /* polling */
					       0, /* in memory */
					       NULL /* failed blocks */);
	if (!ctx->ec_async_ctx) {
		fprintf(stderr, "Failed to allocate EC context\n");
		goto dealloc_pd;
	}

	ctx->async_encode_done_cb = opts->async_encode_done_cb;
	for(i = 0 ; i < opts->max_inflight_calcs ; i++) {
		ctx->ec_async_ctx->comp[i].comp.done = async_encode_done;
		ctx->ec_async_ctx->comp[i].user_ctx = ctx;
	}
	ctx->poller = spdk_poller_register(async_encode_poll, ctx, 0);
	if (!ctx->poller) {
		err_log("Failed to create EC offload poller\n");
		goto free_ec;
	}

	return ctx;

 free_ec:
	free_async_ec_ctx(ctx->ec_async_ctx);
 dealloc_pd:
	ibv_dealloc_pd(ctx->pd);
 close_device:
	ibv_close_device(ctx->context);
 free_ctx:
	free(ctx);

	return NULL;
}

void
ec_offload_close_async_ctx(struct ec_offload_context *ctx)
{
	spdk_poller_unregister(&ctx->poller);
	free_async_ec_ctx(ctx->ec_async_ctx);
	ibv_dealloc_pd(ctx->pd);

	if (ibv_close_device(ctx->context))
		fprintf(stderr, "Couldn't release context\n");

	free(ctx);
}

int
ec_offload_decode_block_sync(struct ec_offload_context *ctx,
			     char *data,
			     char *code)
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
			     char *data,
			     char *code)
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

int
ec_offload_encode_block_async(struct ec_offload_context *ctx,
			      char *data,
			      char *code,
			      void *arg)
{
	struct async_ec_context *ec_ctx = ctx->ec_async_ctx;
	int err = 0;
	struct ec_comp *comp;

	if (ec_ctx->attr.max_inflight_calcs <= ec_ctx->inflights) {
		err_log("No more completions.\n");
		return -1;
	}

	comp = get_ec_comp(ec_ctx);
	memcpy(comp->data.buf, data,
	       ec_ctx->block_size * ec_ctx->attr.k);
	comp->user_dst_code = code;
	comp->user_arg = arg;

	err = ibv_exp_ec_encode_async(ec_ctx->calc, &comp->mem, &comp->comp);
	if (err) {
		err_log("Failed ibv_exp_ec_encode_async (%d)\n", err);
		put_ec_comp(ec_ctx, comp);
		return err;
	}

	if (ec_ctx->attr.polling) {
		ec_ctx->inflights++;
	}
	return 0;
}

static void
async_encode_done(struct ibv_exp_ec_comp *ib_comp)
{
	struct ec_comp *comp = (void *)ib_comp - offsetof(struct ec_comp, comp);
	struct async_ec_context *ec_ctx = comp->ctx;
	struct ec_offload_context *ec_offload_ctx = comp->user_ctx;

	memcpy(comp->user_dst_code, comp->code.buf, ec_ctx->block_size * ec_ctx->attr.m);
	ec_offload_ctx->async_encode_done_cb(ec_offload_ctx, comp->user_arg);

	put_ec_comp(ec_ctx, comp);
	if (ec_ctx->attr.polling)
		ec_ctx->inflights--;
}

static int
async_encode_poll(void *ctx)
{
	struct ec_offload_context *ec_offload_ctx = ctx;
	struct async_ec_context *ec_ctx = ec_offload_ctx->ec_async_ctx;
	if (ec_ctx->attr.polling)
		ibv_exp_ec_poll(ec_ctx->calc, ec_ctx->attr.max_inflight_calcs);
	return 0;
}
