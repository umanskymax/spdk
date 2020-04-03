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

## IO pacing methods

### Number of buffers limitation in SPDK

SPDK has a configuration parameter `NumSharedBuffers` that defines
number of data buffers (and size of buffer) to allocate for NVMf
transport. Buffers form a pool and are shared among all threads.

At start each thread allocates a number of buffers from common pool to
thread local cache. Size of the cache is controlled by `BufCacheSize`
configuration parameter.

When buffer is needed SPDK thread tries to allocate buffer from its
local cache. If there are no buffers it goes to common pool. If there
is nothing in common pool, IO request goes to pending buffer queue and
is retried when buffer is released by the same thread.

When buffer IO request is completed and buffer is not needed anymore,
SPDK tries to return it to local cache first. If local cache is full,
i.e. has length `BufCacheSize`, buffer is returned to common pool.

Data buffer pool is built on top of DPDK mempool API. It has its own
caching mechanism but we disable it in this PoC.

## Results

| Test #              | IO pacing        | Disks   | Description                                  |
|---------------------|------------------|---------|----------------------------------------------|
| [Test 1](#test-1)   | none             | 1 Null  | Basic test                                   |
| [Test 2](#test-2)   | none             | 15 Null | Basic test                                   |
| [Test 3](#test-3)   | none             | 15 NVMe | Basic test                                   |
| [Test 4](#test-4)   | NumSharedBuffers | 15 Null | Basic test                                   |
| [Test 5](#test-5)   | NumSharedBuffers | 15 NVMe | Basic test                                   |
| [Test 6](#test-6)   | NumSharedBuffers | 15 NVMe | Stability test: multiple same test runs      |
| [Test 7](#test-7)   | NumSharedBuffers | 15 NVMe | Different number of target cores             |
| [Test 8](#test-8)   | NumSharedBuffers | 15 NVMe | Different buffer cache size                  |
| [Test 9](#test-9)   | NumSharedBuffers | 15 NVMe | Different number of buffers, 16 target cores |
| [Test 10](#test-10) | NumSharedBuffers | 15 NVMe | Different number of buffers, 4 target cores  |

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

### Test 6

Stability tests. Check variation of results between multiple runs for
different queue depths.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_nvme_num_buffers.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

~~~
QD         | BW         | WIRE BW
32         | 182.1      | 193.8186
32         | 182.4      | 193.7025
32         | 182.3      | 193.8234
32         | 182.3      | 194.3455
32         | 182.0      | 194.3137
32         | 180.5      | 193.897
32         | 180.4      | 193.6792
32         | 182.3      | 193.8799
32         | 182.4      | 193.7207
32         | 182.3      | 193.6092
~~~

~~~
QD         | BW         | WIRE BW
64         | 182.7      | 194.0737
64         | 182.7      | 195.7083
64         | 182.8      | 194.068
64         | 180.7      | 195.0194
64         | 182.7      | 194.574
64         | 182.6      | 194.7142
64         | 182.8      | 194.7191
64         | 182.7      | 194.5625
64         | 182.6      | 194.6243
64         | 182.7      | 194.9261
~~~

~~~
QD         | BW         | WIRE BW
128        | 181.0      | 194.8205
128        | 183.0      | 194.2791
128        | 182.9      | 194.1231
128        | 178.9      | 194.5432
128        | 183.0      | 195.5661
128        | 182.9      | 195.8418
128        | 182.8      | 194.5217
128        | 183.0      | 194.6062
128        | 182.9      | 195.9649
128        | 182.9      | 194.0792
~~~

~~~
QD         | BW         | WIRE BW
256        | 183.2      | 195.4783
256        | 179.4      | 195.3888
256        | 172.4      | 98.1666
256        | 178.6      | 194.6085
256        | 178.2      | 194.3612
256        | 173.2      | 194.778
256        | 183.1      | 194.0347
256        | 183.1      | 195.608
256        | 181.2      | 194.5141
256        | 183.1      | 194.0458
~~~

### Test 7

Check performance effect of number of target cores.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_nvme_num_buffers.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

Target cores 16 (0xFFFF), buffer cache size 6.

~~~
QD         | BW         | WIRE BW
8          | 92.8       | 99.0422
16         | 166.9      | 177.6865
32         | 182.5      | 194.0054
64         | 182.6      | 194.3754
128        | 182.9      | 194.429
256        | 183.1      | 194.3922
~~~

Target cores 8 (0xFF), buffer cache size 12.

~~~
QD         | BW         | WIRE BW
8          | 95.8       | 101.819
16         | 171.7      | 182.558
32         | 184.8      | 196.3163
64         | 184.8      | 196.3329
128        | 184.8      | 196.3341
256        | 184.8      | 196.2277
~~~

Target cores 4 (0xF), buffer cache size 24.

~~~
QD         | BW         | WIRE BW
8          | 95.6       | 101.5697
16         | 169.0      | 179.7792
32         | 184.8      | 196.3151
64         | 184.8      | 196.3326
128        | 184.8      | 196.333
256        | 184.8      | 196.3326
~~~

Target cores 2 (0x3), buffer cache size 48.

~~~
QD         | BW         | WIRE BW
8          | 91.6       | 97.212
16         | 157.7      | 167.6598
32         | 184.2      | 195.624
64         | 184.2      | 196.1523
128        | 184.6      | 196.3215
256        | 184.6      | 196.2801
~~~

Target cores 1 (0x1), buffer cache size 96.

~~~
QD         | BW         | WIRE BW
8          | 94.8       | 100.4075
16         | 145.6      | 155.4012
32         | 177.9      | 189.4804
64         | 176.3      | 186.8191
128        | 172.2      | 183.846
256        | 156.1      | 165.5522
~~~

### Test 8

Check performance effects of buffer cache size.

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

Buffer cache size 0.

~~~
QD         | BW         | WIRE BW
8          | 94.5       | 100.5522
16         | 166.9      | 178.6776
32         | 182.1      | 193.7545
64         | 182.7      | 194.8118
~~~

Test hangs with queue depth 128 and more. One of initiators can not
connect all the QPs. Probably, without cache it is possible that some
threads will never get buffers and will not be able to handle even
admin commands.

Buffer cache size 1.

~~~
QD         | BW         | WIRE BW
8          | 91.9       | 98.8753
16         | 163.2      | 176.9629
32         | 182.1      | 194.0412
64         | 182.6      | 194.3561
128        | 133.0      | 139.5647
256        | 134.5      | 137.4158
~~~

With very small buffer cache it works but we see performance
degradation with deep queues. Likely because of the same effect, some
threads consume all the buffers and others don't get enough to perform
well.

### Test 9

Check performance effect of number of data buffers. All buffers are
shared equally between all threads at start with `BufCacheSize`
parameter.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_nvme_num_buffers.conf -m 0xFFFF`

**Initiator**: `fio+SPDK`

Number of buffers 128, buffer cache size 32.

~~~
QD         | BW         | WIRE BW
8          | 92.8       | 99.8292
16         | 164.0      | 177.0472
32         | 180.4      | 193.8725
64         | 133.7      | 184.1221
128        | 131.1      | 190.8772
256        | 127.3      | 177.241
~~~

Number of buffers 96, buffer cache size 6.

~~~
QD         | BW         | WIRE BW
8          | 92.8       | 99.0422
16         | 166.9      | 177.6865
32         | 182.5      | 194.0054
64         | 182.6      | 194.3754
128        | 182.9      | 194.429
256        | 183.1      | 194.3922
~~~

Number of buffers 64, buffer cache size 4.

~~~
QD         | BW         | WIRE BW
8          | 93.2       | 100.2594
16         | 164.0      | 177.9693
32         | 180.2      | 193.8549
64         | 182.3      | 193.7867
128        | 182.8      | 193.4866
256        | 183.2      | 195.4177
~~~

Number of buffers 48, buffer cache size 3.

~~~
QD         | BW         | WIRE BW
8          | 93.0       | 99.8556
16         | 164.1      | 177.2571
32         | 178.7      | 190.3871
64         | 178.8      | 191.1094
128        | 179.7      | 190.2044
256        | 179.9      | 191.586
~~~

Number of buffers 32, buffer cache size 2.

~~~
QD         | BW         | WIRE BW
8          | 93.8       | 99.6489
16         | 142.1      | 151.7735
32         | 141.8      | 151.3303
64         | 136.7      | 148.1263
128        | 143.7      | 152.5965
256        | 143.9      | 153.4391
~~~

Number of buffers 16, buffer cache size 1.

~~~
rdma.c:2419:spdk_nvmf_rdma_create: *ERROR*: The number of shared data buffers (16) is less thanthe minimum number required to guarantee that forward progress can be made (32)
~~~

### Test 10

Check performance effect of number of data buffers with 4 cores. All
buffers are shared equally between all threads at start with
`BufCacheSize` parameter.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_nvme_num_buffers.conf -m 0xF`

**Initiator**: `fio+SPDK`

Number of buffers 128, buffer cache size 32.

~~~
QD         | BW         | WIRE BW
8          | 94.6       | 100.5571
16         | 169.0      | 180.0731
32         | 184.8      | 196.3248
64         | 123.1      | 130.9857
128        | 124.9      | 129.8354
256        | 123.2      | 129.6055
~~~

Number of buffers 96, buffer cache size 24.

~~~
QD         | BW         | WIRE BW
8          | 95.6       | 101.5987
16         | 168.9      | 179.8312
32         | 184.8      | 196.3177
64         | 184.8      | 196.3324
128        | 184.8      | 196.3333
256        | 184.8      | 196.3248
~~~

Number of buffers 64, buffer cache size 16.

~~~
QD         | BW         | WIRE BW
8          | 95.9       | 101.7749
16         | 168.8      | 180.3303
32         | 184.8      | 196.3154
64         | 184.8      | 196.3052
128        | 184.8      | 196.3052
256        | 184.8      | 196.3063
~~~

Number of buffers 48, buffer cache size 12.

~~~
QD         | BW         | WIRE BW
8          | 95.9       | 102.0887
16         | 168.9      | 178.9896
32         | 183.9      | 195.3663
64         | 183.9      | 195.6575
128        | 183.3      | 195.2519
256        | 183.7      | 195.0659
~~~

Number of buffers 32, buffer cache size 8.

~~~
QD         | BW         | WIRE BW
8          | 96.5       | 102.4352
16         | 155.2      | 165.1455
32         | 155.4      | 164.9088
64         | 154.2      | 163.772
128        | 154.7      | 164.9357
256        | 152.6      | 163.5733
~~~

Number of buffers 16, buffer cache size 4.

~~~
rdma.c:2419:spdk_nvmf_rdma_create: *ERROR*: The number of shared data buffers (16) is less thanthe minimum number required to guarantee that forward progress can be made (32)
~~~
