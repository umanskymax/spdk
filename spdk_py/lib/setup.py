try:
    from distutils.core import setup, Extension
except:
    raise RuntimeError("\n\nPython distutils not found!\n")

import os
cur_dir = os.path.dirname(os.path.abspath(__file__))

# Definition of extension modules
spdk_reader_cpp = Extension('spdk_reader_cpp',
                 sources = ['spdk_reader_py.cpp'],
#                 include_dirs=['/hpc/local/oss/cuda9.2/include/', '/hpc/local/work/alexeymar/repo/spdk/install_x86_file/include'],
                 include_dirs=['/hpc/local/oss/cuda9.2/include/', cur_dir + '/../../install_x86_file/include'],
                 extra_compile_args=['-std=c++11', '-O0', '-g'],
                 library_dirs=[cur_dir],
                 libraries=['stdc++', 'spdkreader'],
                 language='c++11',)

# Compile Python module
setup (ext_modules = [spdk_reader_cpp],
       name = 'spdk_reader_cpp',
       description = 'spdk_reader_cpp Python module',
       version = '1.0')