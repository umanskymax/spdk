#!/bin/bash

sudo yum install -y libuuid-devel
sudo yum install -y libaio-devel
module load dev/cuda9.2
sudo cp /hpc/local/oss/cuda9.2/lib64/libcudart.so.9.2 /lib64/
sudo cp /hpc/local/oss/cuda9.2/lib64/libcudart.so.9.2.88 /lib64/

sudo yum install -y epel-release
sudo yum install -y python34
sudo ln -s /bin/python3.4 /bin/python3
sudo rpm -i /hpc/local/work/alexeymar/python-srpm-macros-3-32.el7.noarch.rpm
sudo rpm -i /hpc/local/work/alexeymar/python-rpm-macros-3-32.el7.noarch.rpm
sudo yum install -y python34-devel.x86_64

modinfo nv_peer_mem
#if no nv_peer_mem found
sudo rpm -i /hpc/local/work/alexeymar/nvidia_peer_memory-1.0-8.x86_64.rpm 

module load dev/cuda9.2

#sudo modprobe nvme-rdma
#sudo nvme connect -t rdma -a 1.1.10.1 -s 4420 -n nqn.2016-06.io.spdk:cnode1
#sudo mkfs.ext3 /dev/nvme0n1
#sudo mkdir /nvme_mount
#sudo mount /dev/nvme0n1 /nvme_mount/
#sudo chown -R alexeymar /nvme_mount/
#cp lib/nvmf/rdma.c /nvme_mount/


