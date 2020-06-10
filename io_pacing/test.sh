#!/usr/bin/env bash

# Input test parameters
TEST_TIME=${TEST_TIME-60}
RW=${RW-randread}
QD=${QD-32}
IO_SIZE=${IO_SIZE-128k}
HOSTS="spdk04.swx.labs.mlnx spdk05.swx.labs.mlnx"
TARGET="ubuntu@swx-bw-07"
TARGET_ADDRS="1.1.107.1 2.2.107.1"
FIO_JOB=${FIO_JOB-"fio-16ns"}
FIO_RAMP_TIME=${FIO_RAMP_TIME-5}
KERNEL_DRIVER=${KERNEL_DRIVER-0}

# Paths configuration
FIO_PATH="$PWD/../../fio"
SPDK_PATH="$PWD/.."
FIO_JOBS_PATH="$PWD/jobs"
OUT_PATH="$PWD/out"
mkdir -p $OUT_PATH
TARGET_SPDK_PATH="/home/ubuntu/work/spdk"
TARGET_BF_COUNTERS="/home/ubuntu/work/bf_counters.py"

# Other configurations
ENABLE_DEVICE_COUNTERS=1
ENABLE_DETAILED_STATS=1

# Internal variables

function m()
{
    M_SCALE=${M_SCALE-1}
    bc 2>/dev/null <<< "scale=$M_SCALE; $@"
}

function get_device_counters()
{
    ssh $TARGET sudo python /opt/neohost/sdk/get_device_performance_counters.py --dev-uid=0000:17:00.0 --output-format=JSON > $OUT_PATH/device-counters.json
}

function get_bf_counters()
{
    ssh $TARGET sudo python $TARGET_BF_COUNTERS > $OUT_PATH/bf_counters.log
}

function parse_fio()
{
    local LOG=$1; shift

    IOPS_R=$(jq .jobs[].read.iops $LOG 2>/dev/null)
    BW_R=$(jq .jobs[].read.bw_bytes $LOG 2>/dev/null)
    BW_STDDEV_R=$(jq .jobs[].read.bw_dev $LOG 2>/dev/null)
    LAT_AVG_R=$(jq .jobs[].read.lat_ns.mean $LOG 2>/dev/null)

    IOPS_W=$(jq .jobs[].write.bw_bytes $LOG 2>/dev/null)
    BW_W=$(jq .jobs[].write.iops $LOG 2>/dev/null)
    BW_STDDEV_W=$(jq .jobs[].write.bw_dev $LOG 2>/dev/null)
    LAT_AVG_W=$(jq .jobs[].write.lat_ns.mean $LOG 2>/dev/null)
}

