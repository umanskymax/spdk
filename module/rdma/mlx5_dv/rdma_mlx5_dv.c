/*-
 *   BSD LICENSE
 *
 *   Copyright (c) Intel Corporation. All rights reserved.
 *   Copyright (c) 2020 Mellanox Technologies LTD. All rights reserved.
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

#include <rdma/rdma_cma.h>
#include <infiniband/mlx5dv.h>

#include "spdk/stdinc.h"
#include "spdk/string.h"
#include "spdk/likely.h"
#include "spdk/dif.h"

#include "spdk_internal/rdma.h"
#include "spdk_internal/log.h"

struct spdk_rdma_send_wr_list {
	struct ibv_send_wr *first;
	struct ibv_send_wr *last;
};

struct reg_sig_mr {
	struct ibv_exp_sig_attrs sig_attrs;
	struct ibv_exp_send_wr wr;
	struct ibv_exp_send_wr inv_wr;
};

struct spdk_rdma_qp {
	struct ibv_qp *qp;
	struct ibv_qp_ex *qpex;
	struct rdma_cm_id *cm_id;
	/* Used to report bad_wr since Direct Verbs don't provide
	 * a mechanism similar to ibv_post_send */
	struct spdk_rdma_send_wr_list send_wrs;

	uint32_t num_entries;

	/* to query offload capabilities */
	struct ibv_context *device;
	/* Array of WRs to register sig_mr */
	struct reg_sig_mr *reg_sig_mr_wrs;
	/* Array of pointers to sig_mrs */
	struct ibv_mr **sig_mrs;
	/* Array of free indexes, 0 is invalid idx */
	bool *free_idx;
	uint32_t last_free_idx;
};

