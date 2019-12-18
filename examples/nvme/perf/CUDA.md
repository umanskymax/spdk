
 sudo LD_LIBRARY_PATH=/hpc/local/oss/cuda10.2/cuda-toolkit/lib64/   ./examples/nvme/perf/perf -q 128 -o 4096 -w randwrite -t 600 -c 0x0001 -D  -r 'trtype:PCIe traddr:0000.01.00.0'

nvidia-smi topo -m
