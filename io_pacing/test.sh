#!/usr/bin/env bash

# Input test parameters
TEST_TIME=${TEST_TIME-60}
RW=${RW-randread}
QD=${QD-32}
IO_SIZE=${IO_SIZE-128k}
HOSTS="r-dcs79 spdk03.swx.labs.mlnx"
TARGET="ubuntu@spdk-tgt-bw-03"
TARGET_ADDRS="1.1.103.1 2.2.103.1"
FIO_JOB=${FIO_JOB-"fio-16ns"}
KERNEL_DRIVER=${KERNEL_DRIVER-0}

# Paths configuration
FIO_PATH="$PWD/../../fio"
SPDK_PATH="$PWD/.."
FIO_JOBS_PATH="$PWD/jobs"
OUT_PATH="$PWD/out"
mkdir -p $OUT_PATH
TARGET_SPDK_PATH="/home/evgeniik/spdk"

# Other configurations
ENABLE_DEVICE_COUNTERS=1

# Internal variables

function m()
{
    bc 2>/dev/null <<< "scale=1; $@"
}

function get_device_counters()
{
    ssh $TARGET sudo python /opt/neohost/sdk/get_device_performance_counters.py --dev-uid=0000:17:00.0 --output-format=JSON > $OUT_PATH/device-counters.json
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
    local FORMAT="%-30s | %-10s | %-10s | %-15s | %-15s | %-15s\n"
    printf "$FORMAT" "Host" "kIOPS" "BW,Gb/s" "AVG_LAT,us" "Wire BW,Gb/s" "BW STDDEV"
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
    fi
    printf "$FORMAT" "Total" $(m $SUM_IOPS_R/1000) $(m $SUM_BW_R*8/1000^3) "$(m $SUM_LAT_AVG_R/1000)" "$TX_BW_WIRE" "$(m $SUM_BW_STDDEV_R*8/1000^2)"
}

function run_fio()
{
    local HOST=$1; shift
    local JOB=$1; shift

    [ -z "$JOB" ] && JOB=$FIO_JOBS_PATH/$FIO_JOB-$HOST.job

    local SSH=
    [ "$HOST" != "$HOSTNAME" ] && SSH="ssh $HOST"

    local FIO_PARAMS="--stats=1 --group_reporting=1 --thread=1 --direct=1 --norandommap\
    --output-format=json --output=$OUT_PATH/fio-$HOST.json \
    --time_based=1 --runtime=$TEST_TIME --ramp_time=3 \
    --readwrite=$RW --bs=$IO_SIZE --iodepth=$QD"

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

function start_tgt()
{
    local CPU_MASK=$1; shift

    ssh $TARGET sudo $TARGET_SPDK_PATH/install/bin/spdk_tgt --wait-for-rpc -m $CPU_MASK > $OUT_PATH/tgt.log 2>&1 &
    sleep 10
}

function stop_tgt()
{
    # Collect some stats
    rpc thread_get_stats
    rpc nvmf_get_stats
    rpc bdev_get_iostat

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
    ssh $TARGET sudo $TARGET_SPDK_PATH/scripts/rpc.py $@ >> $OUT_PATH/rpc.log 2>&1
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
	QD_LIST=${QD_LIST-"8 16 32 64 128 256"}
    else
	QD_LIST=${QD_LIST-"2 4 8 16 32"}
    fi
    REPEAT=${REPEAT-1}
    local FORMAT="| %-10s | %-10s | %-10s | %-15s | %-10s\n"
    printf "$FORMAT" "QD" "BW" "WIRE BW" "AVG LAT, us" "BW STDDEV"

    for qd in $QD_LIST; do
	for rep in $(seq $REPEAT); do
	    QD=$qd run_test $HOSTS > /dev/null
	    OUT=$(print_report $HOSTS | tee $OUT_PATH/basic_test.log)
	    BW="$(echo "$OUT" | grep Total | awk '{print $5}')"
	    LAT_AVG="$(echo "$OUT" | grep Total | awk '{print $7}')"
	    WIRE_BW="$(echo "$OUT" | grep Total | awk '{print $9}')"
	    BW_STDDEV="$(echo "$OUT" | grep Total | awk '{print $11}')"
	    printf "$FORMAT" "$qd" "$BW" "$WIRE_BW" "$LAT_AVG" "$BW_STDDEV"
	done
    done
}

function config_null_1()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
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
	     --max-srq-depth 4096
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 1.1.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 2.2.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send bdev_null_create Null0 8192 4096
    rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Null0
    rpc_stop
    sleep 1
}