struct spdk_rdma_qp *
spdk_rdma_create_qp(struct rdma_cm_id *cm_id, struct spdk_rdma_qp_init_attr *qp_attr)
{
	assert(cm_id);
	assert(qp_attr);

	struct ibv_qp *qp;
	struct spdk_rdma_qp *spdk_rdma_qp;
	uint32_t i;
	struct ibv_exp_create_mr_in sig_mr_in = {
		.pd = qp_attr->pd,
		.attr.max_klm_list_size = 1,
		.attr.create_flags = IBV_EXP_MR_SIGNATURE_EN,
		.attr.exp_access_flags = IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE |
		IBV_ACCESS_REMOTE_READ
	};
	struct ibv_qp_init_attr_ex dv_qp_attr = {
		.qp_context = qp_attr->qp_context,
		.send_cq = qp_attr->send_cq,
		.recv_cq = qp_attr->recv_cq,
		.srq = qp_attr->srq,
		.cap = qp_attr->cap,
		.qp_type = IBV_QPT_RC,
		.comp_mask = IBV_QP_INIT_ATTR_PD | IBV_QP_INIT_ATTR_SEND_OPS_FLAGS,
		.pd = qp_attr->pd ? qp_attr->pd : cm_id->pd
	};

	assert(dv_qp_attr.pd);

	spdk_rdma_qp = calloc(1, sizeof(*spdk_rdma_qp));
	if (!spdk_rdma_qp) {
		SPDK_ERRLOG("qp memory allocation failed\n");
		return NULL;
	}

	qp = mlx5dv_create_qp(cm_id->verbs, &dv_qp_attr, NULL);

	if (!qp) {
		SPDK_ERRLOG("Failed to create qpair, errno %d %s\n", errno, spdk_strerror(errno));
		free(spdk_rdma_qp);
		return NULL;
	}
	qp_attr->cap = dv_qp_attr.cap;
	/* Assign qp in RESET state to cm_id. Later this qp will be transitioned
	 * through INIT/RTR/RTS state during rdma_connect or rdma_accept calls */
	cm_id->qp = qp;

	spdk_rdma_qp->qp = qp;
	spdk_rdma_qp->cm_id = cm_id;
	spdk_rdma_qp->qpex = ibv_qp_to_qp_ex(spdk_rdma_qp->qp);
	spdk_rdma_qp->num_entries = qp_attr->num_entries;
	spdk_rdma_qp->device = cm_id->verbs;

	spdk_rdma_qp->free_idx = calloc(spdk_rdma_qp->num_entries + 1, sizeof((spdk_rdma_qp->free_idx)));
	if (!spdk_rdma_qp->free_idx) {
		spdk_rdma_destroy_qp(spdk_rdma_qp);
		return NULL;
	}

	spdk_rdma_qp->reg_sig_mr_wrs = calloc(spdk_rdma_qp->num_entries, sizeof(struct ibv_send_wr));
	if (!spdk_rdma_qp->reg_sig_mr_wrs) {
		spdk_rdma_destroy_qp(spdk_rdma_qp);
		return NULL;
	}

	spdk_rdma_qp->sig_mrs = calloc(spdk_rdma_qp->num_entries, sizeof(struct ibv_mr *));
	if (!spdk_rdma_qp->sig_mrs) {
		spdk_rdma_destroy_qp(spdk_rdma_qp);
		return NULL;
	}

	for (i = 0; i < spdk_rdma_qp->num_entries; i++) {
		spdk_rdma_qp->sig_mrs[i] = ibv_exp_create_mr(&sig_mr_in);
		if (!spdk_rdma_qp->sig_mrs[i]) {
			spdk_rdma_destroy_qp(spdk_rdma_qp);
			return NULL;
		}
	}

	for (i = 0; i < spdk_rdma_qp->num_entries; i++) {
		/* Fill default values of WR which is used to register sig_mr*/
		struct reg_sig_mr *reg_mr = &spdk_rdma_qp->reg_sig_mr_wrs[i];
		reg_mr->sig_attrs.check_mask = 0xff;
		// TODO: initiator uses wire domain, need to pass additional options in spdk_rdma_qp_init_attr
		reg_mr->sig_attrs.wire.sig_type = IBV_EXP_SIG_TYPE_NONE;
		reg_mr->sig_attrs.mem.sig_type = IBV_EXP_SIG_TYPE_T10_DIF;
		reg_mr->sig_attrs.mem.sig.dif.bg_type = IBV_EXP_T10DIF_CRC;
		reg_mr->sig_attrs.mem.sig.dif.bg = 0;
		reg_mr->sig_attrs.mem.sig.dif.app_tag = 0;
		reg_mr->sig_attrs.mem.sig.dif.ref_remap = 1;
		reg_mr->sig_attrs.mem.sig.dif.app_escape = 1;
		reg_mr->sig_attrs.mem.sig.dif.ref_escape = 1;

		reg_mr->wr.opcode = IBV_EXP_WR_REG_SIG_MR;
		reg_mr->wr.ext_op.sig_handover.sig_attrs = &reg_mr->sig_attrs;
		reg_mr->wr.ext_op.sig_handover.sig_mr = spdk_rdma_qp->sig_mrs[i];
		reg_mr->wr.ext_op.sig_handover.access_flags =
			IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE | IBV_ACCESS_REMOTE_READ;

		reg_mr->inv_wr.exp_opcode = IBV_EXP_WR_LOCAL_INV;
	}

	return spdk_rdma_qp;
}

void
spdk_rdma_destroy_qp(struct spdk_rdma_qp *spdk_rdma_qp)
{
	uint32_t i;

	if (!spdk_rdma_qp) {
		return;
	}

	if (spdk_rdma_qp->send_wrs.first != NULL) {
		spdk_rdma_flush_queued_wrs(spdk_rdma_qp, NULL);
	}

	for (i = 0; i < spdk_rdma_qp->num_entries; i++) {
		if (spdk_rdma_qp->sig_mrs[i]) {
			ibv_dereg_mr(spdk_rdma_qp->sig_mrs[i]);
		}
	}

	if (spdk_rdma_qp->qp) {
		ibv_destroy_qp(spdk_rdma_qp->qp);
	}

	free(spdk_rdma_qp->free_idx);
	free(spdk_rdma_qp->reg_sig_mr_wrs);
	free(spdk_rdma_qp->sig_mrs);
	free(spdk_rdma_qp);
}

