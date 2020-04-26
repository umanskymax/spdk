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

| Test #              | IO pacing        | Disks                   | Description                                  |
|---------------------|------------------|-------------------------|----------------------------------------------|
| [Test 1](#test-1)   | none             | 1 Null                  | Basic test                                   |
| [Test 2](#test-2)   | none             | 16 Null                 | Basic test                                   |
| [Test 3](#test-3)   | none             | 16 NVMe                 | Basic test                                   |
| [Test 4](#test-4)   | NumSharedBuffers | 16 Null                 | Basic test                                   |
| [Test 5](#test-5)   | NumSharedBuffers | 16 NVMe                 | Basic test                                   |
| [Test 6](#test-6)   | NumSharedBuffers | 16 NVMe                 | Stability test: multiple same test runs      |
| [Test 7](#test-7)   | NumSharedBuffers | 16 NVMe                 | Different number of target cores             |
| [Test 8](#test-8)   | NumSharedBuffers | 16 NVMe                 | Different buffer cache size                  |
| [Test 9](#test-9)   | NumSharedBuffers | 16 NVMe                 | Different number of buffers, 16 target cores |
| [Test 10](#test-10) | NumSharedBuffers | 16 NVMe                 | Different number of buffers, 4 target cores  |
| [Test 11](#test-11) | NumSharedBuffers | 16 NVMe, split 3, delay | No limit of IO depth for delay devices       |
| [Test 12](#test-12) | NumSharedBuffers | 16 NVMe, split 3, delay | Control IO depthfor delay devices            |
| [Test 13](#test-13) | N/A              | 16 NVMe, split 3, delay | Test disk latencies                          |
| [Test 14](#test-14) | Rate based       | 16 NVMe                 | Basic test                                   |

### Test 1

**IO pacing**: `none`

**Configuration**: `config_null_1`

**Initiator**: `fio+SPDK`

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 184.0      | 196.3107   | 90.5            | 1.5
16         | 184.6      | 196.3327   | 181.1           | .8
32         | 184.0      | 196.3318   | 364.0           | 2.4
64         | 177.3      | 188.6632   | 756.1           | .7
128        | 177.4      | 188.7209   | 1511.9          | .6
256        | 177.6      | 188.7393   | 3021.1          | .5
~~~

### Test 2

**IO pacing**: `none`

**Configuration**: `config_null_16`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|-------|----------|-------------|-----------|-------------|
| 16  | 184.5 | 196.1237 | 181.3       | .5        | 99.1        |
| 32  | 184.8 | 196.333  | 362.5       | .1        | 91.0        |
| 36  | 184.8 | 196.3326 | 407.8       | .1        | 83.0        |
| 40  | 184.8 | 196.3322 | 453.2       | 0         | 88.3        |
| 44  | 184.8 | 196.3332 | 498.6       | .1        | 83.7        |
| 48  | 184.8 | 196.3331 | 543.9       | 0         | 90.4        |
| 64  | 184.8 | 196.3324 | 725.4       | 0         | 83.6        |
| 128 | 184.8 | 196.3335 | 1451.4      | .1        | 70.5        |
| 256 | 184.8 | 196.3331 | 2903.6      | .1        | 45.1        |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 184.8      | 196.331    | 179.8           | .2
| 4          | 184.8      | 196.3365   | 361.2           | .2
| 8          | 182.4      | 193.8894   | 733.8           | .2
| 16         | 179.1      | 190.5807   | 1496.6          | .2
| 32         | 181.5      | 192.7129   | 2956.1          | .3
~~~

### Test 3

**IO pacing**: `none`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------|-------|----------|-------------|-----------|-------------|----------------------|
| 32   | 184.8 | 196.3297 | 362.6       | .1        | 99.1        | 59 (7.3)             |
| 36   | 184.7 | 196.3331 | 408.0       | .3        | 98.4        | 69 (8.6)             |
| 40   | 184.7 | 196.3318 | 453.4       | .2        | 92.5        | 77 (9.6)             |
| 44   | 184.1 | 195.3937 | 500.7       | .7        | 85.7        | 85 (10.6)            |
| 48   | 173.5 | 184.9336 | 579.6       | 1.7       | 78.3        | 98 (12.2)            |
| 64   | 171.0 | 181.6606 | 784.2       | 3.0       | 71.6        | 122 (15.2)           |
| 128  | 166.4 | 180.7608 | 1612.4      | 3.2       | 76.4        | 253 (31.6)           |
| 256  | 160.3 | 176.5963 | 3347.9      | 2.9       | 73.7        | 369 (46.1)           |
| 1024 | 143.2 | 157.6718 | 13263.5     | 7.1       | 68.9        | 796 (99.5)           |
| 2048 | 142.4 | 156.8726 | 17547.5     | 8.3       | 67.8        | 743 (92.8)           |


**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 164.3      | 175.335    | 202.4           | .2
| 4          | 184.8      | 196.3352   | 361.3           | .2
| 8          | 107.4      | 113.4529   | 1247.9          | .2
| 16         | 104.3      | 110.5348   | 2571.3          | .3
| 32         | 104.5      | 110.9826   | 5133.0          | .2
~~~

### Test 4

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 config_null_16`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|-------|----------|-------------|-----------|-------------|
| 16  | 184.6 | 196.1118 | 181.3       | .3        | 99.1        |
| 32  | 184.8 | 196.3311 | 362.6       | .3        | 97.0        |
| 36  | 184.8 | 196.3328 | 407.9       | .2        | 94.0        |
| 40  | 184.8 | 196.3331 | 453.2       | 0         | 95.5        |
| 44  | 184.8 | 196.3322 | 498.6       | .1        | 95.3        |
| 48  | 184.8 | 196.3332 | 543.9       | 0         | 95.0        |
| 64  | 184.7 | 196.3331 | 725.8       | .3        | 95.0        |
| 128 | 184.8 | 196.3329 | 1451.6      | .1        | 92.3        |
| 256 | 184.8 | 196.3301 | 2903.8      | .1        | 96.1        |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 184.8      | 196.3326   | 179.8           | .2
| 4          | 184.8      | 196.3337   | 361.3           | .2
| 8          | 184.8      | 196.3349   | 724.2           | .2
| 16         | 184.8      | 196.3341   | 1450.1          | .2
| 32         | 184.8      | 196.3341   | 2901.9          | .2
~~~

### Test 5

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------|-------|----------|-------------|-----------|-------------|----------------------|
| 32   | 184.8 | 196.2989 | 362.5       | .1        | 98.9        | 60 (7.5)             |
| 64   | 184.6 | 196.3293 | 726.5       | .4        | 89.5        | 90 (11.2)            |
| 128  | 184.6 | 196.332  | 1453.3      | .3        | 91.1        | 94 (11.7)            |
| 256  | 184.7 | 196.3342 | 2906.0      | .2        | 90.6        | 95 (11.8)            |
| 1024 | 184.4 | 196.312  | 11646.2     | .5        | 88.2        | 96 (12.0)            |
| 2048 | 184.1 | 196.2966 | 23019.9     | 1.4       | 87.9        | 96 (12.0)            |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 165.4      | 175.6145   | 201.1           | .2
| 4          | 184.8      | 196.3025   | 361.3           | .2
| 8          | 184.8      | 196.2741   | 724.5           | .2
| 16         | 184.8      | 196.3269   | 1450.3          | .2
| 32         | 184.8      | 196.3037   | 2903.2          | .3
~~~

### Test 6

Stability tests. Check variation of results between multiple runs for
different queue depths.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme`

**Initiator**: `fio+SPDK`

| QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|------|-------|----------|-------------|-----------|-------------|
| 32   | 184.7 | 196.3127 | 362.7       | .4        | 99.4        |
| 32   | 184.8 | 196.3116 | 362.5       | .1        | 99.1        |
| 32   | 184.8 | 196.3224 | 362.5       | 0         | 99.4        |
| 32   | 184.8 | 196.3193 | 362.6       | .2        | 99.4        |
| 32   | 184.8 | 196.3207 | 362.6       | .2        | 99.2        |
| 32   | 184.8 | 196.3202 | 362.6       | .3        | 99.3        |
| 32   | 184.8 | 196.3186 | 362.6       | .2        | 99.4        |
| 32   | 184.7 | 196.319  | 362.7       | .3        | 99.2        |
| 32   | 184.8 | 196.31   | 362.5       | .1        | 99.3        |
| 32   | 184.8 | 196.3194 | 362.6       | .2        | 99.4        |
| 256  | 184.7 | 196.3318 | 2905.8      | .3        | 90.8        |
| 256  | 184.6 | 196.331  | 2906.4      | .4        | 89.4        |
| 256  | 184.6 | 196.3302 | 2906.6      | .3        | 89.3        |
| 256  | 184.6 | 196.328  | 2907.3      | .4        | 89.2        |
| 256  | 184.6 | 196.3333 | 2906.3      | .3        | 91.0        |
| 256  | 184.6 | 196.3318 | 2906.7      | .3        | 89.8        |
| 256  | 184.6 | 196.3309 | 2906.9      | .3        | 90.3        |
| 256  | 184.7 | 196.3312 | 2906.0      | .2        | 90.6        |
| 256  | 184.7 | 196.3424 | 2906.0      | .3        | 89.5        |
| 256  | 184.7 | 196.3308 | 2906.1      | .3        | 90.0        |
| 1024 | 184.5 | 196.323  | 11639.8     | .4        | 88.7        |
| 1024 | 184.5 | 196.3303 | 11638.0     | .5        | 87.8        |
| 1024 | 184.5 | 196.2538 | 11639.6     | .5        | 88.2        |
| 1024 | 184.5 | 196.3264 | 11639.5     | .5        | 88.0        |
| 1024 | 184.4 | 196.3148 | 11642.0     | .5        | 88.5        |
| 1024 | 184.5 | 196.3287 | 11637.4     | .5        | 87.8        |
| 1024 | 184.5 | 196.3236 | 11638.4     | .5        | 88.4        |
| 1024 | 184.4 | 196.3291 | 11640.6     | .4        | 89.3        |
| 1024 | 184.5 | 196.3237 | 11639.2     | .4        | 88.4        |
| 1024 | 184.4 | 196.3293 | 11640.4     | .5        | 87.8        |
| 2048 | 184.1 | 196.3099 | 23322.6     | 1.2       | 87.0        |
| 2048 | 184.3 | 196.3222 | 22865.1     | 1.1       | 88.6        |
| 2048 | 184.2 | 196.3225 | 21973.9     | 1.1       | 88.2        |
| 2048 | 184.2 | 196.3202 | 22456.9     | 1.3       | 87.9        |
| 2048 | 184.2 | 196.3208 | 22160.7     | 1.0       | 87.8        |
| 2048 | 184.2 | 196.3207 | 22533.7     | .9        | 87.6        |
| 2048 | 184.2 | 196.3194 | 22282.5     | 1.2       | 88.5        |
| 2048 | 184.2 | 196.3175 | 22542.9     | 1.3       | 88.5        |
| 2048 | 184.2 | 196.3023 | 23316.1     | 1.2       | 88.4        |
| 2048 | 184.2 | 196.3171 | 22966.5     | 1.1       | 88.0        |

### Test 7

Check performance effect of number of target cores.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$((num_buffers/num_cores)) config_nvme`

**Initiator**: `fio+SPDK`

Target cores 16 (0xFFFF). Buffer cache size 6

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 97.3       | 106.0621   | 171.7           | 5.9
16         | 162.1      | 176.1584   | 206.3           | 10.2
32         | 177.0      | 192.845    | 378.5           | 10.1
64         | 181.2      | 193.9438   | 740.0           | 5.9
128        | 181.8      | 195.2145   | 1475.2          | 4.6
256        | 182.4      | 195.8669   | 2942.2          | 4.0
~~~

Target cores 8 (0xFF). Buffer cache size 12

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 104.5      | 110.949    | 159.8           | 0
16         | 174.7      | 185.6216   | 191.4           | 2.1
32         | 184.8      | 196.2932   | 362.4           | 0
64         | 184.7      | 196.298    | 725.8           | .2
128        | 184.8      | 196.3279   | 1451.8          | .1
256        | 184.7      | 196.3195   | 2905.4          | .2
~~~

Target cores 4 (0xF). Buffer cache size 24

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 106.4      | 113.1102   | 157.0           | .1
16         | 174.4      | 185.751    | 191.7           | .2
32         | 184.8      | 196.3121   | 362.4           | 0
64         | 184.8      | 196.3286   | 725.6           | .1
128        | 184.8      | 196.3073   | 1451.9          | .1
256        | 184.8      | 196.3337   | 2904.5          | .1
~~~

Target cores 2 (0x3). Buffer cache size 48

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 109.5      | 116.4625   | 152.5           | .1
16         | 171.7      | 182.089    | 194.7           | .3
32         | 184.7      | 196.2224   | 362.6           | 0
64         | 184.8      | 196.3316   | 725.6           | .1
128        | 184.8      | 196.3326   | 1451.6          | .1
256        | 184.8      | 196.3332   | 2903.9          | .1
~~~

Target cores 1 (0x1). Buffer cache size 96

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 101.8      | 108.2169   | 164.1           | .1
16         | 150.8      | 160.8635   | 221.9           | .3
32         | 177.8      | 188.5567   | 376.8           | .3
64         | 177.6      | 188.2296   | 755.1           | .5
128        | 171.7      | 182.3304   | 1562.2          | .5
256        | 156.9      | 166.5067   | 3420.7          | .6
~~~

### Test 8

Check performance effects of buffer cache size.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$buf_cache_size config_nvme`

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

**Configuration**: `NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/16)) config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xFFFF

| Num buffers | Buf cache | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------|-----|-------|----------|-------------|-----------|-------------|
| 128         | 8         | 256 | 161.6 | 194.9704 | 3320.5      | 6.2       | 89.2        |
| 96          | 6         | 256 | 167.3 | 195.9908 | 3206.9      | 11.4      | 99.5        |
| 64          | 4         | 256 | 156.5 | 195.1129 | 3579.2      | 13.4      | 99.6        |
| 48          | 3         | 256 | 176.6 | 194.4154 | 3039.1      | 7.3       | 99.6        |
| 44          | 2         | 256 | 156.3 | 194.5452 | 3433.5      | 12.1      | 99.6        |
| 40          | 2         | 256 | 157.0 | 194.8172 | 3419.0      | 11.0      | 99.6        |
| 36          | 2         | 256 | 176.5 | 194.4009 | 3040.8      | 6.8       | 99.6        |
| 32          | 2         | 256 | 171.1 | 185.0244 | 3136.0      | 8.3       | 99.6        |
| 24          | 1         | 256 | 144.7 | 155.9214 | 3709.2      | 3.6       | 99.6        |
| 16          | 1         | 256 | 112.2 | 126.1672 | 4784.2      | 6.9       | 99.6        |


### Test 10

Check performance effect of number of data buffers with 4 cores. All
buffers are shared equally between all threads at start with
`BufCacheSize` parameter.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/4)) config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

| Num buffers | Buf cache | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------|------|-------|----------|-------------|-----------|-------------|
| 128         | 32        | 256  | 179.7 | 195.3655 | 2985.7      | 1.5       | 79.6        |
| 128         | 32        | 1024 | 172.1 | 181.9699 | 12473.3     | 2.7       | 71.3        |
| 96          | 24        | 256  | 184.6 | 196.331  | 2906.6      | .3        | 89.8        |
| 96          | 24        | 1024 | 184.4 | 196.3206 | 11641.4     | .6        | 87.7        |
| 64          | 16        | 256  | 184.8 | 196.3301 | 2904.6      | .3        | 99.5        |
| 64          | 16        | 1024 | 109.3 | 196.3159 | 19633.6     | 22.5      | 98.0        |
| 48          | 12        | 256  | 184.8 | 196.321  | 2904.1      | 0         | 99.5        |
| 48          | 12        | 1024 | 184.6 | 196.1717 | 11635.1     | .1        | 99.5        |
| 44          | 11        | 256  | 184.7 | 196.2367 | 2905.3      | .1        | 99.5        |
| 44          | 11        | 1024 | 184.2 | 195.6856 | 11659.6     | .1        | 99.5        |
| 40          | 10        | 256  | 184.4 | 196.0097 | 2910.2      | .3        | 99.5        |
| 40          | 10        | 1024 | 183.6 | 195.1481 | 11699.9     | .7        | 99.5        |
| 36          | 9         | 256  | 183.9 | 195.2629 | 2918.8      | .1        | 99.5        |
| 36          | 9         | 1024 | 181.8 | 193.365  | 11812.1     | .3        | 99.5        |
| 32          | 8         | 256  | 181.0 | 192.241  | 2964.6      | .3        | 99.5        |
| 32          | 8         | 1024 | 174.1 | 185.0916 | 12332.6     | .8        | 99.5        |
| 24          | 6         | 256  | 155.8 | 165.411  | 3445.7      | .5        | 99.5        |
| 24          | 6         | 1024 | 150.2 | 158.9911 | 14300.9     | 1.1       | 99.5        |
| 16          | 4         | 256  | 115.1 | 122.0057 | 4662.6      | .2        | 99.5        |
| 16          | 4         | 1024 | 109.8 | 116.4242 | 19565.0     | .9        | 99.5        |

Something strange is happening around 64 buffers with queue depth
of 1024. It is very unstable and numers are really low. Here is a
closer look with 3 runs for each.

| Num buffers | Buf cache | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------|------|-------|----------|-------------|-----------|-------------|
| 96          | 24        | 1024 | 184.5 | 196.3218 | 11636.1     | .4        | 88.0        |
| 96          | 24        | 1024 | 184.4 | 196.3181 | 11641.0     | .5        | 89.1        |
| 96          | 24        | 1024 | 184.5 | 196.3224 | 11639.6     | .5        | 88.4        |
| 80          | 20        | 1024 | 73.4  | 0        | 29277.6     | 28.4      | 99.4        |
| 80          | 20        | 1024 | 101.0 | 196.3324 | 22017.4     | 22.3      | 99.1        |
| 80          | 20        | 1024 | 74.0  | 0        | 29040.4     | 26.0      | 97.9        |
| 64          | 16        | 1024 | 131.7 | 30.8655  | 16737.7     | 17.3      | 99.4        |
| 64          | 16        | 1024 | 101.9 | 85.8252  | 22388.4     | 21.6      | 98.6        |
| 64          | 16        | 1024 | 134.4 | 77.1212  | 16298.1     | 14.4      | 98.8        |
| 56          | 14        | 1024 | 173.5 | 0        | 12379.3     | 5.8       | 99.5        |
| 56          | 14        | 1024 | 177.4 | 196.3213 | 12102.3     | 10.1      | 99.5        |
| 56          | 14        | 1024 | 168.7 | 0        | 12967.1     | 10.2      | 99.4        |
| 48          | 12        | 1024 | 184.6 | 196.2486 | 11634.9     | .1        | 99.5        |
| 48          | 12        | 1024 | 184.6 | 196.2123 | 11633.4     | .1        | 99.5        |
| 48          | 12        | 1024 | 184.6 | 196.255  | 11635.8     | .1        | 99.5        |

### Test 11

Split each NVMe disk into 3 partitions with SPDK split block device
and build delay block device on top of some partitions.

IO depth is shared equally between all disks. FIO runs 3 jobs with
queue depth of 85 or 341 each. This gives us total IO depth of 255 and
1023 per initiator respectively.

**IO pacing**: `Number of buffers`

**Configuration**: `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

| Num buffers | Num delay bdevs | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------------|-----|-------|----------|-------------|-----------|-------------|
| 96          | 0               | 85  | 182.0 | 193.3359 | 3018.7      | .2        | 93.5        |
| 96          | 0               | 341 | 179.8 | 195.2692 | 11759.9     | .1        | 93.9        |
| 96          | 16              | 85  | 184.2 | 195.7152 | 2901.8      | .1        | 93.3        |
| 96          | 16              | 341 | 179.7 | 190.0656 | 12304.2     | .3        | 92.0        |
| 96          | 32              | 85  | 126.2 | 133.2654 | 4235.2      | 1.1       | 87.4        |
| 96          | 32              | 341 | 120.7 | 127.0313 | 18325.3     | 2.5       | 86.5        |
| 48          | 0               | 85  | 184.7 | 196.2235 | 2893.5      | 0         | 99.5        |
| 48          | 0               | 341 | 152.9 | 196.2135 | 14459.1     | 4.1       | 99.4        |
| 48          | 16              | 85  | 111.6 | 117.5887 | 4790.3      | 1.5       | 99.3        |
| 48          | 16              | 341 | 102.2 | 109.9827 | 20979.1     | 2.7       | 99.2        |
| 48          | 32              | 85  | 64.6  | 67.3646  | 8279.2      | 1.4       | 99.1        |
| 48          | 32              | 341 | 71.8  | 65.8915  | 30960.4     | 3.6       | 99.0        |

### Test 12

Split each NVMe disk into 3 partitions with SPDK split block device
and build delay block device on top of some partitions.

FIO runs 3 jobs with 16 disks each. Job 1 is always delay devices, job
2 may be good (16 delay bdevs) or delay (32 dely bdevs), job 3 is
always good. IO depth is fixed to 256 or 1024 for job 3. For jobs 1
and 2 it is set to value in QD column in the table below. For 32 delay
bdevs effective IO depth is twice the QD since we have 2 jobs each
with it's own IO depth.

**IO pacing**: `Number of buffers`

**Configuration**: `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

Job 3 QD is 256.

| Num buffers | Num delay bdevs | QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------------|----|-------|----------|-------------|-----------|-------------|
| 48          | 16              | 1  | 184.6 | 196.2039 | 2929.3      | .1        | 99.5        |
| 48          | 16              | 2  | 184.5 | 196.1547 | 2954.4      | .2        | 99.5        |
| 48          | 16              | 4  | 184.4 | 195.9771 | 3000.7      | 0         | 99.5        |
| 48          | 16              | 8  | 183.8 | 195.504  | 3102.0      | .1        | 99.5        |
| 48          | 16              | 16 | 181.5 | 193.2384 | 3326.9      | .1        | 99.5        |
| 48          | 16              | 32 | 171.7 | 181.3755 | 4023.0      | .8        | 99.5        |
| 48          | 32              | 1  | 184.6 | 196.0657 | 2930.6      | .1        | 99.5        |
| 48          | 32              | 2  | 184.5 | 196.0089 | 2954.2      | .1        | 99.5        |
| 48          | 32              | 4  | 184.1 | 195.4684 | 3006.6      | 0         | 99.5        |
| 48          | 32              | 8  | 181.5 | 192.3983 | 3142.1      | .1        | 99.5        |
| 48          | 32              | 16 | 171.0 | 181.6819 | 3531.1      | .5        | 99.5        |

Job 3 QD is 1024

| Num buffers | Num delay bdevs | QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------------|----|-------|----------|-------------|-----------|-------------|
| 48          | 16              | 1  | 184.2 | 195.8731 | 11678.7     | .1        | 99.5        |
| 48          | 16              | 2  | 184.2 | 195.6442 | 11704.4     | .1        | 99.5        |
| 48          | 16              | 4  | 184.0 | 195.4774 | 11762.4     | .2        | 99.5        |
| 48          | 16              | 8  | 183.4 | 194.7805 | 11889.7     | .2        | 99.5        |
| 48          | 16              | 16 | 182.3 | 192.9675 | 12146.8     | .5        | 99.5        |
| 48          | 16              | 32 | 176.0 | 187.1557 | 13353.8     | 1.1       | 99.4        |
| 48          | 16              | 64 | 155.7 | 170.9021 | 15523.1     | 1.0       | 99.4        |
| 48          | 32              | 1  | 183.8 | 195.8345 | 11702.7     | .7        | 99.5        |
| 48          | 32              | 2  | 184.0 | 195.576  | 11717.9     | .1        | 99.5        |
| 48          | 32              | 4  | 183.8 | 195.586  | 11772.1     | .2        | 99.5        |
| 48          | 32              | 8  | 182.8 | 194.0948 | 11929.1     | .3        | 99.5        |
| 48          | 32              | 16 | 179.0 | 189.0024 | 12372.0     | .6        | 99.4        |
| 48          | 32              | 32 | 160.3 | 168.7374 | 14232.4     | 1.7       | 99.4        |
| 48          | 32              | 64 | 138.2 | 144.7699 | 17425.0     | 4.2       | 99.4        |


### Test 13

Test latencies with different configurations.

**IO pacing**: `N/A`

**Configuration**: `config_null_16`, `config_nvme`, `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

One initiator: spdk03

16 Null disks

| QD | BW   | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|------|---------|-------------|-----------|-------------|
| 1  | 50.8 | 53.6049 | 20.3        | .3        | 99.0        |
| 1  | 50.9 | 53.6818 | 20.3        | .3        | 99.0        |
| 1  | 50.1 | 52.8107 | 20.6        | .4        | 99.1        |
| 1  | 50.8 | 53.5558 | 20.3        | .3        | 99.1        |
| 1  | 50.7 | 53.5645 | 20.4        | .3        | 99.0        |

Local single NVMe disk (SPDK perf)

| QD | BW | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|----|---------|-------------|-----------|-------------|
| 1  | 11 |         | 87.51       |           |             |

16 NVMe disks

| QD  | BW   | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|------|---------|-------------|-----------|-------------|
| 1   | 8.5  | 9.0731  | 122.3       | 0         | 98.8        |
| 1   | 8.5  | 9.0599  | 122.4       | 0         | 98.8        |
| 1   | 8.5  | 9.0664  | 122.4       | 0         | 98.9        |
| 1   | 8.5  | 9.0549  | 122.3       | 0         | 98.8        |
| 1   | 8.5  | 9.0622  | 122.4       | 0         | 98.9        |

48 split disks (1 job)

| QD | BW  | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|-----|---------|-------------|-----------|-------------|
| 1  | 8.2 | 8.6961  | 127.5       | 0         | 99.0        |
| 1  | 8.2 | 8.7048  | 127.3       | 0         | 99.1        |
| 1  | 8.2 | 8.7198  | 127.2       | 0         | 99.0        |
| 1  | 8.2 | 8.7214  | 127.0       | 0         | 99.0        |
| 1  | 8.2 | 8.7181  | 127.2       | 0         | 99.0        |

48 split+delay disks (1 job)

| QD | BW | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|----|---------|-------------|-----------|-------------|
| 1  | .9 | 0.9805  | 1136.2      | 0         | 98.4        |
| 1  | .9 | 0.9805  | 1136.0      | 0         | 98.4        |
| 1  | .9 | 0.9805  | 1136.1      | 0         | 98.6        |
| 1  | .9 | 0.9805  | 1135.7      | 0         | 98.5        |
| 1  | .9 | 0.9805  | 1135.9      | 0         | 98.4        |

### Test 14

Basic test with rate based IO pacing.

**IO pacing**: `Rate based`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF (4 cores)

| IO pacer period | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----------------|------|-------|----------|-------------|-----------|-------------|
| 0               | 32   | 184.8 | 196.3317 | 362.5       | .1        | 98.8        |
| 0               | 256  | 160.3 | 169.6222 | 3347.9      | 2.8       | 71.7        |
| 0               | 1024 | 140.2 | 161.1577 | 14458.8     | 7.1       | 68.3        |
| 0               | 2048 | 138.5 | 155.6116 | 18660.9     | 7.6       | 67.0        |
| 3               | 32   | 184.8 | 196.3307 | 362.5       | 0         | 99.3        |
| 3               | 256  | 163.2 | 157.1766 | 3289.4      | 4.6       | 71.4        |
| 3               | 1024 | 141.5 | 160.0647 | 14787.5     | 6.9       | 63.2        |
| 3               | 2048 | 143.7 | 156.4782 | 16494.4     | 10.7      | 69.7        |
| 3.5             | 32   | 184.8 | 196.3309 | 362.5       | .1        | 99.4        |
| 3.5             | 256  | 163.0 | 159.7484 | 3292.2      | 4.5       | 73.6        |
| 3.5             | 1024 | 151.7 | 160.5335 | 12726.6     | 7.1       | 67.9        |
| 3.5             | 2048 | 147.4 | 161.3473 | 16528.0     | 9.2       | 64.7        |
| 4               | 32   | 168.3 | 178.5906 | 398.1       | .5        | 99.5        |
| 4               | 256  | 169.1 | 180.267  | 3173.9      | 1.9       | 99.5        |
| 4               | 1024 | 134.9 | 147.789  | 14972.4     | 5.6       | 68.0        |
| 4               | 2048 | 133.2 | 151.1227 | 19600.0     | 6.3       | 65.6        |
| 4.5             | 32   | 160.5 | 170.4317 | 417.6       | 1.1       | 99.5        |
| 4.5             | 256  | 157.9 | 167.3296 | 3399.1      | 1.2       | 99.5        |
| 4.5             | 1024 | 154.2 | 169.2268 | 13929.7     | 6.5       | 99.5        |
| 4.5             | 2048 | 139.0 | 168.8874 | 28507.3     | 11.1      | 99.4        |
| 5               | 32   | 160.0 | 169.7012 | 418.8       | .8        | 99.5        |
| 5               | 256  | 155.2 | 164.5528 | 3458.6      | 1.4       | 99.5        |
| 5               | 1024 | 151.5 | 165.0851 | 14177.8     | 5.7       | 99.5        |
| 5               | 2048 | 140.7 | 165.1421 | 28648.2     | 9.8       | 99.4        |
| 5.5             | 32   | 159.6 | 169.3923 | 419.8       | .8        | 99.5        |
| 5.5             | 256  | 156.0 | 165.2335 | 3441.2      | 1.3       | 99.5        |
| 5.5             | 1024 | 152.9 | 165.7459 | 14046.2     | 5.5       | 99.5        |
| 5.5             | 2048 | 147.8 | 165.2593 | 26727.6     | 8.6       | 99.4        |
| 6               | 32   | 152.0 | 161.2482 | 441.0       | 1.1       | 99.6        |
| 6               | 256  | 152.0 | 160.0379 | 3531.3      | 1.6       | 99.5        |
| 6               | 1024 | 148.7 | 160.3621 | 14437.2     | 4.9       | 99.5        |
| 6               | 2048 | 143.1 | 158.1064 | 24024.0     | 7.4       | 99.4        |
| 7               | 32   | 117.6 | 124.3374 | 569.9       | 2.2       | 99.5        |
| 7               | 256  | 116.8 | 123.3631 | 4596.2      | 3.4       | 99.5        |
| 7               | 1024 | 116.9 | 123.7242 | 18370.8     | 3.4       | 99.5        |
| 7               | 2048 | 115.3 | 124.6023 | 33296.3     | 6.5       | 99.4        |

**CPU mask**: 0xFF (8 cores)

| IO pacer period | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----------------|------|-------|----------|-------------|-----------|-------------|
| 0               | 32   | 184.8 | 196.3334 | 362.5       | .1        | 99.3        |
| 0               | 256  | 160.5 | 174.0253 | 3343.7      | 3.3       | 70.4        |
| 0               | 1024 | 140.2 | 158.5671 | 14516.7     | 8.3       | 67.1        |
| 0               | 2048 | 132.9 | 154.7515 | 20338.1     | 11.0      | 67.4        |
| 3               | 32   | 184.8 | 196.3277 | 362.5       | .1        | 99.4        |
| 3               | 256  | 159.7 | 169.2593 | 3360.5      | 3.5       | 68.9        |
| 3               | 1024 | 147.4 | 147.7872 | 13919.8     | 6.8       | 69.9        |
| 3               | 2048 | 133.1 | 98.1669  | 23824.1     | 8.9       | 64.6        |
| 3.5             | 32   | 184.8 | 196.326  | 362.4       | 0         | 99.4        |
| 3.5             | 256  | 160.3 | 171.4964 | 3347.3      | 3.7       | 69.8        |
| 3.5             | 1024 | 149.5 | 162.6794 | 13566.3     | 7.1       | 67.9        |
| 3.5             | 2048 | 143.9 | 162.4699 | 17132.6     | 9.9       | 72.3        |
| 4               | 32   | 184.8 | 196.3261 | 362.5       | .1        | 99.4        |
| 4               | 256  | 157.8 | 162.152  | 3401.0      | 3.2       | 71.9        |
| 4               | 1024 | 144.8 | 159.9945 | 13892.0     | 8.1       | 70.7        |
| 4               | 2048 | 147.7 | 162.3275 | 16816.0     | 9.7       | 70.1        |
| 4.5             | 32   | 184.8 | 196.3263 | 362.5       | .1        | 99.5        |
| 4.5             | 256  | 157.8 | 170.068  | 3401.7      | 3.5       | 69.6        |
| 4.5             | 1024 | 147.2 | 158.7259 | 13908.7     | 6.6       | 66.8        |
| 4.5             | 2048 | 138.8 | 160.577  | 19913.5     | 9.4       | 74.0        |
| 5               | 32   | 178.8 | 189.9759 | 374.8       | .2        | 99.5        |
| 5               | 256  | 175.2 | 188.1404 | 3062.5      | 3.5       | 99.5        |
| 5               | 1024 | 133.4 | 157.6215 | 16107.0     | 9.3       | 66.4        |
| 5               | 2048 | 133.0 | 164.3485 | 19846.7     | 7.7       | 68.5        |
| 5.5             | 32   | 178.1 | 189.5703 | 376.2       | .3        | 99.6        |
| 5.5             | 256  | 176.2 | 189.8118 | 3045.6      | 4.1       | 99.5        |
| 5.5             | 1024 | 154.5 | 155.0827 | 13899.7     | 10.6      | 70.7        |
| 5.5             | 2048 | 127.6 | 127.6582 | 21034.0     | 6.8       | 68.2        |
| 6               | 32   | 150.0 | 158.9347 | 446.6       | 1.3       | 99.6        |
| 6               | 256  | 149.3 | 158.4648 | 3593.7      | 1.7       | 99.5        |
| 6               | 1024 | 145.4 | 158.4566 | 14764.2     | 5.2       | 99.5        |
| 6               | 2048 | 143.0 | 158.3105 | 27274.5     | 7.5       | 99.5        |
| 7               | 32   | 133.0 | 140.5932 | 503.9       | 2.2       | 99.5        |
| 7               | 256  | 134.1 | 141.9532 | 4001.6      | 2.5       | 99.5        |
| 7               | 1024 | 131.0 | 141.4608 | 16389.5     | 6.1       | 99.5        |
| 7               | 2048 | 122.4 | 126.7452 | 20854.1     | 9.8       | 58.6        |

**CPU mask**: 0xFFFF (16 cores)

| IO pacer period | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----------------|------|-------|----------|-------------|-----------|-------------|
| 0               | 32   | 171.0 | 192.7966 | 391.8       | 12.6      | 97.4        |
| 0               | 256  | 144.5 | 132.7806 | 3715.0      | 6.8       | 67.6        |
| 0               | 1024 | 126.2 | 124.0217 | 16197.1     | 7.5       | 60.2        |
| 0               | 2048 | 131.6 | 129.8344 | 19247.9     | 9.1       | 60.2        |
| 3               | 32   | 170.7 | 192.8037 | 392.5       | 12.6      | 99.0        |
| 3               | 256  | 143.5 | 155.7446 | 3739.5      | 6.1       | 63.2        |
| 3               | 1024 | 130.7 | 115.7254 | 15326.2     | 7.6       | 60.6        |
| 3               | 2048 | 126.8 | 133.085  | 22887.8     | 9.6       | 64.7        |
| 3.5             | 32   | 170.8 | 192.5502 | 392.2       | 12.4      | 99.0        |
| 3.5             | 256  | 142.5 | 146.9747 | 3766.9      | 6.2       | 68.2        |
| 3.5             | 1024 | 131.7 | 116.574  | 15235.3     | 7.8       | 61.2        |
| 3.5             | 2048 | 129.4 | 137.2487 | 19852.8     | 10.2      | 61.9        |
| 4               | 32   | 170.8 | 192.4459 | 392.3       | 12.5      | 98.4        |
| 4               | 256  | 141.3 | 148.7148 | 3797.6      | 6.7       | 66.9        |
| 4               | 1024 | 131.6 | 116.1092 | 15129.3     | 8.0       | 61.0        |
| 4               | 2048 | 131.1 | 127.1635 | 20653.8     | 8.5       | 61.5        |
| 4.5             | 32   | 170.4 | 192.1688 | 393.2       | 12.5      | 99.3        |
| 4.5             | 256  | 143.2 | 142.1507 | 3748.6      | 5.5       | 71.9        |
| 4.5             | 1024 | 128.5 | 119.4071 | 16703.3     | 5.9       | 61.4        |
| 4.5             | 2048 | 130.8 | 130.8235 | 21526.4     | 9.2       | 59.9        |
| 5               | 32   | 168.2 | 191.6887 | 398.4       | 13.8      | 99.6        |
| 5               | 256  | 144.2 | 166.1459 | 3722.2      | 5.9       | 73.5        |
| 5               | 1024 | 130.4 | 125.4646 | 16352.6     | 7.0       | 59.0        |
| 5               | 2048 | 131.2 | 124.4609 | 19505.3     | 8.4       | 63.1        |
| 5.5             | 32   | 160.1 | 183.4443 | 418.7       | 13.2      | 99.6        |
| 5.5             | 256  | 167.0 | 186.9249 | 3213.7      | 8.0       | 99.6        |
| 5.5             | 1024 | 159.7 | 188.5    | 12652.1     | 11.0      | 99.6        |
| 5.5             | 2048 | 124.5 | 121.7424 | 26739.1     | 7.2       | 59.5        |
| 6               | 32   | 150.5 | 171.9523 | 445.1       | 12.0      | 99.6        |
| 6               | 256  | 160.6 | 176.0261 | 3341.4      | 4.5       | 99.6        |
| 6               | 1024 | 154.7 | 177.7808 | 13407.4     | 8.3       | 99.5        |
| 6               | 2048 | 119.0 | 113.8833 | 28619.8     | 5.6       | 61.6        |
| 7               | 32   | 129.2 | 146.9376 | 518.7       | 10.2      | 99.6        |
| 7               | 256  | 136.4 | 146.3027 | 3933.4      | 4.7       | 99.6        |
| 7               | 1024 | 137.1 | 149.7633 | 13261.0     | 4.4       | 99.6        |
| 7               | 2048 | 134.8 | 149.1207 | 24787.8     | 6.1       | 99.5        |
