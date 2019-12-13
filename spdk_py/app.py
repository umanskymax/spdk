import sys
from spdk_reader import spdk_reader

def help():
    print("app.py ctrlr_addr file_name")

def main():
    if 3 != len(sys.argv):
        help()
        return 1

    ctrlr_addr = sys.argv[1]
    filepath = sys.argv[2]
    print("Controller: " + ctrlr_addr)
    print("File: " + filepath)
    print("Creating SPDK context")
    spdk_ctx = spdk_reader("trtype:RDMA adrfam:IPV4 traddr:" + ctrlr_addr + " trsvcid:4420")
    file_size = spdk_ctx.get_file_size(filepath)
    print("Python: file size ", file_size)

    cpu_mem = spdk_ctx.alloc_cpu_mem(file_size)
    if cpu_mem:
        spdk_ctx.do_read(filepath, cpu_mem)
        print("Python: print 200 symbols of CPU memory")
        spdk_ctx.print_cpu_mem(cpu_mem, 200)
        spdk_ctx.free_cpu_mem(cpu_mem)
    else:
        print("Failed to allocate CPU mem")

    gpu_mem = spdk_ctx.alloc_gpu_mem(file_size)
    if gpu_mem:
        spdk_ctx.do_read(filepath, gpu_mem)
        print("Python: print 200 symbols of GPU memory")
        spdk_ctx.print_gpu_mem(gpu_mem, 200)
        spdk_ctx.free_gpu_mem(gpu_mem)
    else:
        print("Failed to allocate GPU mem")

if __name__ == "__main__":
    main()
