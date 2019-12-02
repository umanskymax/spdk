
from spdk_reader import spdk_reader

def main():
    print("Creating SPDK context")
    spdk_ctx = spdk_reader("trtype:RDMA adrfam:IPV4 traddr:1.1.10.1 trsvcid:4420")
    filepath = "/nvme_mount/rdma.c"
    file_size = spdk_ctx.get_file_size(filepath)
    print("Python: file size ", file_size)

    cpu_mem = spdk_ctx.alloc_cpu_mem(file_size)
    spdk_ctx.do_read(filepath, cpu_mem)
    print("Python: print 200 symbols of CPU memory")
    spdk_ctx.print_cpu_mem(cpu_mem, 200)
    spdk_ctx.free_cpu_mem(cpu_mem)

    gpu_mem = spdk_ctx.alloc_gpu_mem(file_size)
    spdk_ctx.do_read(filepath, gpu_mem)
    print("Python: print 200 symbols of GPU memory")
    spdk_ctx.print_gpu_mem(gpu_mem, 200)
    spdk_ctx.free_gpu_mem(gpu_mem)

if __name__ == "__main__":
    main()