function print_report()
{
    local HOSTS=$@
    local SUM_IOPS_R=0
    local SUM_BW_R=0
    local SUM_BW_STDDEV_R=0
    local SUM_LAT_AVG_R=0

    echo "Test parameters"
    echo "Time        : $TEST_TIME"
    echo "Read/write  : $RW"
    echo "Queue depth : $QD"
    echo "IO size     : $IO_SIZE"
    echo "Fio job     : $FIO_JOB"
    echo ""

    echo Results
    local FORMAT="%-30s | %-10s | %-10s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n"
    printf "$FORMAT" "Host" "kIOPS" "BW,Gb/s" "AVG_LAT,us" "Wire BW,Gb/s" "BW STDDEV" "L3 Hit Rate, %" "Bufs in-flight" "Pacer period, us"
    printf "$FORMAT" | tr " " "-"

    local count=0
    for host in $HOSTS; do
	parse_fio $OUT_PATH/fio-$host.json
	SUM_IOPS_R=$(m $SUM_IOPS_R + $IOPS_R)
	SUM_BW_R=$(m $SUM_BW_R + $BW_R)
	SUM_BW_STDDEV_R=$(m $SUM_BW_STDDEV_R + $BW_STDDEV_R^2)
	SUM_LAT_AVG_R=$(m $SUM_LAT_AVG_R + $LAT_AVG_R)

	printf "$FORMAT" $host $(m $IOPS_R/1000) $(m $BW_R*8/1000^3) $(m $LAT_AVG_R/1000)
	((count+=1))
    done
    SUM_LAT_AVG_R=$(m $SUM_LAT_AVG_R / $count)
    SUM_BW_STDDEV_R=$(m "sqrt($SUM_BW_STDDEV_R / $count)")

    printf "$FORMAT" | tr " " "-"

    if [ "1" == "$ENABLE_DEVICE_COUNTERS" ]; then
	local TX_BW_WIRE=$(jq '.analysis[].analysisAttribute | select(.name=="TX BandWidth") | .value' $OUT_PATH/device-counters.json 2>/dev/null)
	local L3_HIT_RATE=0
	for l3hr in $(grep -Po "(?<=Hit Rate: )[0-9]*\.[0-9]*(?=%)" $OUT_PATH/bf_counters.log); do
	    L3_HIT_RATE=$(m $L3_HIT_RATE + $l3hr)
	done
	L3_HIT_RATE=$(m $L3_HIT_RATE/4)

	local BUFFERS_ALLOCATED=0
	for ba in $(jq .poll_groups[].transports[].buffers_allocated $OUT_PATH/nvmf_stats.log); do
	    BUFFERS_ALLOCATED=$((BUFFERS_ALLOCATED + ba))
	done
	BUFFERS_ALLOCATED=$(m $BUFFERS_ALLOCATED/3)

	local TOTAL_TICKS=0
	for tt in $(jq .poll_groups[].transports[].io_pacer.total_ticks $OUT_PATH/nvmf_stats_final.log); do
	    TOTAL_TICKS=$((TOTAL_TICKS + tt))
	done
	local TOTAL_POLLS=0
	for tp in $(jq .poll_groups[].transports[].io_pacer.polls $OUT_PATH/nvmf_stats_final.log); do
	    TOTAL_POLLS=$((TOTAL_POLLS + tp))
	done
	local TICK_RATE=$(jq .tick_rate $OUT_PATH/nvmf_stats_final.log)
	local PACER_PERIOD=$(m 10^6*$TOTAL_TICKS/$TICK_RATE/$TOTAL_POLLS)

    fi
    printf "$FORMAT" "Total" $(m $SUM_IOPS_R/1000) $(m $SUM_BW_R*8/1000^3) "$(m $SUM_LAT_AVG_R/1000)" "$TX_BW_WIRE" "$(m $SUM_BW_STDDEV_R*8/1000^2)" "$L3_HIT_RATE" "$BUFFERS_ALLOCATED" "$PACER_PERIOD"
}

function set_fio_params()
{
    FIO_PARAMS="--stats=1 --group_reporting=1 --output-format=json --thread=1 \
    --numjobs=1 --cpus_allowed=1 --cpus_allowed_policy=split \
    --time_based=1 --runtime=$TEST_TIME --ramp_time=3 \
    --readwrite=$RW --bs=$IO_SIZE --iodepth=$QD"
}

function run_fio()
{
    local HOST=$1; shift
    local JOB=$1; shift

    [ -z "$JOB" ] && JOB=$FIO_JOBS_PATH/$FIO_JOB-$HOST.job

    local SSH=
    [ "$HOST" != "$HOSTNAME" ] && SSH="ssh $HOST"

    local FIO_PARAMS="--stats=1 --group_reporting=1 --thread=1 --direct=1 --norandommap \
    --time_based=1 --runtime=$TEST_TIME --ramp_time=$FIO_RAMP_TIME --file_service_type=roundrobin:1 \
    --readwrite=$RW --bs=$IO_SIZE --iodepth=$QD"

    [ -z "$FIO_NO_JSON" ] && FIO_PARAMS="--output-format=json --output=$OUT_PATH/fio-$HOST.json $FIO_PARAMS"

    echo "$HOST"
    echo "$JOB"
    echo "$FIO_PARAMS"
    $SSH sudo LD_PRELOAD=$SPDK_PATH/install-$HOST/lib/fio_plugin $FIO_PATH/install-$HOST/bin/fio $FIO_PARAMS $JOB
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

    echo "" > $OUT_PATH/nvmf_stats.log

    local PIDS=
    for host in $HOSTS; do
	run_fio $host > $OUT_PATH/fio-$host.log 2>&1 &
	PIDS="$PIDS $!"
	sleep 1
    done

    progress_bar $FIO_RAMP_TIME

    if [ "1" == "$ENABLE_DEVICE_COUNTERS" ]; then
	# Get nvmf stats 3 times and other stats one time
	progress_bar $((TEST_TIME/5))
	RPC_OUT=$OUT_PATH/nvmf_stats.log rpc nvmf_get_stats
	progress_bar $((TEST_TIME/5))
	get_device_counters
	get_bf_counters
	RPC_OUT=$OUT_PATH/nvmf_stats.log rpc nvmf_get_stats
	echo -n "-"
	progress_bar $((TEST_TIME/5))
	RPC_OUT=$OUT_PATH/nvmf_stats.log rpc nvmf_get_stats
    else
	progress_bar $((TEST_TIME))
    fi
    echo "!"
    wait $PIDS

    # Collect some stats
    echo "" > $OUT_PATH/thread_stats_final.log
    echo "" > $OUT_PATH/nvmf_stats_final.log
    echo "" > $OUT_PATH/bdev_stats_final.log

    RPC_OUT=$OUT_PATH/thread_stats_final.log rpc thread_get_stats
    RPC_OUT=$OUT_PATH/nvmf_stats_final.log rpc nvmf_get_stats
    RPC_OUT=$OUT_PATH/bdev_stats_final.log rpc bdev_get_iostat
}

