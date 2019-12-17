try:
    import spdk_reader_cpp
except:
    strErr = "\n\n`spdk_reader_cpp` module not found, "
    raise RuntimeError(strErr)

class spdk_reader():
    def __init__(self, trid):
        self.spdk_capsule = spdk_reader_cpp.construct(trid)

    def __delete__(self):
        spdk_reader_cpp.delete_obj(self.spdk_capsule)

    def get_file_size(self, filepath):
        size = spdk_reader_cpp.get_file_size(self.spdk_capsule, filepath)
        return size

    def reg_mem(self, mem_ptr, size):
        rc = spdk_reader_cpp.reg_mem(self.spdk_capsule, mem_ptr, size)
        return rc

    def alloc_cpu_mem(self, size):
        mem_ptr = spdk_reader_cpp.alloc_cpu_mem(self.spdk_capsule, size)
        return mem_ptr

    def free_cpu_mem(self, mem_ptr):
        spdk_reader_cpp.free_cpu_mem(self.spdk_capsule, mem_ptr)

    def alloc_gpu_mem(self, size):
        mem_ptr = spdk_reader_cpp.alloc_gpu_mem(self.spdk_capsule, size)
        return mem_ptr

    def free_gpu_mem(self, mem_ptr):
        spdk_reader_cpp.free_gpu_mem(self.spdk_capsule, mem_ptr)

    def do_read(self, filepath, mem_ptr):
        rc = spdk_reader_cpp.spdk_do_read(self.spdk_capsule,  filepath, mem_ptr)
        return rc

    def print_cpu_mem(self, mem_ptr, count):
        rc = spdk_reader_cpp.print_cpu_mem(self.spdk_capsule,  mem_ptr, count)
        return rc

    def print_gpu_mem(self, mem_ptr, count):
        rc = spdk_reader_cpp.print_gpu_mem(self.spdk_capsule,  mem_ptr, count)
        return rc
