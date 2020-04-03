#!/usr/bin/env bash

# Input test parameters
TEST_TIME=${TEST_TIME-60}
RW=${RW-randread}
QD=${QD-32}
IO_SIZE=${IO_SIZE-128k}
HOSTS="r-dcs79 spdk03.swx.labs.mlnx"
TARGET="ubuntu@spdk-tgt-bw-03"
FIO_JOB=${FIO_JOB-"fio-16ns"}

# Paths configuration
FIO_PATH="$PWD/../../fio"
SPDK_PATH="$PWD/.."
FIO_JOBS_PATH="$PWD/jobs"
OUT_PATH="$PWD/out"
mkdir -p $OUT_PATH

# Other configurations
ENABLE_DEVICE_COUNTERS=1

# Internal variables
FIO_PARAMS="--time_based=1 --runtime=$TEST_TIME --readwrite=$RW --bs=$IO_SIZE --iodepth=$QD --output-format=json"

function m()
{
    bc <<< "scale=1; $@"
}

function get_device_counters()
{
    ssh $TARGET sudo python /opt/neohost/sdk/get_device_performance_counters.py --dev-uid=0000:17:00.0 --output-format=JSON > $OUT_PATH/device-counters.json
}

function parse_fio()
{
    local LOG=$1; shift

    IOPS_R=$(jq .jobs[].read.iops $LOG)
    BW_R=$(jq .jobs[].read.bw_bytes $LOG)
    LAT_AVG_R=$(jq .jobs[].read.lat_ns.mean $LOG)

    IOPS_W=$(jq .jobs[].write.bw_bytes $LOG)
    BW_W=$(jq .jobs[].write.iops $LOG)
    LAT_AVG_W=$(jq .jobs[].write.lat_ns.mean $LOG)
}

function print_report()
{
    local HOSTS=$@
    local SUM_IOPS_R=0
    local SUM_BW_R=0

    echo "Test parameters"
    echo "Time        : $TEST_TIME"
    echo "Read/write  : $RW"
    echo "Queue depth : $QD"
    echo "IO size     : $IO_SIZE"
    echo "Fio job     : $FIO_JOB"
    echo ""

    echo Results
    local FORMAT="%-30s | %-10s | %-10s | %-15s | %-15s\n"
    printf "$FORMAT" "Host" "kIOPS" "BW,Gb/s" "AVG_LAT,us" "Wire BW,Gb/s"
    printf "$FORMAT" | tr " " "-"

    for host in $HOSTS; do
	parse_fio $OUT_PATH/fio-$host.json
	SUM_IOPS_R=$(m $SUM_IOPS_R + $IOPS_R)
	SUM_BW_R=$(m $SUM_BW_R + $BW_R)

	printf "$FORMAT" $host $(m $IOPS_R/1000) $(m $BW_R*8/1000^3) $(m $LAT_AVG_R/1000)
    done

    printf "$FORMAT" | tr " " "-"

    if [ "1" == "$ENABLE_DEVICE_COUNTERS" ]; then
	local TX_BW_WIRE=$(jq '.analysis[].analysisAttribute | select(.name=="TX BandWidth") | .value' $OUT_PATH/device-counters.json)
    fi
    printf "$FORMAT" "Total" $(m $SUM_IOPS_R/1000) $(m $SUM_BW_R*8/1000^3) "" "$TX_BW_WIRE"
}

function run_fio()
{
    local HOST=$1; shift
    local JOB=$1; shift

    [ -z "$JOB" ] && JOB=$FIO_JOBS_PATH/$FIO_JOB-$HOST.job

    local SSH=
    [ "$HOST" != "$HOSTNAME" ] && SSH="ssh $HOST"

    $SSH sudo LD_PRELOAD=$SPDK_PATH/install-$HOST/lib/fio_plugin $FIO_PATH/install-$HOST/bin/fio --output=$OUT_PATH/fio-$HOST.json $FIO_PARAMS $JOB
}

function progress_bar()
{
    local TIME=$1
    for i in $(seq $TIME); do
	sleep 1
	echo -n .
    done
}

function run_test()
{
    local HOSTS=$@

    local PIDS=
    for host in $HOSTS; do
	run_fio $host > $OUT_PATH/fio-$host.log 2>&1 &
	PIDS="$PIDS $!"
    done

    # Wait 1/3, get counters, wait 2/3
    progress_bar $((TEST_TIME/3))
    if [ "1" == "$ENABLE_DEVICE_COUNTERS" ]; then
	get_device_counters
	echo -n "-"
    fi
    progress_bar $((TEST_TIME*2/3-2))
    echo "!"
    wait $PIDS
}

run_test $HOSTS
print_report $HOSTS
