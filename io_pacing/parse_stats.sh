#!/usr/bin/env bash

OUT_PATH=${OUT_PATH-$PWD/out}

function m()
{
    M_SCALE=${M_SCALE-3}
    bc 2>/dev/null <<< "scale=$M_SCALE; $@"
}

function sum() {
    local SUM=0
    for n in $@; do
	((SUM+=n))
    done
    echo $SUM
}

function jq_sum()
{
    local QUERY="$1"; shift
    local LOG="$1"; shift

    sum $(jq "$QUERY" "$LOG")
}

function jq_diff()
{
    local QUERY="$1"; shift
    local LOG="$1"; shift

    local N1=$(jq "$QUERY" "$LOG" | head -1)
    local N2=$(jq "$QUERY" "$LOG" | tail -1)
    echo $((N2-N1))
}

# bdev stats
TICK_RATE=$(jq .tick_rate $OUT_PATH/bdev_stats_final.log)
NUM_RD_OPS=$(jq_sum .bdevs[].num_read_ops $OUT_PATH/bdev_stats_final.log)
RD_TICKS=$(jq_sum .bdevs[].read_latency_ticks $OUT_PATH/bdev_stats_final.log)
RD_LAT_US=$(bc <<< "scale=6; 10^6*$RD_TICKS/$NUM_RD_OPS/$TICK_RATE")
echo "Bdev avg read lat, us: $RD_LAT_US"

# Per poll group NVMf stats
PG_COUNT=$(jq .poll_groups[].name $OUT_PATH/nvmf_stats_final.log | wc -l)
DEV_COUNT=$(jq .poll_groups[0].transports[].devices[].name $OUT_PATH/nvmf_stats_final.log | wc -l)
for pg in $(seq 0 $((PG_COUNT-1))); do
    PG_NAME=$(jq .poll_groups[$pg].name $OUT_PATH/nvmf_stats_final.log)
    echo "Poll group: $PG_NAME"
    CALLS=$(jq_diff .poll_groups[$pg].transports[].io_pacer.calls $OUT_PATH/nvmf_stats.log)
    POLLS=$(jq_diff .poll_groups[$pg].transports[].io_pacer.polls $OUT_PATH/nvmf_stats.log)
    IOS=$(jq_diff .poll_groups[$pg].transports[].io_pacer.ios $OUT_PATH/nvmf_stats.log)
    TICKS=$(jq_diff .poll_groups[$pg].transports[].io_pacer.total_ticks $OUT_PATH/nvmf_stats.log)
    echo "  Pacer calls, polls, ios: $CALLS, $POLLS, $IOS"
    echo "  Pacer poll, io period, us: $(m 10^6*$TICKS/$POLLS/$TICK_RATE) $(m 10^6*$TICKS/$IOS/$TICK_RATE)"
    for dev in $(seq 0 $((DEV_COUNT-1))); do
	DEV_NAME=$(jq .poll_groups[$pg].transports[].devices[$dev].name $OUT_PATH/nvmf_stats_final.log)
	echo "  Device: $DEV_NAME"
	POLLS=$(jq_diff .poll_groups[$pg].transports[].devices[$dev].polls $OUT_PATH/nvmf_stats.log)
	COMPS=$(jq_diff .poll_groups[$pg].transports[].devices[$dev].completions $OUT_PATH/nvmf_stats.log)
	REQS=$(jq_diff .poll_groups[$pg].transports[].devices[$dev].requests $OUT_PATH/nvmf_stats.log)
	REQ_LAT=$(jq_diff .poll_groups[$pg].transports[].devices[$dev].request_latency $OUT_PATH/nvmf_stats.log)

	echo "    Polls, comps, reqs: $POLLS, $COMPS, $REQS"
	echo "    Comps/poll: $(m $COMPS/$POLLS)"
	echo "    Req lat, us: $(m 10^6*$REQ_LAT/$REQS/$TICK_RATE)"

	REQS=$(jq .poll_groups[$pg].transports[].devices[$dev].requests $OUT_PATH/nvmf_stats_final.log)
	REQ_LAT=$(jq .poll_groups[$pg].transports[].devices[$dev].request_latency $OUT_PATH/nvmf_stats_final.log)
	echo "    Req lat (total), us: $(m 10^6*$REQ_LAT/$REQS/$TICK_RATE)"
	REQ_STATES1=$(jq -c .poll_groups[$pg].transports[].devices[$dev].req_state_count $OUT_PATH/nvmf_stats.log | head -1)
	REQ_STATES2=$(jq -c .poll_groups[$pg].transports[].devices[$dev].req_state_count $OUT_PATH/nvmf_stats.log | head -2 | tail -1)
	REQ_STATES3=$(jq -c .poll_groups[$pg].transports[].devices[$dev].req_state_count $OUT_PATH/nvmf_stats.log | tail -1)
	echo "    Req states 1: $REQ_STATES1"
	echo "    Req states 2: $REQ_STATES2"
	echo "    Req states 3: $REQ_STATES3"

	REQS1=$(jq .poll_groups[$pg].transports[].devices[$dev].requests $OUT_PATH/nvmf_stats.log | head -1)
	REQ_LAT1=$(jq .poll_groups[$pg].transports[].devices[$dev].request_latency $OUT_PATH/nvmf_stats.log | head -1)
	REQS2=$(jq .poll_groups[$pg].transports[].devices[$dev].requests $OUT_PATH/nvmf_stats.log | head -2 | tail -1)
	REQ_LAT2=$(jq .poll_groups[$pg].transports[].devices[$dev].request_latency $OUT_PATH/nvmf_stats.log | head -2 | tail -1)
	REQS3=$(jq .poll_groups[$pg].transports[].devices[$dev].requests $OUT_PATH/nvmf_stats.log | tail -1)
	REQ_LAT3=$(jq .poll_groups[$pg].transports[].devices[$dev].request_latency $OUT_PATH/nvmf_stats.log | tail -1)
	echo "    Req lat 1, us: $(m 10^6*$REQ_LAT1/$REQS1/$TICK_RATE)"
	echo "    Req lat 2, us: $(m 10^6*$REQ_LAT2/$REQS2/$TICK_RATE)"
	echo "    Req lat 3, us: $(m 10^6*$REQ_LAT3/$REQS3/$TICK_RATE)"

    done
done
