/*-
 *   BSD LICENSE
 *
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

#include "io_pacer.h"
#include "spdk/stdinc.h"
#include "spdk/thread.h"
#include "spdk/likely.h"
#include "spdk_internal/assert.h"
#include "spdk_internal/log.h"

#define IO_PACER_DEFAULT_MAX_QUEUES 32

struct io_pacer_queue_entry {
	STAILQ_ENTRY(io_pacer_queue_entry) link;
};

struct io_pacer_queue {
	uint64_t key;
	STAILQ_HEAD(, io_pacer_queue_entry) queue;
};

struct spdk_io_pacer {
	uint64_t period_ticks;
	uint32_t max_queues;
	spdk_io_pacer_pop_cb pop_cb;
	uint32_t num_queues;
	uint32_t next_queue;
	uint64_t num_ios;
	uint64_t first_tick;
	uint64_t last_tick;
	struct spdk_nvmf_io_pacer_stat stat;
	struct io_pacer_queue *queues;
	struct spdk_poller *poller;
};


static struct io_pacer_queue *
io_pacer_get_queue(struct spdk_io_pacer *pacer, uint64_t key)
{
	uint32_t i;
	for (i = 0; i < pacer->num_queues; ++i) {
		if (pacer->queues[i].key == key) {
			return &pacer->queues[i];
		}
	}

	/* @todo: Creating queue on demand due to limitations in rdma transport.
	 * To be removed.
	 */
	if (0 != spdk_io_pacer_create_queue(pacer, key)) {
		return NULL;
	}

	return io_pacer_get_queue(pacer, key);
}

static int
io_pacer_poll(void *arg)
{
	struct spdk_io_pacer *pacer = arg;
	struct io_pacer_queue_entry *entry;
	uint32_t next_queue = pacer->next_queue;

	const uint64_t cur_tick = spdk_get_ticks();
	const uint64_t ticks_diff = cur_tick - pacer->last_tick;

	pacer->stat.calls++;
	if (ticks_diff < pacer->period_ticks) {
		return 0;
	}
	pacer->stat.total_ticks = cur_tick - pacer->first_tick;
	pacer->last_tick = cur_tick - ticks_diff % pacer->period_ticks;
	pacer->stat.polls++;

	if (pacer->num_ios == 0) {
		pacer->stat.no_ios++;
		return 0;
	}

	do {
		if (next_queue >= pacer->num_queues) {
			next_queue = 0;
		}

		entry = STAILQ_FIRST(&pacer->queues[next_queue].queue);
		next_queue++;
	} while (entry == NULL);

	STAILQ_REMOVE_HEAD(&pacer->queues[next_queue - 1].queue, link);
	pacer->num_ios--;
	pacer->next_queue = next_queue;
	pacer->pop_cb(entry);
	pacer->stat.ios++;
	return 1;
}

struct spdk_io_pacer *
spdk_io_pacer_create(uint32_t period_us, spdk_io_pacer_pop_cb pop_cb)
{
	struct spdk_io_pacer *pacer;

	assert(pop_cb != NULL);

	pacer = (struct spdk_io_pacer *)calloc(1, sizeof(struct spdk_io_pacer));
	if (!pacer) {
		SPDK_ERRLOG("Failed to allocate IO pacer\n");
		return NULL;
	}

	/* @todo: may overflow? */
	pacer->period_ticks = period_us * spdk_get_ticks_hz() / SPDK_SEC_TO_USEC;
	pacer->pop_cb = pop_cb;
	pacer->first_tick = spdk_get_ticks();
	pacer->last_tick = spdk_get_ticks();
	pacer->poller = SPDK_POLLER_REGISTER(io_pacer_poll, (void *)pacer, 0);
	if (!pacer->poller) {
		SPDK_ERRLOG("Failed to create poller for IO pacer\n");
		spdk_io_pacer_destroy(pacer);
		return NULL;
	}

	SPDK_NOTICELOG("Created IO pacer %p: period_us %u, period_ticks %lu, max_queues %u\n",
		       pacer, period_us, pacer->period_ticks, pacer->max_queues);

	return pacer;
}

