#!/usr/bin/env bash

SPDK_PATH=.
FIO=../fio/fio
NVMF_TGT=$SPDK_PATH/app/nvmf_tgt/nvmf_tgt
RPC_PY=$SPDK_PATH/scripts/rpc.py
SPDK_PERF=$SPDK_PATH/examples/nvme/perf/perf
SPDK_FIO_PLUGIN=$SPDK_PATH/examples/nvme/fio_plugin/fio_plugin
DEFAULT_NVME_DEVICE="0000:81:00.0"
DEFAULT_IP_ADDR=1.1.75.1
TGT_LOG_FILE=./nvmf_tgt.log.$$


# Initialize started  SPDK NVMF target
# Args:
# - QUEUE_DEPTH=16
# - MAX_QPAIRS=64
# - IN_CAPSULE_DATA_SIZE=4096
nvmf_tgt_init () {
    local QUEUE_DEPTH=${1:-16}; shift
    local MAX_QPAIRS=${1:-64}; shift
    local IN_CAPSULE_DATA_SIZE=${1:-4096}; shift

    while ! ls /var/tmp/spdk.sock > /dev/null 2>&1
    do
	sleep 1
    done
    sleep 5

    $RPC_PY set_nvmf_target_options -p $MAX_QPAIRS -q $QUEUE_DEPTH -c $IN_CAPSULE_DATA_SIZE
    $RPC_PY start_subsystem_init
    $RPC_PY nvmf_create_transport -t RDMA -p $MAX_QPAIRS -q $QUEUE_DEPTH -c $IN_CAPSULE_DATA_SIZE

    echo "Started NVMF target, pid $(pidof "$NVMF_TGT"), cpu_mask $CPU_MASK, queue_depth $QUEUE_DEPTH, max_qpairs $MAX_QPAIRS, in_capsule_data $IN_CAPSULE_DATA_SIZE"
}



# Start SPDK NVMF target
# Args:
# - CPU_MASK=0x01
# - QUEUE_DEPTH=16
# - MAX_QPAIRS=64
# - IN_CAPSULE_DATA_SIZE=4096
nvmf_tgt_start () {
    local CPU_MASK=${1:-"0x01"}; shift
    rm -rf /var/tmp/spdk.sock
    $NVMF_TGT -m $CPU_MASK --wait-for-rpc -s 4096 2>&1 | tee $TGT_LOG_FILE &
    nvmf_tgt_init $@
}

# Start SPDK NVMF target
# Args:
# - CONFIG_FILE=nvmf.conf
# - CPU_MASK=0x01
nvmf_tgt_start_conf () {
    local CONFIG_FILE=${1:-"nvmf.conf"}; shift
    local CPU_MASK=${1:-"0x01"}; shift
    rm -rf /var/tmp/spdk.sock
    $NVMF_TGT -m $CPU_MASK -c $CONFIG_FILE 2>&1 | tee $TGT_LOG_FILE &
    while ! ls /var/tmp/spdk.sock > /dev/null 2>&1
    do
	sleep 1
    done
    sleep 5

}


# Stop previously started NVFM target
nvmf_tgt_stop () {
    $RPC_PY kill_instance 15
    while pidof nvmf_tgt > /dev/null
    do
	sleep 1
    done
    sleep 3
    echo "Stopped NVMF target"
}

# Add NULL bdev
# Args:
# - NAME=Null
# - SIZE=1024
# - BLOCK_SIZE=512
nvmf_tgt_add_null_bdev () {
    local NAME=${1:-"Null"}; shift
    local SIZE=${1:-1024}; shift
    local BLOCK_SIZE=${1:-512}; shift

    $RPC_PY construct_null_bdev $NAME $SIZE $BLOCK_SIZE
}

# Add PCIe NVMe bdev
# Args:
# - NAME=Nvme
# - ADDR=Default NVMe device
nvmf_tgt_add_nvme_bdev () {
    local NAME=${1:-"Nvme"}; shift
    local ADDR=${1:-$DEFAULT_NVME_DEVICE}; shift

    $RPC_PY construct_nvme_bdev -b $NAME -t PCIe -a $ADDR -r 6
}

# Add RAID bdev
# Args:
# - NAME=Raid
# - STRIP_SIZE=32
# - RAID_LEVEL=0
# - BDEVS...
nvmf_tgt_add_raid_bdev () {
    local NAME=${1:-"Null"}; shift
    local STRIP_SIZE=${1:-32}; shift
    local RAID_LEVEL=${1:-0}; shift
    local BDEVS=$@

    $RPC_PY construct_raid_bdev -n $NAME -s $STRIP_SIZE -r $RAID_LEVEL -b "$BDEVS"
}

