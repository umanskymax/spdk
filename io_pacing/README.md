# IO Pacing Prototype

This folder contains files related to IO Pacing prototype in SPDK: configuration files, test scripts, results, etc.

## Test setup preparation

### Target

Clone and build SPDK.

~~~{.sh}
git clone https://github.com/Mellanox/spdk.git
cd spdk
git checkout io_pacing
git submodule update --init
./configure --with-rdma --prefix=$PWD/install-$HOSTNAME --disable-unit-tests
make
make install
~~~

### Initiator

Test scripts use fio with SPDK plugin as initiator. Fio and SPDK should be built on every client host separately to allow differences in environment. Below are steps to setup initiator hosts. Note, that clone should be done just once (if sources are on shared storage), while configure, make and install steps should be done on every initiator host.

#### Fio

~~~{.sh}
git clone https://github.com/axboe/fio
cd fio
git checkout fio-3.15
./configure --prefix=$PWD/install-$HOSTNAME
make
make install
cd ..
~~~

#### SPDK

SPDK for initiator host should be built right after fio build for the same host.

~~~{.sh}
git clone https://github.com/Mellanox/spdk.git
cd spdk
git checkout io_pacing
git submodule update --init
./configure --with-rdma --prefix=$PWD/install-$HOSTNAME --disable-unit-tests --with-fio=$PWD/../fio
make
make install
cp ./examples/nvme/fio_plugin/fio_plugin install-$HOSTNAME/lib
~~~

## Running tests

Test script is `test.sh`. You will also need job files for fio and target configration files. Job files can be found in `io_pacing/jobs` folder, target configs in `io_pacing/configs`. You may need to update some jobs and config parameters according to your setup. Also check test script for configurable parameters.

1. Start target

~~~{.sh}
sudo ./scripts/setup.sh
sudo hugeadm --pool-pages-min DEFAULT:4G
sudo neohost &
sudo ./install-$HOSTNAME/bin/spdk_tgt -c configs/nvmf_nvme.conf -m 0xFFFF
~~~

2. Run test script on one of the initiator hosts

~~~
$ ./test.sh
..........-..................!
Test parameters
Time        : 30
Read/write  : randread
Queue depth : 32
IO size     : 128k

Results
Host                           | kIOPS      | BW,Gb/s    | AVG_LAT,us      | Wire BW,Gb/s
-------------------------------|------------|------------|-----------------|----------------
r-dcs79                        | 87.9       | 92.1       | 363.1           |
spdk03.swx.labs.mlnx           | 87.7       | 91.9       | 364.4           |
-------------------------------|------------|------------|-----------------|----------------
Total                          | 175.6      | 184.1      |                 | 193.4409
~~~

## Results

### Test 1

**IO pacing**: `none`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_null_1.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

~~~
QD         | BW
8          | 184.6
16         | 184.6
32         | 184.6
64         | 179.0
128        | 178.9
256        | 178.7
~~~

### Test 2

**IO pacing**: `none`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_null_16.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

~~~
QD         | BW
8          | 184.6
16         | 184.6
32         | 184.6
64         | 179.0
128        | 178.9
256        | 178.7
~~~

### Test 3

**IO pacing**: `none`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_nvme.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

~~~
QD         | BW
8          | 92.6
16         | 162.2
32         | 182.4
64         | 137.4
128        | 117.5
256        | 114.7
~~~

Closer look at 40-48 queue depth range.

~~~
QD         | BW         | WIRE BW
40         | 180.6      | 194.1261
41         | 182.4      | 195.4818
42         | 181.7      | 193.9956
43         | 179.8      | 193.2307
44         | 179.4      | 190.9635
48         | 169.8      | 189.9152
~~~

### Test 4

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_null_16_num_buffers.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

~~~
QD         | BW
8          | 169.9
16         | 180.1
32         | 180.9
64         | 183.0
128        | 183.0
256        | 183.3
~~~

### Test 5

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_nvme_num_buffers.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

Buffer cache size 6.

~~~
QD         | BW         | WIRE BW
8          | 96.1       | 101.7948
16         | 167.9      | 179.8046
32         | 182.3      | 193.8036
64         | 182.7      | 194.3911
128        | 182.8      | 195.7273
256        | 183.1      | 194.1423
~~~

~~~
