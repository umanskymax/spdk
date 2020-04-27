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
| 32   | 184.7 | 196.333  | 362.8       | .4        | 97.1        | 62.3 (7.7)           |
| 36   | 184.7 | 196.3339 | 408.2       | .3        | 93.9        | 68.6 (8.5)           |
| 40   | 184.6 | 196.3309 | 453.7       | .3        | 93.5        | 78.0 (9.7)           |
| 44   | 182.7 | 196.0504 | 504.4       | 1.2       | 81.8        | 86.3 (10.7)          |
| 48   | 177.5 | 187.658  | 566.5       | 1.6       | 77.5        | 93.6 (11.7)          |
| 64   | 167.8 | 179.6868 | 799.0       | 2.7       | 73.3        | 123.3 (15.4)         |
| 128  | 162.2 | 180.4201 | 1653.7      | 5.0       | 73.2        | 253.0 (31.6)         |
| 256  | 152.7 | 176.4986 | 3514.7      | 5.0       | 74.5        | 500.0 (62.5)         |
| 1024 | 136.6 | 159.2902 | 14241.0     | 6.9       | 63.4        | 933.0 (116.6)        |
| 2048 | 134.8 | 157.7392 | 19880.3     | 8.8       | 68.7        | 1277.0 (159.6)       |

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
| 32   | 184.7 | 196.3081 | 362.7       | .2        | 99.3        | 59.6 (7.4)           |
| 64   | 184.4 | 196.3301 | 727.0       | .6        | 90.6        | 89.6 (11.2)          |
| 128  | 184.5 | 196.3342 | 1454.3      | .4        | 90.5        | 91.3 (11.4)          |
| 256  | 184.5 | 196.3295 | 2908.7      | .4        | 90.1        | 91.3 (11.4)          |
| 1024 | 184.2 | 196.3299 | 11654.3     | .5        | 89.7        | 94.0 (11.7)          |
| 2048 | 184.1 | 196.3253 | 21264.3     | 1.2       | 89.8        | 95.0 (11.8)          |

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

| Num buffers | Buf cache | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-------------|-----------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 128         | 32        | 256  | 176.6 | 191.0384 | 3038.0      | 1.8       | 79.0        | 102.6 (12.8)         |
| 128         | 32        | 1024 | 153.7 | 178.4195 | 13541.1     | 9.5       | 75.7        | 111.3 (13.9)         |
| 96          | 24        | 256  | 184.5 | 196.329  | 2908.5      | .3        | 89.5        | 91.0 (11.3)          |
| 96          | 24        | 1024 | 184.2 | 196.317  | 11654.3     | .5        | 88.5        | 95.6 (11.9)          |
| 64          | 16        | 256  | 184.8 | 196.324  | 2904.0      | .1        | 99.5        | 62.0 (7.7)           |
| 64          | 16        | 1024 | 77.4  | 157.1605 | 29278.3     | 28.3      | 98.0        | 57.3 (7.1)           |
| 48          | 12        | 256  | 184.7 | 196.2684 | 2906.1      | .2        | 99.5        | 43.3 (5.4)           |
| 48          | 12        | 1024 | 184.5 | 196.1051 | 11640.6     | .2        | 99.5        | 41.6 (5.2)           |
| 44          | 11        | 256  | 172.3 | 196.2197 | 3114.4      | 7.1       | 99.5        | 40.0 (5.0)           |
| 44          | 11        | 1024 | 175.2 | 195.7898 | 12259.3     | 8.2       | 99.5        | 38.3 (4.7)           |
| 40          | 10        | 256  | 184.4 | 195.948  | 2910.4      | .1        | 99.5        | 38.3 (4.7)           |
| 40          | 10        | 1024 | 170.6 | 195.2709 | 12590.4     | 3.5       | 99.5        | 33.0 (4.1)           |
| 36          | 9         | 256  | 174.0 | 195.4031 | 3084.8      | 5.8       | 99.5        | 34.0 (4.2)           |
| 36          | 9         | 1024 | 175.7 | 192.7424 | 12233.8     | .9        | 99.5        | 29.0 (3.6)           |
| 32          | 8         | 256  | 181.0 | 192.3175 | 2965.5      | .3        | 99.5        | 29.6 (3.7)           |
| 32          | 8         | 1024 | 174.1 | 185.2337 | 12338.3     | .6        | 99.5        | 25.6 (3.2)           |
| 24          | 6         | 256  | 156.1 | 166.2031 | 3438.5      | .5        | 99.6        | 21.3 (2.6)           |
| 24          | 6         | 1024 | 149.3 | 158.9107 | 14384.8     | 1.1       | 99.5        | 20.0 (2.5)           |
| 16          | 4         | 256  | 115.4 | 122.4798 | 4648.1      | .2        | 99.5        | 14.6 (1.8)           |
| 16          | 4         | 1024 | 109.7 | 115.9732 | 19572.2     | .7        | 99.5        | 14.0 (1.7)           |


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

