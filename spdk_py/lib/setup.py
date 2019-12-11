try:
    from distutils.core import setup, Extension
except:
    raise RuntimeError("\n\nPython distutils not found!\n")

import os
cur_dir = os.path.dirname(os.path.abspath(__file__))
cuda_path = os.environ.get('CUDA_PATH')
spdk_path = os.environ.get('SPDK_PATH')

# Definition of extension modules
spdk_reader_cpp = Extension('spdk_reader_cpp',
                 sources = ['spdk_reader_py.cpp'],
                 include_dirs=[ cuda_path + '/include', spdk_path + '/include'],
                 extra_compile_args=['-std=c++11', '-O0', '-g'],
                 library_dirs=[cur_dir],
                 libraries=['stdc++', 'spdkreader'],
                 language='c++11',)

# Compile Python module
setup (ext_modules = [spdk_reader_cpp],
       name = 'spdk_reader_cpp',
       description = 'spdk_reader_cpp Python module',
       version = '1.0')
