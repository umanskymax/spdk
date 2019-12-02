//
// Created by alexeymar on 02-Dec-19.
//

#include <Python.h>
#include <iostream>
#include "spdk_reader.h"

PyObject* construct(PyObject* self, PyObject* args) {
	//Constructs spdk_reader instance and returns Python capsule
	//with a pointer to created object

	const char* trid;
	PyArg_ParseTuple(args, "s", &trid);

	auto ctx = new spdk_reader_ctx(trid);
	std::cout << "Created spdk_reader_ctx" << static_cast<void*>(ctx) << std::endl;

	PyObject* capsule = PyCapsule_New(static_cast<void*>(ctx), "spdk_reader_ctx", NULL);
	PyCapsule_SetPointer(capsule, static_cast<void*>(ctx));
	return Py_BuildValue("O", capsule); //"O" - python object
}

PyObject* delete_obj(PyObject* self, PyObject* args)
{
	//destroys spdk_reader instance
	//Python capsule with pointer to spdk_reader object
	PyObject* capsule;

	PyArg_ParseTuple(args, "O", &capsule); //"O" - python object

	//get pointer to spdk_reader_ctx object
	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	std::cout << "Deleting spdk_reader_ctx" << static_cast<void*>(ctx) << std::endl;
	delete ctx;

	//return nothing
	return Py_BuildValue("");
}

PyObject* get_file_size(PyObject* self, PyObject* args)
{
	//allocates pinned memory on cpu
	PyObject* capsule;
	const char* file;
	PyArg_ParseTuple(args, "Os", &capsule, &file);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));

	std::cout << "Getting size of file " << file << ", ctx " << static_cast<void*>(ctx) << std::endl;

	auto rc = ctx->get_aligned_file_size(file);

	return PyLong_FromLong(rc);
}


PyObject* alloc_cpu_mem(PyObject* self, PyObject* args)
{
	//allocates pinned memory on cpu
	PyObject* capsule;
	size_t size;
	PyArg_ParseTuple(args, "OK", &capsule, &size);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	std::cout << "Allocating CPU mem, size " << size << ", ctx " << static_cast<void*>(ctx) << std::endl;
	void* ptr = ctx->alloc_cpu_mem(size);

	std::cout << "Allocated  ptr " << ptr << std::endl;

	return PyLong_FromVoidPtr(ptr);
}

PyObject* free_cpu_mem(PyObject* self, PyObject* args)
{
	//allocates pinned memory on cpu
	PyObject* capsule;
	PyObject *mem_ptr;
	PyArg_ParseTuple(args, "OO", &capsule, &mem_ptr);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	void* ptr = PyLong_AsVoidPtr(mem_ptr);

	std::cout << "Freeing CPU mem, ptr " << ptr << ", ctx " << static_cast<void*>(ctx) << std::endl;

	ctx->free_cpu_mem(ptr);

	return Py_BuildValue("");
}

PyObject* alloc_gpu_mem(PyObject* self, PyObject* args)
{
	//allocates pinned memory on cpu
	PyObject* capsule;
	size_t size;
	PyArg_ParseTuple(args, "OK", &capsule, &size);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	std::cout << "Allocating GPU mem, size " << size << ", ctx " << static_cast<void*>(ctx) << std::endl;
	void* ptr = ctx->alloc_gpu_mem(size);

	std::cout << "Allocated  ptr " << ptr << std::endl;

	return PyLong_FromVoidPtr(ptr);
}

PyObject* free_gpu_mem(PyObject* self, PyObject* args)
{
	//allocates pinned memory on cpu
	PyObject* capsule;
	PyObject *mem_ptr;
	PyArg_ParseTuple(args, "OO", &capsule, &mem_ptr);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	void* ptr = PyLong_AsVoidPtr(mem_ptr);

	std::cout << "Freeing CPU mem, ptr " << ptr << ", ctx " << static_cast<void*>(ctx) << std::endl;

	ctx->free_gpu_mem(ptr);

	return Py_BuildValue("");
}

