//
// Created by alexeymar on 29-Nov-19.
//

#include "spdk_reader.h"
#include <iostream>

const size_t chars_to_print = 200;

__global__
void print_gpu_mem(char *c, int n) {
	for (int i = 0; i < n; i++) {
		printf("%c", c[i]);
	}
	printf("\n");
}

int main(int argc, char *argv[]) {
	if (argc < 3) {
		std::cerr << "Specify controller address and file path" << std::endl;
		return 1;
	}
	std::cout << "Working with controller " << argv[1] << std::endl;
	std::cout << "File " << argv[2] << std::endl;
	try {
		spdk_reader_ctx reader{argv[1]};
		auto alloc_size = reader.get_aligned_file_size(argv[2]);

		std::cout << "Read tp CPU" << std::endl;
		auto cpu_buffer = spdk_reader_ctx::get_cpu_mem(alloc_size);
		int rc = reader.do_read(argv[2], cpu_buffer.get());
		if (rc) {
			std::cerr << "Read completed with error " << rc << std::endl;
			return 1;
		}
		std::cout << "Print first " << chars_to_print << "  characters" << std::endl;
		for (uint32_t i = 0; i < chars_to_print && i < alloc_size; i++) {
			std::cout << static_cast<char *>(cpu_buffer.get())[i];
		}
		std::cout << std::endl;

		std::cout << "Read to GPU memory" << std::endl;
		auto gpu_buffer = spdk_reader_ctx::get_gpu_mem(alloc_size);
		rc = reader.do_read(argv[2], gpu_buffer.get());
		if (rc) {
			std::cerr << "Read completed with error " << rc << std::endl;
			return 1;
		}
		std::cout << "Print first " << chars_to_print << "  characters" << std::endl;
		print_gpu_mem << < 1, 1 >> > (static_cast<char *>(gpu_buffer.get()),
			std::min(chars_to_print, alloc_size));

	} catch (std::runtime_error &e) {
		std::cerr << "Exception caught: " << e.what() << std::endl;
	}
}