function start_tgt()
{
    local CPU_MASK=$1; shift

    ssh $TARGET sudo $TARGET_SPDK_PATH/install/bin/spdk_tgt --wait-for-rpc -m $CPU_MASK > $OUT_PATH/tgt.log 2>&1 &
    sleep 10
}

function stop_tgt()
{
    ssh $TARGET 'sudo kill -15 $(pidof spdk_tgt)' >> $OUT_PATH/rpc.log 2>&1
    sleep 5
}

function connect_hosts()
{
    local HOSTS=$@
    NUM_QUEUES=${NUM_QUEUES-8}

    for host in $HOSTS; do
	local SSH=
	[ "$host" != "$HOSTNAME" ] && SSH="ssh $host"

	# Assuming that each host has path to only one listener and
	# another one will fail to connect
	for addr in $TARGET_ADDRS; do
	    $SSH sudo nvme connect -t rdma -a $addr  -s 4420 -n nqn.2016-06.io.spdk:cnode1 -i $NUM_QUEUES >> $OUT_PATH/rpc.log 2>&1
	done
    done
}

function disconnect_hosts()
{
    local HOSTS=$@

    for host in $HOSTS; do
	local SSH=
	[ "$host" != "$HOSTNAME" ] && SSH="ssh $host"

	$SSH sudo nvme disconnect -n nqn.2016-06.io.spdk:cnode1 >> $OUT_PATH/rpc.log 2>&1
    done
}

function rpc()
{
    RPC_OUT=${RPC_OUT-"$OUT_PATH/rpc.log"}
    ssh $TARGET sudo $TARGET_SPDK_PATH/scripts/rpc.py $@ >> $RPC_OUT 2>&1
}

function rpc_start()
{
    [ -e rpc_pipe ] && rm rpc_pipe
    mkfifo rpc_pipe
    tail -f > rpc_pipe &
    RPC_PID=$!
    ssh $TARGET sudo $TARGET_SPDK_PATH/scripts/rpc.py -v --server >> $OUT_PATH/rpc.log 2>&1 < rpc_pipe &
    SSH_PID=$!
}

function rpc_send()
{
    echo "$@" > rpc_pipe
}

function rpc_stop()
{
    kill $RPC_PID >> $OUT_PATH/rpc.log 2>&1
    wait $SSH_PID
    rm rpc_pipe
}

function basic_test()
{
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	QD_LIST=${QD_LIST-"32 64 128 256 1024 2048"}
    else
	QD_LIST=${QD_LIST-"2 4 8 16 32"}
    fi
    REPEAT=${REPEAT-1}
    local FORMAT="| %-10s | %-10s | %-10s | %-15s | %-10s | %-15s | %-25s | %-15s\n"
    printf "$FORMAT" "QD" "BW" "WIRE BW" "AVG LAT, us" "BW STDDEV" "L3 Hit Rate" "Bufs in-flight (MiB)" "Pacer period, us"

    for qd in $QD_LIST; do
	for rep in $(seq $REPEAT); do
	    QD=$qd run_test $HOSTS > /dev/null
	    OUT=$(print_report $HOSTS | tee $OUT_PATH/basic_test.log)
	    BW="$(echo "$OUT" | grep Total | awk '{print $5}')"
	    LAT_AVG="$(echo "$OUT" | grep Total | awk '{print $7}')"
	    WIRE_BW="$(echo "$OUT" | grep Total | awk '{print $9}')"
	    BW_STDDEV="$(echo "$OUT" | grep Total | awk '{print $11}')"
	    L3_HIT_RATE="$(echo "$OUT" | grep Total | awk '{print $13}')"
	    BUFFERS_ALLOCATED="$(echo "$OUT" | grep Total | awk '{print $15}')"
	    PACER_PERIOD="$(echo "$OUT" | grep Total | awk '{print $17}')"
	    printf "$FORMAT" "$qd" "$BW" "$WIRE_BW" "$LAT_AVG" "$BW_STDDEV" "$L3_HIT_RATE" "$BUFFERS_ALLOCATED ($(m $BUFFERS_ALLOCATED*128/1024))" "$PACER_PERIOD"
	    if [ -n "$ENABLE_DETAILED_STATS" ]; then
		./parse_stats.sh
	    fi
	done
    done
}

