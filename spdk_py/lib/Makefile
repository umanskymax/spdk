
ifneq ($(V),1)
Q ?= @
endif

CXX = g++
CPYTHON3 = python3

DIR := ${CURDIR}/
ROOT_DIR := $(DIR)../../

SO_SRCS = spdk_reader.cpp
SO_OBJS := $(SO_SRCS:.cpp=.o)
SO_NAME = libspdkreader.so

PY_SRC = spdk_reader.cpp spdk_reader_2py.cpp
PY_COMPILE_SCRIPT = compile_spdk_reader.py
PY_MODULE = spdk_reader_py

HEADERS = spdk_reader.h

INCS = -I$(ROOT_DIR)install_x86_file/include
CXXFLAGS = -std=c++0x -fPIC -Werror -Wall -O0 -g
LDFLAGS = -L$(ROOT_DIR)install_x86_file/lib/
LDFLAGS += -L$(ROOT_DIR)dpdk/build/lib
LDFLAGS += -L/usr/lib64
LD_STATIC = -lspdk_nvme -lspdk_env_dpdk -lspdk_util -lspdk_log -lspdk_sock
LD_STATIC += -lrte_eal -lrte_mempool -lrte_kvargs -lrte_ring -lrte_bus_pci -lrte_pci
LD_DYNAMIC = -lpthread -libverbs -lrdmacm -luuid -lnuma -lcudart
LDFLAGS += -Wl,-Bstatic $(LD_STATIC)
LDFLAGS += -Wl,-Bdynamic $(LD_DYNAMIC)

%.o: %.cpp $(HEADERS)
	$(Q)echo "Compiling $<"
	$(Q)$(CXX) -c $(CXXFLAGS) $(INCS) $(LDFLAGS) $< -o $@

$(SO_NAME): $(SO_OBJS)
	$(Q)echo "Building $(SO_NAME)"
	$(Q)$(CXX) $(CXXFLAGS) $(INCS) -shared -Wl,-soname,$(SO_NAME) $(SO_OBJS) $(LDFLAGS) -o $(SO_NAME)

#$(PY_MODULE): $(PY_SRC) $(PY_COMPILE_SCRIPT) $(HEADERS)
#	$(CPYTHON3) $(MODULE_COMPILE_SCRIPT) build_ext --inplace

all: $(SO_NAME)
#all: $(SO_NAME) $(PY_MODULE)

clean:
	$(Q)echo "Clean lib"
	$(Q)rm -fR build
	$(Q)rm -f *.so
	$(Q)rm -f *.o
	$(Q)rm -fR __pycache__