bool spdk_rdma_queue_send_wrs(struct spdk_rdma_qp *spdk_rdma_qp, struct ibv_send_wr *first)
{
	struct ibv_send_wr *tmp;

	assert(first);

	bool is_first = spdk_rdma_qp->send_wrs.first == NULL;

	if (is_first) {
		ibv_wr_start(spdk_rdma_qp->qpex);
		spdk_rdma_qp->send_wrs.first = first;
	} else {
		spdk_rdma_qp->send_wrs.last->next = first;
	}

	for (tmp = first; tmp != NULL; tmp = tmp->next) {
		spdk_rdma_qp->qpex->wr_id = tmp->wr_id;
		spdk_rdma_qp->qpex->wr_flags = tmp->send_flags;

		switch (tmp->opcode) {
		case IBV_WR_SEND:
			ibv_wr_send(spdk_rdma_qp->qpex);
			ibv_wr_set_sge(spdk_rdma_qp->qpex, tmp->sg_list->lkey, tmp->sg_list->addr,
				       tmp->sg_list->length);
			break;
		case IBV_WR_SEND_WITH_INV:
			ibv_wr_send_inv(spdk_rdma_qp->qpex, tmp->invalidate_rkey);
			ibv_wr_set_sge(spdk_rdma_qp->qpex, tmp->sg_list->lkey, tmp->sg_list->addr,
				       tmp->sg_list->length);
		case IBV_WR_RDMA_READ:
			ibv_wr_rdma_read(spdk_rdma_qp->qpex, tmp->wr.rdma.rkey, tmp->wr.rdma.remote_addr);
			ibv_wr_set_sge_list(spdk_rdma_qp->qpex, tmp->num_sge, tmp->sg_list);
			break;
		case IBV_WR_RDMA_WRITE:
			ibv_wr_rdma_write(spdk_rdma_qp->qpex, tmp->wr.rdma.rkey, tmp->wr.rdma.remote_addr);
			ibv_wr_set_sge_list(spdk_rdma_qp->qpex, tmp->num_sge, tmp->sg_list);
			break;
		case IBV_EXP_WR_LOCAL_INV:
			/* TODO: use new API to invalidate sig_mr*/
			break;

		case IBV_EXP_WR_REG_SIG_MR:
			/* TODO: use new API to register sig_mr*/
			break;

		default:
			SPDK_ERRLOG("Unexpected opcode %d\n", tmp->opcode);
			assert(0);
		}

		spdk_rdma_qp->send_wrs.last = tmp;
	}

	return is_first;
}

int spdk_rdma_flush_queued_wrs(struct spdk_rdma_qp *spdk_rdma_qp, struct ibv_send_wr **bad_wr)
{
	int rc;

	assert(bad_wr);

	if (spdk_unlikely(spdk_rdma_qp->send_wrs.first == NULL)) {
		return 0;
	}

	rc = ibv_wr_complete(spdk_rdma_qp->qpex);

	if (spdk_unlikely(rc)) {
		/* If ibv_wr_complete reports an error that means that no WRs have been posted to NIC */
		*bad_wr = spdk_rdma_qp->send_wrs.first;
	}

	spdk_rdma_qp->send_wrs.first = NULL;

	return rc;
}

bool
spdk_rdma_qpair_sig_offload_supported(struct spdk_rdma_qp *spdk_rdma_qp)
{
	//TODO: check device capabilities, store the result to qpair at init state
	//and return the new property here
	return true;
}

