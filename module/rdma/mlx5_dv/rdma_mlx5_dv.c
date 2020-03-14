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

#include "spdk_internal/rdma.h"
#include "spdk_internal/log.h"

struct spdk_rdma_send_wr_list {
	struct ibv_send_wr	*first;
	struct ibv_send_wr	*last;
};

struct spdk_rdma_qp {
	struct ibv_qp *qp;
	struct ibv_qp_ex *qpex;
	struct rdma_cm_id *cm_id;
	/* Used to report bad_wr since Direct Verbs don't provide
	 * a mechanism similar to ibv_post_send */
	struct spdk_rdma_send_wr_list send_wrs;
};

struct spdk_rdma_qp *
spdk_rdma_create_qp(struct rdma_cm_id *cm_id, struct spdk_rdma_qp_init_attr *qp_attr)
{
	assert(cm_id);
	assert(qp_attr);

	struct ibv_qp *qp;
	struct spdk_rdma_qp *spdk_rdma_qp;
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
	qp_attr->cap =  dv_qp_attr.cap;
	/* Assign qp in RESET state to cm_id. Later this qp will be transitioned
	 * through INIT/RTR/RTS state during rdma_connect or rdma_accept calls */
	cm_id->qp = qp;

	spdk_rdma_qp->qp = qp;
	spdk_rdma_qp->cm_id = cm_id;
	spdk_rdma_qp->qpex = ibv_qp_to_qp_ex(spdk_rdma_qp->qp);

	return spdk_rdma_qp;
}

void
spdk_rdma_destroy_qp(struct spdk_rdma_qp *spdk_rdma_qp)
{
	if (!spdk_rdma_qp) {
		return;
	}

	if (spdk_rdma_qp->send_wrs.first != NULL) {
		spdk_rdma_flush_queued_wrs(spdk_rdma_qp, NULL);
	}

	if (spdk_rdma_qp->qp) {
		ibv_destroy_qp(spdk_rdma_qp->qp);
	}

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

	rc =  ibv_wr_complete(spdk_rdma_qp->qpex);

	if (spdk_unlikely(rc)) {
		/* If ibv_wr_complete reports an error that means that no WRs have been posted to NIC */
		*bad_wr = spdk_rdma_qp->send_wrs.first;
	}

	spdk_rdma_qp->send_wrs.first = NULL;

	return rc;
}
