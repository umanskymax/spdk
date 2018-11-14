#!/usr/bin/env bash
nvme connect -n nqn.2016-06.io.spdk.r-dcs75:rd0 -t rdma -a 11.141.71.100 -s 1023
sleep 3
fio --name=Job --group_reporting=1 --ioengine=libaio --direct=1 --filename=/dev/nvme0n1 --readwrite=randwrite --bs=4k --time_based=1 --runtime=10s --iodepth=16 --numjobs=16
sleep 5
nvme disconnect -n nqn.2016-06.io.spdk.r-dcs75:rd0