PyObject* print_cpu_mem(PyObject* self, PyObject* args)
{
	PyObject* capsule;
	PyObject *mem_ptr;
	size_t count;
	PyArg_ParseTuple(args, "OOK", &capsule, &mem_ptr, &count);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	void* ptr = PyLong_AsVoidPtr(mem_ptr);

	std::cout << "Printing " << count << " symbols of memory " << ptr << std::endl;
	char* ptr_c = static_cast<char*>(ptr);
	for(size_t i = 0; i < count; i++) {
		std::cout << ptr_c[i];
	}
	std::cout << std::endl;

	return Py_BuildValue("");
}

PyObject* print_gpu_mem(PyObject* self, PyObject* args)
{
	PyObject* capsule;
	PyObject *mem_ptr;
	size_t count;
	PyArg_ParseTuple(args, "OOK", &capsule, &mem_ptr, &count);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	void* ptr = PyLong_AsVoidPtr(mem_ptr);

	//copy GPU buffer to CPU to avoid running kernel and compiling with nvcc
	auto cpu_mem = static_cast<char*>(calloc(1, count + 1));
	cudaMemcpy(cpu_mem, ptr, count, cudaMemcpyDeviceToHost);
	cpu_mem[count] = '\0';

	std::cout << "Printing " << count << " symbols of memory " << ptr << std::endl;
	std::cout << cpu_mem << std::endl;

	free(cpu_mem);

	return Py_BuildValue("");
}


PyObject* spdk_do_read(PyObject* self, PyObject* args)
{
	//allocates pinned memory on cpu
	PyObject* capsule;
	PyObject *mem_ptr;
	const char* file;
	PyArg_ParseTuple(args, "OsO", &capsule, &file, &mem_ptr);

	auto ctx = static_cast<spdk_reader_ctx*>(PyCapsule_GetPointer(capsule, "spdk_reader_ctx"));
	void* ptr = PyLong_AsVoidPtr(mem_ptr);

	std::cout << "Reading from file " << file << ", ctx " << static_cast<void*>(ctx) << ", mem " << ptr << std::endl;

	auto rc = ctx->do_read(file, ptr);

	return PyLong_FromLong(rc);
}

/////////////////////////////
PyMethodDef spdk_reader_cpp_functions[] =
{
/*
*  Structures which define functions ("methods") provided by the module.
*/
	{"construct",
		construct, METH_VARARGS,
		"Create spdk_reader_ctx object"},
	{"delete_object",
		delete_obj, METH_VARARGS,
		"Delete spdk_reader_ctx object"},

	{"get_file_size",
		get_file_size, METH_VARARGS,
		"Get algined file size"},

	{"alloc_cpu_mem",
		alloc_cpu_mem, METH_VARARGS,
		"Allocate pinned memory on CPU"},
	{"free_cpu_mem",
		free_cpu_mem, METH_VARARGS,
		"Free previously allocated memory"},

	{"alloc_gpu_mem",
		alloc_gpu_mem, METH_VARARGS,
		"Allocate pinned memory on CPU"},
	{"free_gpu_mem",
		free_gpu_mem, METH_VARARGS,
		"Free previously allocated memory"},

	{"spdk_do_read",
		spdk_do_read, METH_VARARGS,
		"Read file content to the provided memory"},

	{"print_cpu_mem",
		print_cpu_mem, METH_VARARGS,
		"Print content of the first N symbols"},

	{"print_gpu_mem",
		print_gpu_mem, METH_VARARGS,
		"Print content of the first N symbols"},

	{NULL, NULL, 0, NULL}      // Last function description must be empty.
	// Otherwise, it will create seg fault while
	// importing the module.
};

struct PyModuleDef spdk_reader_cpp =
{
/*
*  Structure which defines the module.
*
*  For more info look at: https://docs.python.org/3/c-api/module.html
*
*/
	PyModuleDef_HEAD_INIT,
	"spdk_reader_cpp",               // Name of the module.

	NULL,                 // Docstring for the module - in this case empty.

	-1,                   // Used by sub-interpreters, if you do not know what
	// it is then you do not need it, keep -1 .

	spdk_reader_cpp_functions         // Structures of type `PyMethodDef` with functions
	// (or "methods") provided by the module.
};

PyMODINIT_FUNC PyInit_spdk_reader_cpp(void)
{
/*
 *   Function which initialises the Python module.
 *
 *   Note:  This function must be named "PyInit_MODULENAME",
 *          where "MODULENAME" is the name of the module.
 *
 */
	return PyModule_Create(&spdk_reader_cpp);
}