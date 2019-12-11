
ifneq ($(V),1)
Q ?= @
endif

CXX = nvcc

DIR := ${CURDIR}/
LIB_DIR := $(DIR)lib
ROOT_DIR := $(DIR)../
SPDK_PATH ?= $(ROOT_DIR)/install

SRCS = app.cu
OBJS_CU := $(SRCS:.cu=.o)

INCS = -I$(LIB_DIR) -I$(SPDK_PATH)/include
CXXFLAGS = -std=c++11  -O0 -g
LDFLAGS = -L$(LIB_DIR) -lspdkreader

SPDK_READER = $(LIB_DIR)/libspdkreader.so
APP = use_spdk_reader

.PHONY: all

%.o: %.cpp
	$(Q)echo "Compiling $<"
	$(Q)$(CXX) -c $(CXXFLAGS) $(INCS) $(LDFLAGS) $< -o $@

%.o: %.cu
	$(Q)echo "Compiling $<"
	$(Q)$(CXX) -c $(CXXFLAGS) $(INCS) $(LDFLAGS) $< -o $@

.PHONY: $(SPDK_READER) all

all: $(APP)
	$(Q)echo "Building library and application"

$(APP): $(SPDK_READER) $(OBJS_CU)
	$(Q)echo "Building app"
	$(Q)$(CXX) -o $@ $^ $(CXXFLAGS) $(INCS) $(LDFLAGS)

$(SPDK_READER):
	$(Q)echo "Building lib"
	$(Q)make -sC $(LIB_DIR) V=$(V)

clean_lib:
	$(Q)make -sC $(LIB_DIR) V=$(V) clean

clean: clean_lib
	$(Q)echo "Clean app"
	$(Q)rm -f *.o
	$(Q)rm -rf $(APP)