| Num buffers | Num delay bdevs | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-------------|-----------------|-----|-------|----------|-------------|-----------|-------------|----------------------|
| 96          | 0               | 85  | 181.9 | 193.1907 | 2939.0      | .6        | 93.5        | 93.6 (11.7)          |
| 96          | 0               | 341 | 179.3 | 194.0893 | 11966.7     | 1.8       | 93.6        | 95.0 (11.8)          |
| 96          | 16              | 85  | 184.0 | 195.7565 | 2988.2      | .1        | 93.4        | 89.0 (11.1)          |
| 96          | 16              | 341 | 179.3 | 190.1234 | 12368.2     | .3        | 92.2        | 91.6 (11.4)          |
| 96          | 32              | 85  | 139.0 | 145.6064 | 4052.0      | 2.4       | 89.1        | 89.0 (11.1)          |
| 96          | 32              | 341 | 124.5 | 127.9649 | 17376.1     | 2.5       | 86.6        | 94.3 (11.7)          |
| 48          | 0               | 85  | 184.5 | 196.2425 | 2974.9      | 1.1       | 99.5        | 47.3 (5.9)           |
| 48          | 0               | 341 | 175.7 | 196.0569 | 12306.1     | 2.5       | 99.4        | 45.6 (5.7)           |
| 48          | 16              | 85  | 135.8 | 141.2414 | 4363.3      | 3.2       | 99.4        | 47.3 (5.9)           |
| 48          | 16              | 341 | 111.3 | 113.8428 | 19482.0     | 3.1       | 99.3        | 44.0 (5.5)           |
| 48          | 32              | 85  | 89.6  | 93.682   | 6943.0      | 2.2       | 99.3        | 47.0 (5.8)           |
| 48          | 32              | 341 | 66.7  | 67.6684  | 32658.4     | 2.1       | 99.1        | 43.0 (5.3)           |

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