void
spdk_io_pacer_destroy(struct spdk_io_pacer *pacer)
{
	uint32_t i;

	assert(pacer != NULL);

	/* Check if we have something in the queues */
	for (i = 0; i < pacer->num_queues; ++i) {
		if (!STAILQ_EMPTY(&pacer->queues[i].queue)) {
			SPDK_WARNLOG("IO pacer queue is not empty on pacer destroy: pacer %p, key %016lx\n",
				     pacer, pacer->queues[i].key);
		}
	}

	spdk_poller_unregister(&pacer->poller);
	free(pacer->queues);
	free(pacer);
	SPDK_NOTICELOG("Destroyed IO pacer %p\n", pacer);
}

int
spdk_io_pacer_create_queue(struct spdk_io_pacer *pacer, uint64_t key)
{
	assert(pacer != NULL);

	if (pacer->num_queues >= pacer->max_queues) {
		const uint32_t new_max_queues = pacer->max_queues ?
			2 * pacer->max_queues : IO_PACER_DEFAULT_MAX_QUEUES;
		struct io_pacer_queue *new_queues =
			(struct io_pacer_queue *)realloc(pacer->queues,
							 new_max_queues * sizeof(*pacer->queues));
		if (!new_queues) {
			SPDK_NOTICELOG("Failed to allocate more queues for IO pacer %p: max_queues %u\n",
				       pacer, new_max_queues);
			return -1;
		}

		pacer->queues = new_queues;
		pacer->max_queues = new_max_queues;
		SPDK_NOTICELOG("Allocated more queues for IO pacer %p: max_queues %u\n",
			       pacer, pacer->max_queues);
	}

	pacer->queues[pacer->num_queues].key = key;
	STAILQ_INIT(&pacer->queues[pacer->num_queues].queue);
	pacer->num_queues++;
	SPDK_NOTICELOG("Created IO pacer queue: pacer %p, key %016lx\n",
		       pacer, key);

	return 0;
}

int
spdk_io_pacer_destroy_queue(struct spdk_io_pacer *pacer, uint64_t key)
{
	uint32_t i;

	assert(pacer != NULL);

	for (i = 0; i < pacer->num_queues; ++i) {
		if (pacer->queues[i].key == key) {
			if (!STAILQ_EMPTY(&pacer->queues[i].queue)) {
				SPDK_WARNLOG("Destroying non empty IO pacer queue: key %016lx\n", key);
			}

			memmove(&pacer->queues[i], &pacer->queues[i + 1],
				(pacer->num_queues - i - 1) * sizeof(struct io_pacer_queue));
			pacer->num_queues--;
			SPDK_NOTICELOG("Destroyed IO pacer queue: pacer %p, key %016lx\n",
				       pacer, key);
			return 0;
		}
	}

	SPDK_ERRLOG("IO pacer queue not found: key %016lx\n", key);
	return -1;
}

int
spdk_io_pacer_push(struct spdk_io_pacer *pacer, uint64_t key, void *io)
{
	struct io_pacer_queue *queue;
	struct io_pacer_queue_entry *entry = io;

	assert(pacer != NULL);
	assert(io != NULL);

	queue = io_pacer_get_queue(pacer, key);
	if (spdk_unlikely(queue == NULL)) {
		SPDK_ERRLOG("IO pacer queue not found: key %016lx\n", key);
		return -1;
	}

	STAILQ_INSERT_TAIL(&queue->queue, entry, link);
	pacer->num_ios++;
	return 0;
}

void
spdk_io_pacer_get_stat(const struct spdk_io_pacer *pacer,
		       struct spdk_nvmf_transport_poll_group_stat *stat)
{
	if (pacer && stat) {
		stat->io_pacer.total_ticks = pacer->stat.total_ticks;
		stat->io_pacer.polls = pacer->stat.polls;
		stat->io_pacer.ios = pacer->stat.ios;
		stat->io_pacer.calls = pacer->stat.calls;
		stat->io_pacer.no_ios = pacer->stat.no_ios;
	}
}