function config_null_1()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size 4096 \
	     --max-io-size 131072 \
	     --io-unit-size 131072 \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    rpc_send bdev_null_create Null0 8192 4096
    rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Null0
    rpc_stop
    sleep 1
}

function config_null_16()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size 4096 \
	     --max-io-size 131072 \
	     --io-unit-size 131072 \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    for i in $(seq 16); do
	rpc_send bdev_null_create Null$i 8192 4096
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Null$i
    done
    rpc_stop
    sleep 1
}

function config_nvme()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-128}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    local DISKS="05 06 07 08 09 0a 0b 0c 0f 10 11 12 13 14 15 16"
    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size 4096 \
	     --max-io-size 131072 \
	     --io-unit-size 131072 \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    local i=0
    for pci in $DISKS; do
	rpc_send bdev_nvme_attach_controller --name Nvme$i \
		 --trtype pcie \
		 --traddr 0000:$pci:00.0
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Nvme${i}n1
	((i+=1))
    done
    rpc_stop
    sleep 1
}

function config_nvme_split3_delay()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-128}
    NUM_DELAY_BDEVS=${NUM_DELAY_BDEVS-0}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    IO_PACER_DISK_CREDIT=6
    local DISKS="05 06 07 08 09 0a 0b 0c 0f 10 11 12 13 14 15 16"
    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size 4096 \
	     --max-io-size 131072 \
	     --io-unit-size 131072 \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP \
         --io-pacer-disk-credit $IO_PACER_DISK_CREDIT
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    local i=0
    for pci in $DISKS; do
	rpc_send bdev_nvme_attach_controller --name Nvme$i \
		 --trtype pcie \
		 --traddr 0000:$pci:00.0
	rpc_send bdev_split_create Nvme${i}n1 3
	((i+=1))
    done
    local num_disks=$i
    i=0
    for part in 0 1 2; do
	for disk in $(seq 0 $((num_disks-1))); do
	    local ns_id=$((disk*3 + part + 1))
	    if [ "$i" -lt "$NUM_DELAY_BDEVS" ]; then
		rpc_send bdev_delay_create --base-bdev-name Nvme${disk}n1p${part} \
			 --name Nvme${disk}n1p${part}d \
			 --avg-read-latency 1000 \
			 --nine-nine-read-latency 1000 \
			 --avg-write-latency 1000 \
			 --nine-nine-write-latency 1000
		rpc_send nvmf_subsystem_add_ns -n $ns_id nqn.2016-06.io.spdk:cnode1 Nvme${disk}n1p${part}d
	    else
		rpc_send nvmf_subsystem_add_ns -n $ns_id nqn.2016-06.io.spdk:cnode1 Nvme${disk}n1p${part}
	    fi
	    ((i+=1))
	done
    done
    rpc_stop
    sleep 1
}

function test_1()
{
    start_tgt 0xF
    config_null_1
    FIO_JOB=fio-1ns basic_test
    stop_tgt
}

