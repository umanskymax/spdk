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

#define MAX_DRIVES_STATS 256
static rte_spinlock_t drives_stats_create_lock = RTE_SPINLOCK_INITIALIZER;
struct spdk_io_pacer_drives_stats drives_stats = {0};

struct io_pacer_queue_entry {
	STAILQ_ENTRY(io_pacer_queue_entry) link;
};

struct io_pacer_queue {
	uint64_t key;
	struct drive_stats *stats;
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

	uint64_t tuner_period_ns;
	uint64_t tuner_step_ns;
	uint64_t min_period_ticks;
	uint64_t max_period_ticks;
	uint64_t tuner_last_ios;
	struct spdk_poller *tuner;
	void *ctx;
	uint32_t disk_credit;
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
	uint32_t ops_in_flight = 0;
	
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
		next_queue %= pacer->num_queues;

		ops_in_flight = rte_atomic32_read(&pacer->queues[next_queue].stats->ops_in_flight);
		if (ops_in_flight > pacer->disk_credit) {
			next_queue++;
			continue;
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

static int
io_pacer_tune(void *arg)
{
	struct spdk_io_pacer *pacer = arg;
	const uint64_t ticks_hz = spdk_get_ticks_hz();
	const uint64_t ios = pacer->stat.ios - pacer->tuner_last_ios;
	const uint64_t io_period_ns = pacer->tuner_period_ns / ((ios != 0) ? ios : 1);

	const uint64_t cur_period_ns = (pacer->period_ticks * SPDK_SEC_TO_NSEC) / ticks_hz;
	/* We always want to set pacer period one step shorter than measured IO period.
	 * But we limit changes to one step at a time in any direction.
	 */
	uint64_t new_period_ns = io_period_ns - pacer->tuner_step_ns;
	if (new_period_ns > cur_period_ns + pacer->tuner_step_ns) {
		new_period_ns = cur_period_ns + pacer->tuner_step_ns;
	} else if (new_period_ns < cur_period_ns - pacer->tuner_step_ns) {
		new_period_ns = cur_period_ns - pacer->tuner_step_ns;
	}

	uint64_t new_period_ticks = (new_period_ns * ticks_hz) / SPDK_SEC_TO_NSEC;
	new_period_ticks = spdk_max(spdk_min(new_period_ticks, pacer->max_period_ticks),
				    pacer->min_period_ticks);

	static __thread uint32_t log_counter = 0;
	/* Try to log once per second */
	if (log_counter % (SPDK_SEC_TO_NSEC / pacer->tuner_period_ns) == 0) {
		SPDK_NOTICELOG("IO pacer tuner: pacer %p, ios %lu, io period %lu ns, new period %lu ns, new period %lu ticks, min %lu, max %lu\n",
			       pacer,
			       pacer->stat.ios - pacer->tuner_last_ios,
			       io_period_ns,
			       new_period_ns,
			       new_period_ticks,
			       pacer->min_period_ticks,
			       pacer->max_period_ticks);
	}
	log_counter++;

	pacer->period_ticks = new_period_ticks;
	pacer->tuner_last_ios = pacer->stat.ios;

	return 1;
}

struct spdk_io_pacer *
spdk_io_pacer_create(uint32_t period_ns, uint32_t tuner_period_us, uint32_t tuner_step_ns,
		     uint32_t disk_credit, spdk_io_pacer_pop_cb pop_cb, void *ctx)
{
	struct spdk_io_pacer *pacer;

	assert(pop_cb != NULL);

	pacer = (struct spdk_io_pacer *)calloc(1, sizeof(struct spdk_io_pacer));
	if (!pacer) {
		SPDK_ERRLOG("Failed to allocate IO pacer\n");
		return NULL;
	}

	/* @todo: may overflow? */
	pacer->min_period_ticks = (period_ns * spdk_get_ticks_hz()) / SPDK_SEC_TO_NSEC;
	pacer->max_period_ticks = 2 * pacer->min_period_ticks;
	pacer->period_ticks = pacer->min_period_ticks;
	pacer->pop_cb = pop_cb;
	pacer->first_tick = spdk_get_ticks();
	pacer->last_tick = spdk_get_ticks();
	pacer->poller = SPDK_POLLER_REGISTER(io_pacer_poll, (void *)pacer, 0);
	if (!pacer->poller) {
		SPDK_ERRLOG("Failed to create poller for IO pacer\n");
		spdk_io_pacer_destroy(pacer);
		return NULL;
	}

	pacer->tuner_period_ns = 1000ULL * tuner_period_us;
	pacer->tuner_step_ns = tuner_step_ns;
	pacer->disk_credit = disk_credit;
	pacer->tuner = SPDK_POLLER_REGISTER(io_pacer_tune, (void *)pacer, tuner_period_us);
	if (!pacer->tuner) {
		SPDK_ERRLOG("Failed to create tuner poller for IO pacer\n");
		spdk_io_pacer_destroy(pacer);
		return NULL;
	}

	pacer->ctx = ctx;
	SPDK_NOTICELOG("Created IO pacer %p: period_ns %u, period_ticks %lu, max_queues %u, tuner_period_ns %lu, tuner_step_ns %lu\n",
		       pacer,
		       period_ns,
		       pacer->period_ticks,
		       pacer->max_queues,
		       pacer->tuner_period_ns,
		       pacer->tuner_step_ns);

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
	spdk_poller_unregister(&pacer->tuner);
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
	spdk_io_pacer_drive_stats_setup(&drives_stats, MAX_DRIVES_STATS);
	pacer->queues[pacer->num_queues].stats = spdk_io_pacer_drive_stats_get(&drives_stats, key);
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
		stat->io_pacer.period_ticks = pacer->period_ticks;
	}
}

void spdk_io_pacer_drive_stats_setup(struct spdk_io_pacer_drives_stats *stats, int32_t entries)
{
	struct rte_hash_parameters hash_params = {
		.name = "DRIVE_STATS",		
		.entries = entries,
		.key_len = sizeof(uint64_t),
		.socket_id = rte_socket_id(),
		.hash_func = rte_jhash,
		.hash_func_init_val = 0,		
	};
	struct rte_hash *h = NULL;
	
	if (stats->h != NULL)
		return;
	
	rte_spinlock_lock(&drives_stats_create_lock);

	if (stats->h != NULL)
		return;

	h = rte_hash_create(&hash_params);
	if (h == NULL)
		SPDK_ERRLOG("IO pacer can't create drive statistics dict");
	stats->h = h;
	rte_spinlock_init(&stats->lock);
	rte_spinlock_unlock(&drives_stats_create_lock);
}