function config_null_16()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
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
	     --max-srq-depth 4096
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 1.1.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 2.2.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
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
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
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
	     --max-srq-depth 4096
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 1.1.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 2.2.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1

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

function config_nvme_split3()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
    local DISKS="05 06 07 08 09 0a 0b 0c 0f 10 11 12 13 14 15 16"
    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    local i=0
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size 4096 \
	     --max-io-size 131072 \
	     --io-unit-size 131072 \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 1.1.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 2.2.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    for pci in $DISKS; do
	rpc_send bdev_nvme_attach_controller --name Nvme$i \
		 --trtype pcie \
		 --traddr 0000:$pci:00.0
	rpc_send bdev_split_create Nvme${i}n1 3
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Nvme${i}n1p0
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Nvme${i}n1p1
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Nvme${i}n1p2
	((i+=1))
    done
    rpc_stop
    sleep 1
}

function config_nvme_split3_delay()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
    NUM_DELAY_BDEVS=${NUM_DELAY_BDEVS-0}
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
	     --max-srq-depth 4096
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 1.1.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1
    rpc_send nvmf_subsystem_add_listener --trtype rdma \
	     --traddr 2.2.103.1 \
	     --adrfam ipv4 \
	     --trsvcid 4420 \
	     nqn.2016-06.io.spdk:cnode1

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
    start_tgt 0xFFFF
    config_null_1
    FIO_JOB=fio-1ns basic_test
    stop_tgt
}

function test_2()
{
    start_tgt 0xFFFF
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
    start_tgt 0xFFFF
    config_nvme
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-16ns basic_test
    else
	connect_hosts $HOSTS
	FIO_JOB=fio-kernel-16ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_4()
{
    start_tgt 0xFFFF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_null_16
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
    start_tgt 0xFFFF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme
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
    start_tgt 0xFFFF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme
    FIO_JOB=fio-16ns QD_LIST="32 64 128 256" REPEAT=10 basic_test
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

function test_11()
{
    start_tgt 0xFFFF
    config_nvme_split3
    FIO_JOB=fio-48ns basic_test
    stop_tgt
}

function test_12()
{
    start_tgt 0xFFFF
    NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme_split3
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-48ns basic_test
    else
	connect_hosts $HOSTS
	QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_13()
{
    start_tgt 0xFFFF
    NUM_DELAY_BDEVS=16 config_nvme_split3_delay
    FIO_JOB=fio-48ns basic_test
    stop_tgt
}

function test_14()
{
    start_tgt 0xFFFF
    NUM_DELAY_BDEVS=16 NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme_split3_delay
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-48ns basic_test
    else
	connect_hosts $HOSTS
	QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

function test_15()
{
    start_tgt 0xFFFF
    NUM_DELAY_BDEVS=32 config_nvme_split3_delay
    FIO_JOB=fio-48ns basic_test
    stop_tgt
}

function test_16()
{
    start_tgt 0xFFFF
    NUM_DELAY_BDEVS=32 NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme_split3_delay
    if [ 0 -eq "$KERNEL_DRIVER" ]; then
	FIO_JOB=fio-48ns basic_test
    else
	connect_hosts $HOSTS
	QD_LIST=32 FIO_JOB=fio-kernel-48ns basic_test
	disconnect_hosts $HOSTS
    fi
    stop_tgt
}

if [ -z "$1" ]; then
    declare -F | grep ' -f test' | cut -d " " -f 3
    exit 0
fi

for test in $@; do
    echo "$test"
    $test
done
