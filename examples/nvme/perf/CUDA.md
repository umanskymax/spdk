
 sudo LD_LIBRARY_PATH=/hpc/local/oss/cuda10.2/cuda-toolkit/lib64/   ./examples/nvme/perf/perf -q 128 -o 4096 -w randwrite -t 600 -c 0x0001 -D  -r 'trtype:PCIe traddr:0000.01.00.0'

nvidia-smi topo -m

CUDA_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=/hpc/local/oss/cuda9.2/lib64/     ./examples/nvme/perf/perf -q 32  -o 65536   -w randread -t 5  -c 0xfffff -D  -r 'trtype:RDMA adrfam:IPv4   traddr:1.1.21.16 trsvcid:4320' -r 'trtype:RDMA adrfam:IPv4   traddr:1.1.22.16 trsvcid:4321'  -a 1

sudo ./install/bin/spdk_tgt -m 0xc00c00 -c ../spdk_dgx/examples/nvme/perf/contrib/conf/x86.conf


