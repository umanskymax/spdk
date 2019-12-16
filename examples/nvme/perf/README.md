# Compiling perf on FreeBSD

To use perf test on FreeBSD over NVMe-oF, explicitly link userspace library of HBA. For example, on a setup with Mellanox HBA,

	LIBS += -lmlx5

sudo PCI_WHITELIST="01:00.0"  ./scripts/setup.sh

sudo LD_LIBRARY_PATH=/hpc/local/oss/cuda10.2/cuda-toolkit/lib64/   ./examples/nvme/perf/perf -q 128 -o 4096 -w randwrite -t 600 -c 0x0001 -D  -r 'trtype:PCIe traddr:0000.01.00.0'
 LD_LIBRARY_PATH=/hpc/local/oss/cuda10.2/cuda-toolkit/lib64/ ./install/bin/spdk_tgt -c $PWD/examples/nvme/perf/contrib/conf/nvmf.cfg  -m 0x4



