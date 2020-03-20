/*-
 *   BSD LICENSE
 *
 *   Copyright (c) Intel Corporation. All rights reserved.
 *   Copyright (c) Mellanox Technologies LTD. All rights reserved.
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

#ifndef SPDK_RDMA_H
#define SPDK_RDMA_H

#include <infiniband/verbs.h>
#include <rdma/rdma_cma.h>
#include <rdma/rdma_verbs.h>

struct spdk_rdma_qp_init_attr {
	void		       *qp_context;
	struct ibv_cq	       *send_cq;
	struct ibv_cq	       *recv_cq;
	struct ibv_srq	       *srq;
	struct ibv_qp_cap	cap;
	struct ibv_pd	       *pd;
	uint32_t num_entries;
};

struct spdk_rdma_qp;

/**
 * Create RDMA provider specific qpair
 * \param cm_id Pointer to RDMACM cm_id
 * \param qp_attr Pointer to qpair init attributes
 * \return Pointer to a newly created qpair on success or NULL on failure
 */
struct spdk_rdma_qp *spdk_rdma_create_qp(struct rdma_cm_id *cm_id,
		struct spdk_rdma_qp_init_attr *qp_attr);

/**
 * Destory RDMA provider specific qpair
 * \param spdk_rdma_qp Pointer to qpair to be destroyed
 */
void spdk_rdma_destroy_qp(struct spdk_rdma_qp *spdk_rdma_qp);

/**
 * Append the given send wr structure to the qpair's outstanding sends list.
 * This function accepts either a single Work Request or the first WR in a linked list.
 *
 * \param spdk_rdma_qp Pointer to SPDK RDMA qpair
 * \param first Pointer to the first Work Request
 * \return true if there were no outstanding WRs before, false otherwise
 */
bool spdk_rdma_queue_send_wrs(struct spdk_rdma_qp *spdk_rdma_qp, struct ibv_send_wr *first);

/**
 * Submit all queued Work Request
 * \param spdk_rdma_qp Pointer to SPDK RDMA qpair
 * \param bad_wr Stores a pointer to the first failed WR if this function return nonzero value
 * \return 0 on succes, errno on failure
 */
int spdk_rdma_flush_queued_wrs(struct spdk_rdma_qp *spdk_rdma_qp, struct ibv_send_wr **bad_wr);

/**
 * Check whether the device used by qpair supports signature offload
 * @return
 */
bool spdk_rdma_qpair_sig_offload_supported(struct spdk_rdma_qp *spdk_rdma_qp);

/**
 * Prepares a Work Request to be send in a regular way to register signature offload for
 * a particular wr_in
 * @param spdk_rdma_qp
 * @param idx - identifier of the operation returned to the called. Will be used to release the registered sig offload
 * @param wr_in - Work Request which describes data to be used for signature offload
 * @param dif_ctx - T10DIF related info
 * @return Pointer to WR to be chanined with regular data WRs
 */
struct ibv_send_wr *spdk_rdma_prepare_signature(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t *idx,
		struct ibv_send_wr *wr_in, const struct spdk_dif_ctx *dif_ctx);

/**
 * Prepares a Work Request to be send in a regular way to release previously registered signature offload
 * @param spdk_rdma_qp
 * @param idx
 * @param rkey
 * @return
 */
struct ibv_send_wr *spdk_rdma_release_signature(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t idx);

/**
 * Check result of signature offload operation
 * @param spdk_rdma_qp
 * @param idx
 * @return
 */
int spdk_rdma_validate_signature(struct spdk_rdma_qp *spdk_rdma_qp, uint32_t idx);


#endif /* SPDK_RDMA_H */