# Add NVMF subsytem
# Args:
# - NAME=cnode1
# - ADDR=Default IP address
# - PORT=4420
# - BDEVS...
nvmf_tgt_add_subsystem () {
    local NAME=${1:-"cnode1"}; shift
    local ADDR=${1:-$DEFAULT_IP_ADDR}; shift
    local PORT=${1:-4420}; shift
    local BDEVS="$@"

    local SUBSYS="nqn.2016-06.io.spdk:$NAME"
    $RPC_PY nvmf_subsystem_create $SUBSYS -s SPDK00000000000001 -a
    for bdev in "$BDEVS"
    do
	$RPC_PY nvmf_subsystem_add_ns $SUBSYS $bdev
    done
    $RPC_PY nvmf_subsystem_add_listener $SUBSYS -t RDMA -a $ADDR -s $PORT
}

# Connect NVMf subsystem
# Args:
# - NAME=cnode1
# - ADDR=Default IP address
# - PORT=4420
# - QUEUE_COUNT=8
# - QUEUE_SIZE=64
nvmf_connect () {
    local NAME=${1:-"cnode1"}; shift
    local ADDR=${1:-$DEFAULT_IP_ADDR}; shift
    local PORT=${1:-4420}; shift
    local QUEUE_COUNT=${1:-8}; shift
    local QUEUE_SIZE=${1:-64}; shift

    nvme connect -n nqn.2016-06.io.spdk:$NAME -t rdma -a $ADDR -s $PORT -i $QUEUE_COUNT -Q $QUEUE_SIZE
    echo "Connected to target $ADDR:$PORT subsystem $NAME"
}

# Disconnect NVMf subsystem
# Args:
# - NAME=cnode1
nvmf_disconnect () {
    local NAME=${1:-"cnode1"}; shift

    sleep 3
    nvme disconnect -n nqn.2016-06.io.spdk:$NAME
    echo "Disconnected from subsystem $NAME"
}

# Run FIO test for RDMA target with SPDK FIO plugin
# Args:
# - ADDR=Default IP address
# - PORT=4420
# - NS=1
# - JOBS=1
# - BLOCK_SIZE=4k
# - IO_DEPTH=16
# - SIZE=4G
# - IO_PATTERN=randread
# - TIME=5s
# - CPU_MASK=0x01
fio_spdk_rdma () {
    local ADDR=${1:-$DEFAULT_IP_ADDR}; shift
    local PORT=${1:-4420}; shift
    local NS=${1:-1}; shift
    local JOBS=${1:-1}; shift
    local BLOCK_SIZE=${1:-"4k"}; shift
    local IO_DEPTH=${1:-"16"}; shift
    local SIZE=${1:-"4G"}; shift
    local IO_PATTERN=${1:-"randread"}; shift
    local TIME=${1:-"5s"}; shift
    local CPU_MASK=${1:-"0x01"}; shift

    local FIO_PARAMS=" --name=Job --stats=1 --group_reporting=1"
    FIO_PARAMS+=" --idle-prof=percpu"
    FIO_PARAMS+=" --loops=1 --numjobs=$JOBS --thread=1"
    if [ "$TIME" != "0" ]
    then
	FIO_PARAMS+=" --time_based=1 --runtime=$TIME"
    fi
    FIO_PARAMS+=" --bs=$BLOCK_SIZE --size=$SIZE"
    FIO_PARAMS+=" --iodepth=$IO_DEPTH --readwrite=$IO_PATTERN --rwmixread=50"
    FIO_PARAMS+=" --randrepeat=1 --ioengine=spdk --direct=1 --gtod_reduce=0"
    FIO_PARAMS+=" --cpumask=$CPU_MASK"
    local FIO_FILENAME="--filename=trtype=RDMA adrfam=IPv4 traddr=$ADDR trsvcid=$PORT ns=$NS"

    echo "*** FIO: $ADDR:$PORT NS$NS, jobs $JOBS, bs $BLOCK_SIZE, io_depth $IO_DEPTH, pattern $IO_PATTERN, cpumask $CPU_MASK"
    LD_PRELOAD=$SPDK_FIO_PLUGIN $FIO $FIO_PARAMS "$FIO_FILENAME"
}