function test_2()
{
    start_tgt 0xF
    config_null_16
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-16ns basic_test
    else
	connect_hosts $HOSTS
	FIO_JOB=fio-kernel-16ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_3()
{
    start_tgt 0xF
    config_nvme
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	QD_LIST="32 36 40 44 48 64 128 256 1024 2048" FIO_JOB=fio-16ns basic_test
    else
	connect_hosts $HOSTS
	FIO_JOB=fio-kernel-16ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_4()
{
    start_tgt 0xF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=24 config_null_16
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-16ns basic_test
    else
	connect_hosts $HOSTS
	FIO_JOB=fio-kernel-16ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_5()
{
    start_tgt 0xF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=24 config_nvme
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-16ns basic_test
    else
	connect_hosts $HOSTS
	FIO_JOB=fio-kernel-16ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_6()
{
    start_tgt 0xF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=24 config_nvme
    FIO_JOB=fio-16ns QD_LIST="32 256 1024 2048" REPEAT=10 basic_test
    stop_tgt
}

function test_7()
{
    for cpu_mask in FFFF FF F 3 1; do
	local bin_mask=$(m "ibase=16; obase=2; $cpu_mask")
	bin_mask=${bin_mask//0/}
	local core_count=${#bin_mask}
	local cache_size=$((96/core_count))
	echo "Target cores $core_count (0x$cpu_mask). Buffer cache size $cache_size"
	start_tgt 0x$cpu_mask
	NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$cache_size config_nvme
	FIO_JOB=fio-16ns basic_test
	stop_tgt
	sleep 3
    done
}

function test_8()
{
    for cache_size in 6 3 1 0; do
	echo "Buffer cache size $cache_size"
	start_tgt 0xFFFF
	NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$cache_size config_nvme
	FIO_JOB=fio-16ns basic_test
	stop_tgt
	sleep 3
    done
}

function test_9()
{
    for num_buffers in 128 96 64 48 44 40 36 32 24 16; do
	local cache_size=$((num_buffers/16))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"
	start_tgt 0xFFFF
	NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$cache_size config_nvme
	if [ 0 -eq "$KERNEL_DRIVER" ]; then
	    QD_LIST=256 FIO_JOB=fio-16ns basic_test
	else
	    connect_hosts $HOSTS
	    QD_LIST=32 FIO_JOB=fio-kernel-16ns basic_test
	    disconnect_hosts $HOSTS
	fi
	stop_tgt
	sleep 3
    done
}

function test_10()
{
    for num_buffers in 128 96 64 48 44 40 36 32 24 16; do
	local cache_size=$((num_buffers/4))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"
	start_tgt 0xF
	NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$cache_size config_nvme
	if [ 0 -eq "$KERNEL_DRIVER" ]; then
	    QD_LIST="256 1024" FIO_JOB=fio-16ns basic_test
	else
	    connect_hosts $HOSTS
	    QD_LIST=32 FIO_JOB=fio-kernel-16ns basic_test
	    disconnect_hosts $HOSTS
	fi
	stop_tgt
	sleep 3
    done
}

function test_11()
{
    local CPU_MASK=0xF
    local NUM_CORES=4

    for num_buffers in 96 48; do
	for num_delay in 0 16 32; do
	    echo "| $CPU_MASK | $num_buffers | $num_delay"
	    start_tgt $CPU_MASK
	    NUM_DELAY_BDEVS=$num_delay NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/NUM_CORES)) config_nvme_split3_delay
	    if [ 0 -eq "$KERNEL_DRIVER" ]; then
		QD_LIST="85 341" FIO_JOB=fio-48ns basic_test
	    else
		connect_hosts $HOSTS
		QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
		disconnect_hosts $HOSTS
	    fi
	    stop_tgt
	done
    done
}

function test_12()
{
    local CPU_MASK=0xF
    local NUM_CORES=4

    for num_buffers in 48; do
	for num_delay in 16 32; do
	    echo "| $CPU_MASK | $num_buffers | $num_delay"
	    start_tgt $CPU_MASK
	    NUM_DELAY_BDEVS=$num_delay NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/NUM_CORES)) config_nvme_split3_delay
	    if [ 0 -eq "$KERNEL_DRIVER" ]; then
		QD_LIST="1 2 4 8 16 32 64" FIO_JOB=fio-48ns basic_test
	    else
		connect_hosts $HOSTS
		QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
		disconnect_hosts $HOSTS
	    fi
	    stop_tgt
	done
    done
}

# Test latencies
function test_13()
{
    local CPU_MASK=0xF
    local NUM_CORES=4
    HOSTS="spdk03.swx.labs.mlnx"

    for num_buffers in 48; do

	# 16 Null disks
	start_tgt $CPU_MASK
	NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/NUM_CORES)) config_null_16
	if [ 0 -eq "$KERNEL_DRIVER" ]; then
	    QD_LIST="1" FIO_JOB=fio-16ns basic_test
	else
	    connect_hosts $HOSTS
	    QD_LIST="1" FIO_JOB=fio-kernel-16ns basic_test
	    disconnect_hosts $HOSTS
	fi
	stop_tgt

	# 16 NVMe disks
	start_tgt $CPU_MASK
	NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/NUM_CORES)) config_nvme
	if [ 0 -eq "$KERNEL_DRIVER" ]; then
	    QD_LIST="1" FIO_JOB=fio-16ns basic_test
	else
	    connect_hosts $HOSTS
	    QD_LIST="1" FIO_JOB=fio-kernel-16ns basic_test
	    disconnect_hosts $HOSTS
	fi
	stop_tgt

	# 48 split and delay disks
	for num_delay in 0 48; do
	    echo "| $CPU_MASK | $num_buffers | $num_delay"
	    start_tgt $CPU_MASK
	    NUM_DELAY_BDEVS=$num_delay NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/NUM_CORES)) config_nvme_split3_delay
	    if [ 0 -eq "$KERNEL_DRIVER" ]; then
		QD_LIST="1" FIO_JOB=fio-48ns basic_test
	    else
		connect_hosts $HOSTS
		QD_LIST="1" FIO_JOB=fio-kernel-48ns basic_test
		disconnect_hosts $HOSTS
	    fi
	    stop_tgt
	done
    done
}