| IO pacer period | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-----------------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 0               | 32   | 184.7 | 196.326  | 362.7       | .2        | 99.0        | 59.6 (7.4)           |
| 0               | 256  | 155.4 | 159.4917 | 3452.7      | 4.3       | 73.8        | 400.6 (50.0)         |
| 0               | 1024 | 139.4 | 159.708  | 13732.8     | 7.6       | 67.6        | 909.3 (113.6)        |
| 0               | 2048 | 142.2 | 161.4203 | 16135.2     | 8.0       | 69.9        | 863.3 (107.9)        |
| 3               | 32   | 184.8 | 196.3269 | 362.6       | .1        | 99.4        | 54.6 (6.8)           |
| 3               | 256  | 155.6 | 175.9233 | 3448.5      | 4.7       | 73.8        | 437.3 (54.6)         |
| 3               | 1024 | 145.7 | 163.9056 | 14115.5     | 5.7       | 69.5        | 909.3 (113.6)        |
| 3               | 2048 | 129.7 | 135.0755 | 24125.6     | 7.9       | 63.1        | 1298.3 (162.2)       |
| 3.5             | 32   | 184.7 | 196.3315 | 362.8       | .3        | 99.5        | 54.6 (6.8)           |
| 3.5             | 256  | 159.4 | 177.9331 | 3367.9      | 3.7       | 73.6        | 416.6 (52.0)         |
| 3.5             | 1024 | 138.7 | 160.4113 | 14830.5     | 7.9       | 71.8        | 1031.0 (128.8)       |
| 3.5             | 2048 | 147.3 | 171.372  | 16673.3     | 9.0       | 72.0        | 941.0 (117.6)        |
| 4               | 32   | 168.3 | 179.0991 | 398.0       | .3        | 99.6        | 22.3 (2.7)           |
| 4               | 256  | 168.3 | 179.1769 | 3188.8      | 2.0       | 99.5        | 23.0 (2.8)           |
| 4               | 1024 | 134.4 | 126.4239 | 14583.5     | 4.4       | 64.5        | 892.0 (111.5)        |
| 4               | 2048 | 130.4 | 154.1629 | 24291.5     | 8.8       | 69.6        | 1380.0 (172.5)       |
| 4.5             | 32   | 160.5 | 170.3565 | 417.5       | .8        | 99.5        | 20.0 (2.5)           |
| 4.5             | 256  | 157.3 | 166.9201 | 3412.8      | 1.1       | 99.5        | 21.0 (2.6)           |
| 4.5             | 1024 | 154.1 | 168.8149 | 13933.8     | 5.9       | 99.5        | 21.6 (2.7)           |
| 4.5             | 2048 | 147.5 | 169.1376 | 28027.7     | 9.2       | 99.5        | 526.0 (65.7)         |
| 5               | 32   | 159.6 | 169.4616 | 419.8       | .5        | 99.6        | 21.0 (2.6)           |
| 5               | 256  | 154.3 | 163.9354 | 3477.0      | 1.2       | 99.5        | 20.6 (2.5)           |
| 5               | 1024 | 151.3 | 164.628  | 14192.5     | 5.3       | 99.5        | 21.6 (2.7)           |
| 5               | 2048 | 137.8 | 164.7405 | 29030.0     | 11.2      | 99.4        | 1088.0 (136.0)       |
| 5.5             | 32   | 159.6 | 169.493  | 419.9       | .6        | 99.6        | 21.0 (2.6)           |
| 5.5             | 256  | 154.1 | 163.4106 | 3482.3      | 1.1       | 99.5        | 18.6 (2.3)           |
| 5.5             | 1024 | 151.4 | 164.7501 | 14180.4     | 5.3       | 99.5        | 19.0 (2.3)           |
| 5.5             | 2048 | 146.5 | 163.5427 | 27635.8     | 7.9       | 99.4        | 23.6 (2.9)           |
| 6               | 32   | 150.6 | 160.2117 | 444.9       | 1.2       | 99.5        | 18.3 (2.2)           |
| 6               | 256  | 150.7 | 160.2014 | 3559.9      | 1.2       | 99.5        | 16.6 (2.0)           |
| 6               | 1024 | 147.9 | 160.2129 | 14516.3     | 4.7       | 99.5        | 18.6 (2.3)           |
| 6               | 2048 | 144.4 | 159.8682 | 23785.4     | 7.3       | 99.4        | 23.0 (2.8)           |
| 7               | 32   | 116.6 | 123.7133 | 574.6       | 1.1       | 99.5        | 13.6 (1.7)           |
| 7               | 256  | 116.0 | 122.9794 | 4625.6      | 2.5       | 99.5        | 12.6 (1.5)           |
| 7               | 1024 | 116.3 | 123.381  | 18466.9     | 2.9       | 99.5        | 14.0 (1.7)           |
| 7               | 2048 | 115.2 | 123.2602 | 33173.5     | 2.8       | 99.4        | 16.0 (2.0)           |


**CPU mask**: 0xFF (8 cores)