# Run FIO test for kernel device
# Args:
# - DEVICE=/dev/nvme0n1
# - JOBS=1
# - BLOCK_SIZE=4k
# - IO_DEPTH=16
# - SIZE=4G
# - IO_PATTERN=randread
# - TIME=5s
# - CPU_MASK=0x01
fio_kernel_dev () {
    local DEVICE=${1:-"/dev/nvme0n1"}; shift
    local JOBS=${1:-1}; shift
    local BLOCK_SIZE=${1:-"4k"}; shift
    local IO_DEPTH=${1:-"16"}; shift
    local SIZE=${1:-"4G"}; shift
    local IO_PATTERN=${1:-"randread"}; shift
    local TIME=${1:-"5s"}; shift
    local CPU_MASK=${1:-"0x01"}; shift

    local FIO_PARAMS=" --name=Job --stats=1 --group_reporting=1"
    FIO_PARAMS+=" --loops=1 --numjobs=$JOBS --thread=1"
    if [ "$TIME" != "0" ]
    then
	FIO_PARAMS+=" --time_based=1 --runtime=$TIME"
    fi
    FIO_PARAMS+=" --bs=$BLOCK_SIZE --size=$SIZE --iodepth=$IO_DEPTH --readwrite=$IO_PATTERN --rwmixread=50"
    FIO_PARAMS+=" --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1"
    FIO_PARAMS+=" --cpumask=$CPU_MASK"
    local FIO_FILENAME="--filename=$DEVICE"

    echo "*** FIO: $DEVICE, jobs $JOBS, bs $BLOCK_SIZE, io depth $IO_DEPTH, pattern $IO_PATTERN, cpumask $CPU_MASK"
    $FIO $FIO_PARAMS "$FIO_FILENAME"
}

test_raid_spdk_fio()
{
    nvmf_tgt_start 0x0F 128 0 64
    local bdevs=""
    for i in $(seq 0 4); do
	nvmf_tgt_add_null_bdev Null$i 8096 32768
	bdevs+=" Null$i"
    done
    nvmf_tgt_add_raid_bdev Raid0 32 6 $bdevs
    nvmf_tgt_add_subsystem cnode1 $DEFAULT_IP_ADDR 4420 Raid0
    sleep 5
    fio_spdk_rdma $DEFAULT_IP_ADDR 4420 1 1 32k 16 4G write 10s
    sleep 1
    nvmf_tgt_stop
}

test_raid_spdk_fio_conf()
{
    nvmf_tgt_start_conf "nvmf.conf" 0x0F
    sleep 5
    fio_spdk_rdma $DEFAULT_IP_ADDR 4420 1 1 32k 16 4G write 10s
    sleep 1
    nvmf_tgt_stop
}

test_raid_kernel_fio()
{
    nvmf_tgt_start 0x0F 128 0 64
    local bdevs=""
    for i in $(seq 0 4); do
	nvmf_tgt_add_null_bdev Null$i 8096 32768
	bdevs+=" Null$i"
    done
    nvmf_tgt_add_raid_bdev Raid0 32 0 $bdevs
    nvmf_tgt_add_subsystem cnode1 $DEFAULT_IP_ADDR 4420 Raid0
    sleep 5
    nvmf_connect cnode1 $DEFAULT_IP_ADDR 4420
    sleep 5
    fio_kernel_dev /dev/nvme0n1 1 96k 16 96k write 0
    sleep 5
    nvmf_disconnect cnode1
    sleep 5
    nvmf_tgt_stop
}

test_raid_bluefield_matrix ()
{
    local CONF_DIR=$PWD/conf
    local TGT_LOG=/tmp/nvmf_tgt.log

    for conf in $CONF_DIR/*.conf
    do
	for cpu_mask in 0x01 0x03 0x0F 0xFF 0xFFFF
	do
	    local DISKS=$(grep "NumDevices" $conf | grep -v "#" | awk '{ print $2 }')
	    local EC=$(grep "SkipJerasure.*True" $conf | grep -cv "#")
	    local ROTATE=$(grep "Rotate.*True" $conf | grep -cv "#")
	    local GOOD=$(grep "ErasedDevice.*-1" $conf | grep -cv "#")
	    if [ 0 -eq "$EC" ]; then EC="Calc"; else EC="Skip"; fi
	    if [ 0 -eq "$ROTATE" ]; then ROTATE="No"; else ROTATE="Yes"; fi
	    if [ 0 -eq "$GOOD" ]; then GOOD="Bad"; else GOOD="Good"; fi

	    nvmf_tgt_start_conf "$conf" $cpu_mask 1>$TGT_LOG 2>&1
	    FIO_RES=$(ssh gen-l-vrt-41071 sudo -E $PWD/fio.sh)
	    sleep 5
	    kill -15 $(pidof nvmf_tgt)

	    local CORES=$(grep "Total cores available:" $TGT_LOG | awk '{ print $NF }')
	    echo -n "| $CORES | $DISKS | $EC| $GOOD | $ROTATE | "
	    echo "$FIO_RES" | grep "write:"
	    echo -n "| | | | | | "
	    echo "$FIO_RES" | grep " lat.*):"
	    sleep 3
	done
    done
}

test_raid_bluefield_matrix