function test_14()
{
    local CPU_MASK=0xF0
    local NUM_CORES=4

    for io_pacer in 5600 5650 5700 5750 5800 6000; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD"
	start_tgt $CPU_MASK
	IO_PACER_PERIOD=$ADJUSTED_PERIOD config_nvme
	if [ 0 -eq "$KERNEL_DRIVER" ]; then
	    QD_LIST="256 1024 2048" FIO_JOB=fio-16ns basic_test
	else
	    connect_hosts $HOSTS
	    FIO_JOB=fio-kernel-16ns basic_test
	    disconnect_hosts $HOSTS
	fi
	stop_tgt
    done
}

function test_16_pacing_internal()
{
    local CPU_MASK=$1
    local NUM_CORES=$2
    local ADJUSTED_PERIOD=$3

	for num_delay in 16 32; do
	    echo "| $CPU_MASK | $num_buffers | $num_delay"
	    start_tgt $CPU_MASK
	    IO_PACER_PERIOD=$ADJUSTED_PERIOD NUM_DELAY_BDEVS=$num_delay config_nvme_split3_delay
	    if [ 0 -eq "$KERNEL_DRIVER" ]; then
		QD_LIST="1 2 4 8 16 32 64" FIO_JOB=fio-48ns basic_test
	    else
		connect_hosts $HOSTS
		QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
		disconnect_hosts $HOSTS
	    fi
	    stop_tgt
    done
}

function test_16()
{
    local CPU_MASK=0xF0
    local NUM_CORES=4

    #for io_pacer in 5600 5650 5700 5750 5800 6000; do
    for io_pacer in 5750 6000; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD"
        test_16_pacing_internal $CPU_MASK $NUM_CORES $ADJUSTED_PERIOD 
    done
}


function test_17_pacing_internal()
{
    local CPU_MASK=$1
    local NUM_CORES=$2
    local ADJUSTED_PERIOD=$3

	#for num_delay in 16 32; do
	for num_delay in 16; do
	    echo "| $CPU_MASK | $num_buffers | $num_delay"
	    start_tgt $CPU_MASK
	    IO_PACER_PERIOD=$ADJUSTED_PERIOD NUM_DELAY_BDEVS=$num_delay config_nvme_split3_delay
	    if [ 0 -eq "$KERNEL_DRIVER" ]; then
		#QD_LIST="1 2 4 8 16 32 64" FIO_JOB=fio-48ns basic_test
		QD_LIST="8" FIO_JOB=fio-48ns basic_test
	    else
		connect_hosts $HOSTS
		QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
		disconnect_hosts $HOSTS
	    fi
	    stop_tgt
    done
}

function test_17()
{
    local CPU_MASK=0xF0
    local NUM_CORES=4

    #for io_pacer in 5600 5650 5700 5750 5800 6000; do
    #for io_pacer in 5750 6000; do
    for io_pacer in 6000; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD"
        test_17_pacing_internal $CPU_MASK $NUM_CORES $ADJUSTED_PERIOD 
    done
}

function test_tgt()
{
    local CPU_MASK=0xF0
    local NUM_CORES=4
    local IO_PACER="6000"

    start_tgt $CPU_MASK
    IO_PACER_PERIOD="$(M_SCALE=0 m $IO_PACER \* $NUM_CORES / 1)" config_nvme
    echo "Running"
    progress_bar $TEST_TIME
    echo "Stopping"
    stop_tgt
}

function test_fio()
{
    QD=2048 FIO_NO_JSON=1 FIO_JOB=fio-16ns run_fio $HOSTNAME
}

if [ -z "$1" ]; then
    declare -F | grep ' -f test' | cut -d " " -f 3
    exit 0
fi

for test in $@; do
    echo "$test"
    $test
done
