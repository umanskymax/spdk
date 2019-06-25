/*-
 *   BSD LICENSE
 *
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

#include "spdk/ibv.h"
#include "spdk/log.h"

uint32_t
spdk_ibv_get_device_max_inline_size(struct ibv_context *dev_context, struct ibv_pd* pd)
{
	uint32_t current_value = 2;
	uint32_t max_value = INT_MAX / 2;
	uint32_t result = 0;
	const uint32_t multiplier = 2;
	struct ibv_qp *qp;
	struct ibv_cq *cq = ibv_create_cq(dev_context, 1, NULL, NULL, 0);
	if (!cq) {
		SPDK_ERRLOG("Unable to retrieve max inline size - cq creation failed, error %d\n", errno);
		return 0;
	}
	struct ibv_qp_init_attr qp_init_attr = {
		.send_cq = cq,
		.recv_cq = cq,
		.cap.max_send_wr = 1,
		.cap.max_send_sge = 1,
		.qp_type = IBV_QPT_RC,
		.sq_sig_all = 1
	};

	do {
		qp_init_attr.cap.max_inline_data = current_value;
		qp = ibv_create_qp(pd, &qp_init_attr);
		if (qp) {
			result = current_value;
			ibv_destroy_qp(qp);
		} else {
			break;
		}
		current_value *= multiplier;
	} while (qp && current_value < max_value);

	if (result) {
		uint32_t next_value;
		max_value = current_value;
		current_value = result;

		do {
			next_value = current_value  + (max_value - current_value) / 2;
			qp_init_attr.cap.max_inline_data = next_value;
			qp = ibv_create_qp(pd, &qp_init_attr);
			if (qp) {
				current_value = next_value;
				ibv_destroy_qp(qp);
			} else {
				max_value = next_value;
			}
		} while (max_value - current_value > 2);

		result = current_value;
	}
	
	ibv_destroy_cq(cq);

	return result;
}
