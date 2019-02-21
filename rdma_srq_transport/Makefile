SPDK_ROOT_DIR ?= $(abspath $(CURDIR)/..)

include $(SPDK_ROOT_DIR)/mk/spdk.common.mk

LOCAL_SYS_LIBS = -libverbs -lrdmacm
CPPFLAGS += -I$(SPDK_ROOT_DIR)/lib/nvmf

rdma_srq.so: rdma_srq.c
	$(CC) -o $@ -shared $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LOCAL_SYS_LIBS) $^