| IO pacer period | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-----------------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 0               | 32   | 184.7 | 196.3261 | 362.7       | .2        | 97.6        | 60.3 (7.5)           |
| 0               | 256  | 155.3 | 172.7652 | 3455.0      | 4.1       | 71.4        | 412.6 (51.5)         |
| 0               | 1024 | 135.7 | 151.4161 | 14187.7     | 7.1       | 70.8        | 933.6 (116.7)        |
| 0               | 2048 | 133.9 | 167.4473 | 20217.7     | 9.8       | 71.7        | 1182.0 (147.7)       |
| 3               | 32   | 184.4 | 196.3272 | 363.3       | .6        | 98.0        | 53.6 (6.7)           |
| 3               | 256  | 154.7 | 156.8723 | 3469.2      | 3.9       | 74.5        | 415.0 (51.8)         |
| 3               | 1024 | 144.7 | 156.8903 | 13467.6     | 6.1       | 68.4        | 824.6 (103.0)        |
| 3               | 2048 | 133.4 | 170.5178 | 20613.1     | 8.6       | 80.7        | 1230.6 (153.8)       |
| 3.5             | 32   | 184.5 | 196.3298 | 363.0       | .4        | 99.4        | 55.0 (6.8)           |
| 3.5             | 256  | 157.7 | 175.0125 | 3402.3      | 3.4       | 70.4        | 423.6 (52.9)         |
| 3.5             | 1024 | 145.5 | 156.4714 | 13652.6     | 6.4       | 68.4        | 857.0 (107.1)        |
| 3.5             | 2048 | 144.0 | 162.0617 | 16995.2     | 8.5       | 71.3        | 924.0 (115.5)        |
| 4               | 32   | 184.6 | 196.3317 | 362.9       | .5        | 99.0        | 51.3 (6.4)           |
| 4               | 256  | 156.8 | 168.0704 | 3423.4      | 3.1       | 69.7        | 423.3 (52.9)         |
| 4               | 1024 | 145.3 | 155.8483 | 13638.7     | 6.1       | 71.8        | 832.6 (104.0)        |
| 4               | 2048 | 144.6 | 166.6413 | 17667.9     | 8.3       | 72.5        | 938.3 (117.2)        |
| 4.5             | 32   | 184.7 | 196.3324 | 362.8       | .4        | 99.5        | 51.3 (6.4)           |
| 4.5             | 256  | 156.4 | 165.4561 | 3431.8      | 3.2       | 71.3        | 385.6 (48.2)         |
| 4.5             | 1024 | 142.7 | 158.0574 | 14145.0     | 7.9       | 73.1        | 872.0 (109.0)        |
| 4.5             | 2048 | 140.2 | 152.1634 | 17659.1     | 9.7       | 69.9        | 996.6 (124.5)        |
| 5               | 32   | 177.3 | 188.3584 | 377.9       | .3        | 99.6        | 26.0 (3.2)           |
| 5               | 256  | 172.1 | 186.7812 | 3118.0      | 4.2       | 99.6        | 24.6 (3.0)           |
| 5               | 1024 | 152.2 | 149.0763 | 14107.8     | 10.0      | 70.5        | 438.0 (54.7)         |
| 5               | 2048 | 132.9 | 123.4084 | 19384.9     | 7.5       | 70.5        | 965.0 (120.6)        |
| 5.5             | 32   | 177.8 | 188.4768 | 376.8       | .3        | 99.6        | 25.0 (3.1)           |
| 5.5             | 256  | 174.4 | 189.6739 | 3076.5      | 5.2       | 99.5        | 24.6 (3.0)           |
| 5.5             | 1024 | 156.5 | 155.6489 | 13712.9     | 10.3      | 99.5        | 433.0 (54.1)         |
| 5.5             | 2048 | 126.8 | 135.9614 | 19615.2     | 7.0       | 64.1        | 934.6 (116.8)        |
| 6               | 32   | 149.5 | 158.756  | 448.4       | .5        | 99.6        | 21.0 (2.6)           |
| 6               | 256  | 148.4 | 157.6493 | 3616.0      | 1.2       | 99.5        | 20.6 (2.5)           |
| 6               | 1024 | 145.6 | 157.9236 | 14743.2     | 4.6       | 99.5        | 22.0 (2.7)           |
| 6               | 2048 | 142.2 | 159.1991 | 21708.6     | 7.5       | 99.2        | 566.6 (70.8)         |
| 7               | 32   | 132.6 | 140.74   | 505.2       | 1.7       | 99.5        | 18.0 (2.2)           |
| 7               | 256  | 130.5 | 141.1429 | 4124.0      | 6.5       | 99.5        | 18.6 (2.3)           |
| 7               | 1024 | 132.4 | 141.2836 | 16219.2     | 2.9       | 99.5        | 17.3 (2.1)           |
| 7               | 2048 | 129.9 | 141.5682 | 18925.4     | 4.8       | 99.5        | 22.3 (2.7)           |

**CPU mask**: 0xFFFF (16 cores)