static bool
spdk_rdma_mlx5_get_free_idx(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t *_free_idx)
{
	uint32_t free_idx;

	for (free_idx = spdk_rdma_qp->last_free_idx; free_idx < spdk_rdma_qp->num_entries + 1; free_idx++) {
		if (spdk_rdma_qp->free_idx[free_idx]) {
			spdk_rdma_qp->free_idx[free_idx] = false;
			spdk_rdma_qp->last_free_idx = free_idx;
			*_free_idx = free_idx;
			return true;
		}
	}

	//didn't find in a range [spdk_rdma_qp->last_free_idx, spdk_rdma_qp->num_entries + 1)
	//try range [1, spdk_rdma_qp->last_free_idx)
	for (free_idx = 1; free_idx < spdk_rdma_qp->last_free_idx; free_idx++) {
		if (spdk_rdma_qp->free_idx[free_idx]) {
			spdk_rdma_qp->free_idx[free_idx] = false;
			spdk_rdma_qp->last_free_idx = free_idx;
			*_free_idx = free_idx;
			return true;
		}
	}

	return false;

}

struct ibv_send_wr *
spdk_rdma_prepare_signature(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t *idx,
			    struct ibv_send_wr *wr_in, const struct spdk_dif_ctx *dif_ctx)
{
	struct ibv_exp_sig_attrs sig_attrs = {};
	struct ibv_exp_send_wr wr = {};
	struct ibv_exp_send_wr *bad_wr;
	int rc;
	struct reg_sig_mr *sig_mr_wr;
	uint32_t free_idx;

	if (!spdk_rdma_mlx5_get_free_idx(spdk_rdma_qp, &free_idx)) {
		SPDK_ERRLOG("Can't find free idx\n");
		assert(0);
	}

	assert(free_idx < spdk_rdma_qp->num_entries);

	sig_mr_wr = &spdk_rdma_qp->reg_sig_mr_wrs[free_idx];

	sig_mr_wr->sig_attrs.mem.sig.dif.pi_interval = dif_ctx->guard_interval;
	sig_mr_wr->sig_attrs.mem.sig.dif.ref_tag = dif_ctx->init_ref_tag;
	sig_mr_wr->sig_attrs.mem.sig.dif.apptag_check_mask = dif_ctx->apptag_mask;

	sig_mr_wr->wr.sg_list = wr_in->sg_list;
	sig_mr_wr->wr.num_sge = wr_in->num_sge;

	*idx = free_idx;

	return &sig_mr->wr;
}

struct ibv_send_wr *
spdk_rdma_release_signature(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t idx)
{
	struct reg_sig_mr *sig_mr_wr;

	assert(idx < spdk_rdma_qp->num_entries + 1);

	if (idx == 0 || spdk_rdma_qp->free_idx[idx] == true) {
		return NULL;
	}

	sig_mr_wr = &spdk_rdma_qp->reg_sig_mr_wrs[idx];

	sig_mr_wr->inv_wr.ex.invalidate_rkey = spdk_rdma_qp->sig_mrs[idx]->rkey;
	spdk_rdma_qp->free_idx[idx] = true;
	spdk_rdma_qp->last_free_idx = idx;

	return &sig_mr_wr->inv_wr;
}

int spdk_rdma_validate_signature(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t idx)
{
	struct ibv_exp_mr_status status;
	int rc;
	struct ibv_mr *sig_mr;

	assert(idx < spdk_rdma_qp->num_entries);

	sig_mr = spdk_rdma_qp->sig_mrs[idx];
	assert(sig_mr != NULL);

	rc = ibv_exp_check_mr_status(sig_mr, IBV_EXP_MR_CHECK_SIG_STATUS, &status);
	if (rc) {
		SPDK_ERRLOG("Failed to check signature MR status, errno %d\n", rc);
		return -1;
	}

	if (status.fail_status) {
		SPDK_ERRLOG("Signature error: type %d, expected %u, actual %u, offset %lu, key %u\n",
			    status.sig_err.err_type,
			    status.sig_err.expected,
			    status.sig_err.actual,
			    status.sig_err.sig_err_offset,
			    status.sig_err.key);
		return 1;
	}

	return 0;
}
