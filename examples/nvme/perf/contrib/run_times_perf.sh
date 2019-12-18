#!/bin/bash

iters=$1
run_time=$2

export CUDA_VISIBLE_DEVICES=0
export LD_LIBRARY_PATH=/hpc/local/oss/cuda9.2/lib64/

#io_size=4096

echo "| mode | qdepth | io_size | IOPS | BW | lat | gpu_mode |iter |"

for mode in write read randwrite randread
	#for mode in read randread
do
	#    for qdepth in 1 16 32 128 256
	for qdepth in 16 32 64 128
	do
		for io_size in 4096 16384 131072
		do
			for gpu_mode in 0 1 2
			do
				for ((i=0;i<$iters;i++))
				do
					#nvmeof
					#                perf_out=$(./install_x86_dif/bin/spdk_nvme_perf -q $qdepth -o $io_size -w $mode -t $run_time -r 'trtype:RDMA adrfam:IPV4 traddr:1.1.1.3 trsvcid:4420' -c 0x4 -d 1 2>&1)
					perf_out=$(./examples/nvme/perf/perf -q $qdepth -o $io_size -w $mode -t $run_time -r 'trtype:RDMA adrfam:IPV4 traddr:1.1.21.16  trsvcid:4421' -c 0xf -a $gpu_mode 2>&1)
					#intel
					#                perf_out=$(./install_x86_19.07/bin/spdk_nvme_perf -q $qdepth -o $io_size -w $mode -t $run_time -r "trtype:PCIE  traddr:0000:81:00.0" -c 0x2000 2>&1)
					#                printf "\n$perf_out\n"
					raw_data=$(echo "$perf_out" | grep "^Total")
					#                printf "$raw_data\n"
					iops=$(echo "$raw_data" | awk '{print $3}')
					latency=$(echo "$raw_data" | awk '{print $5}')
					bw=$(echo "$raw_data" | awk '{print $4}')
					echo "| $mode | $qdepth | $io_size | $iops | $bw | $latency | $gpu_mode | $i |"

				done
			done
		done
	done
done