| IO pacer period | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-----------------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 0               | 32   | 157.1 | 192.6975 | 426.7       | 15.5      | 97.4        | 41.0 (5.1)           |
| 0               | 256  | 147.9 | 139.9135 | 3628.4      | 8.3       | 66.2        | 124.0 (15.5)         |
| 0               | 1024 | 118.3 | 121.855  | 18145.6     | 5.5       | 61.7        | 1114.6 (139.3)       |
| 0               | 2048 | 117.8 | 128.873  | 23977.6     | 7.1       | 65.3        | 1066.3 (133.2)       |
| 3               | 32   | 156.8 | 192.0871 | 427.3       | 15.4      | 98.8        | 13.6 (1.7)           |
| 3               | 256  | 144.4 | 139.0355 | 3717.0      | 6.6       | 70.8        | 216.3 (27.0)         |
| 3               | 1024 | 120.3 | 118.4527 | 17764.2     | 5.9       | 59.8        | 1056.6 (132.0)       |
| 3               | 2048 | 124.2 | 133.5791 | 22908.2     | 7.1       | 63.2        | 1256.6 (157.0)       |
| 3.5             | 32   | 156.5 | 192.8006 | 428.1       | 15.3      | 98.7        | 23.6 (2.9)           |
| 3.5             | 256  | 145.5 | 145.6146 | 3689.6      | 7.3       | 68.3        | 133.3 (16.6)         |
| 3.5             | 1024 | 119.8 | 118.7067 | 17865.7     | 4.8       | 60.9        | 1152.0 (144.0)       |
| 3.5             | 2048 | 118.5 | 120.0079 | 28888.4     | 8.4       | 61.8        | 1362.0 (170.2)       |
| 4               | 32   | 160.3 | 192.2175 | 418.1       | 14.8      | 99.1        | 7.0 (.8)             |
| 4               | 256  | 143.9 | 146.0938 | 3729.2      | 5.7       | 70.8        | 154.0 (19.2)         |
| 4               | 1024 | 121.6 | 121.327  | 17652.6     | 5.0       | 60.4        | 989.3 (123.6)        |
| 4               | 2048 | 123.7 | 126.1712 | 23311.9     | 7.2       | 64.4        | 1247.3 (155.9)       |
| 4.5             | 32   | 163.9 | 192.0934 | 408.9       | 14.0      | 99.2        | 14.0 (1.7)           |
| 4.5             | 256  | 143.1 | 142.2712 | 3751.3      | 6.1       | 71.2        | 69.6 (8.7)           |
| 4.5             | 1024 | 119.7 | 113.8634 | 17937.7     | 5.6       | 61.2        | 1225.3 (153.1)       |
| 4.5             | 2048 | 120.9 | 120.411  | 22412.2     | 6.3       | 63.7        | 1038.0 (129.7)       |
| 5               | 32   | 161.5 | 191.477  | 414.9       | 15.0      | 99.6        | 7.3 (.9)             |
| 5               | 256  | 140.8 | 140.1633 | 3810.4      | 6.1       | 70.8        | 17.6 (2.2)           |
| 5               | 1024 | 128.7 | 130.1267 | 16237.6     | 5.9       | 65.7        | 639.0 (79.8)         |
| 5               | 2048 | 123.0 | 137.0747 | 28799.5     | 5.5       | 64.3        | 1345.0 (168.1)       |
| 5.5             | 32   | 149.9 | 184.0611 | 447.1       | 15.2      | 99.6        | 4.0 (.5)             |
| 5.5             | 256  | 166.1 | 187.735  | 3230.1      | 7.7       | 99.6        | 13.0 (1.6)           |
| 5.5             | 1024 | 155.4 | 190.7564 | 12502.8     | 13.3      | 99.5        | 17.0 (2.1)           |
| 5.5             | 2048 | 132.6 | 128.0856 | 27583.3     | 12.5      | 99.5        | 687.6 (85.9)         |
| 6               | 32   | 139.5 | 171.5644 | 480.3       | 14.2      | 99.6        | 7.3 (.9)             |
| 6               | 256  | 156.9 | 173.7479 | 3421.6      | 6.2       | 99.6        | 14.3 (1.7)           |
| 6               | 1024 | 159.2 | 175.3013 | 11151.3     | 4.7       | 99.6        | 16.6 (2.0)           |
| 6               | 2048 | 122.0 | 113.6632 | 27780.1     | 14.0      | 61.8        | 19.6 (2.4)           |
| 7               | 32   | 120.2 | 145.2542 | 557.7       | 12.1      | 99.6        | 7.6 (.9)             |
| 7               | 256  | 134.8 | 149.7191 | 3981.2      | 4.9       | 99.6        | 12.3 (1.5)           |
| 7               | 1024 | 132.8 | 147.468  | 15044.0     | 7.6       | 99.6        | 17.0 (2.1)           |
| 7               | 2048 | 125.0 | 138.102  | 25433.0     | 9.1       | 60.5        | 14.3 (1.7)           |
