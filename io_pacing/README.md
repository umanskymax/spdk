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

**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us | Pacer IO period, us | NVMf req lat, us |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|------------------|---------------------|------------------|
| 4.5 (18)         | 32   | 184.7 | 196.3387 | 362.7       | .2        | 99.4        | 24.6 (3.0)           | 18.0             | 22.691              | 310.632          |
| 4.5 (18)         | 256  | 158.7 | 171.543  | 3381.4      | 4.6       | 73.5        | 284.3 (35.5)         | 18.0             | 27.017              | 2869.352         |
| 4.5 (18)         | 1024 | 144.7 | 164.9834 | 11724.2     | 8.0       | 68.1        | 442.0 (55.2)         | 18.1             | 29.591              | 5279.924         |
| 4.5 (18)         | 2048 | 146.0 | 166.1827 | 11700.8     | 8.2       | 68.8        | 684.3 (85.5)         | 18.1             | 28.525              | 4899.519         |
| 5 (20)           | 32   | 184.7 | 196.3264 | 362.6       | .3        | 99.4        | 22.6 (2.8)           | 20.0             | 22.694              | 302.823          |
| 5 (20)           | 256  | 159.9 | 178.1602 | 3355.9      | 4.6       | 75.9        | 271.6 (33.9)         | 20.0             | 26.621              | 2635.266         |
| 5 (20)           | 1024 | 147.1 | 142.1386 | 10929.3     | 8.6       | 65.2        | 653.0 (81.6)         | 20.1             | 29.631              | 5892.605         |
| 5 (20)           | 2048 | 151.0 | 167.1647 | 9959.2      | 9.0       | 73.7        | 400.6 (50.0)         | 20.1             | 28.604              | 4471.030         |
| 5.5 (22)         | 32   | 184.8 | 196.3183 | 362.6       | .2        | 99.5        | 19.3 (2.4)           | 22.0             | 22.688              | 289.424          |
| 5.5 (22)         | 256  | 161.6 | 155.467  | 3322.2      | 4.1       | 73.9        | 301.0 (37.6)         | 22.0             | 26.372              | 2598.139         |
| 5.5 (22)         | 1024 | 154.1 | 165.7173 | 10177.7     | 7.3       | 73.7        | 531.0 (66.3)         | 22.1             | 27.548              | 4322.050         |
| 5.5 (22)         | 2048 | 142.8 | 98.1636  | 16278.4     | 8.9       | 64.4        | 867.6 (108.4)        | 22.1             | 30.647              | 7747.638         |
| 6 (24)           | 32   | 174.3 | 185.1482 | 384.4       | .4        | 99.5        | 12.6 (1.5)           | 24.0             | 24.073              | 149.504          |
| 6 (24)           | 256  | 174.1 | 184.9713 | 3083.0      | .5        | 99.5        | 13.3 (1.6)           | 24.0             | 24.098              | 150.923          |
| 6 (24)           | 1024 | 157.6 | 184.4075 | 12587.9     | 11.3      | 99.0        | 255.6 (31.9)         | 24.0             | 24.963              | 931.933          |
| 6 (24)           | 2048 | 123.2 | 125.8955 | 13124.2     | 6.3       | 56.2        | 774.6 (96.8)         | 24.1             | 34.703              | 6288.830         |
| 6.5 (26)         | 32   | 161.2 | 171.1174 | 415.8       | .9        | 99.6        | 12.0 (1.5)           | 26.0             | 26.056              | 140.132          |
| 6.5 (26)         | 256  | 161.1 | 170.8906 | 3331.4      | 1.1       | 99.5        | 11.0 (1.3)           | 26.0             | 26.062              | 140.794          |
| 6.5 (26)         | 1024 | 161.0 | 170.962  | 13342.4     | 1.2       | 99.5        | 12.6 (1.5)           | 26.0             | 26.074              | 144.894          |
| 6.5 (26)         | 2048 | 117.5 | 111.616  | 19409.7     | 7.0       | 48.5        | 824.3 (103.0)        | 26.0             | 36.217              | 11293.054        |

**CPU mask**: 0xFF0 (8 cores)

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us | Pacer IO period, us | NVMf req lat, us |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|------------------|---------------------|------------------|
| 4.5 (18)         | 32   | 184.6 | 196.3181 | 362.9       | .5        | 99.0        | 24.0 (3.0)           | 36.0             | 45.420              | 307.145          |
| 4.5 (18)         | 256  | 153.2 | 170.6894 | 3503.7      | 4.1       | 74.6        | 269.0 (33.6)         | 36.0             | 55.737              | 2574.694         |
| 4.5 (18)         | 1024 | 145.4 | 98.1667  | 11031.4     | 6.5       | 65.4        | 630.0 (78.7)         | 36.0             | 59.482              | 5479.082         |
| 4.5 (18)         | 2048 | 157.7 | 160.9478 | 7760.4      | 4.9       | 71.9        | 516.0 (64.5)         | 36.0             | 53.589              | 2521.242         |
| 5 (20)           | 32   | 184.7 | 196.3309 | 362.8       | .4        | 99.5        | 22.0 (2.7)           | 40.0             | 45.399              | 293.140          |
| 5 (20)           | 256  | 155.6 | 168.4966 | 3449.7      | 4.0       | 70.8        | 265.0 (33.1)         | 40.0             | 54.595              | 2587.999         |
| 5 (20)           | 1024 | 157.0 | 174.8313 | 9742.5      | 4.3       | 71.3        | 539.6 (67.4)         | 40.0             | 53.839              | 3415.488         |
| 5 (20)           | 2048 | 146.8 | 162.5777 | 12454.0     | 5.5       | 70.3        | 672.3 (84.0)         | 40.0             | 56.351              | 4996.025         |
| 5.5 (22)         | 32   | 184.6 | 196.3294 | 362.9       | .5        | 99.5        | 23.3 (2.9)           | 44.0             | 45.419              | 279.225          |
| 5.5 (22)         | 256  | 158.4 | 173.4521 | 3388.0      | 3.5       | 72.4        | 262.0 (32.7)         | 44.0             | 53.826              | 2481.968         |
| 5.5 (22)         | 1024 | 154.4 | 138.8956 | 9887.7      | 5.7       | 73.3        | 501.3 (62.6)         | 44.0             | 55.068              | 3676.868         |
| 5.5 (22)         | 2048 | 148.6 | 154.6103 | 15041.1     | 5.3       | 70.9        | 771.6 (96.4)         | 44.0             | 55.647              | 5046.112         |
| 6 (24)           | 32   | 174.6 | 185.4689 | 383.7       | .5        | 99.6        | 15.3 (1.9)           | 48.0             | 48.067              | 149.963          |
| 6 (24)           | 256  | 174.6 | 185.5436 | 3072.8      | .5        | 99.5        | 18.3 (2.2)           | 48.0             | 48.033              | 152.571          |
| 6 (24)           | 1024 | 148.5 | 135.355  | 13745.9     | 11.8      | 89.4        | 383.3 (47.9)         | 48.0             | 55.054              | 3718.257         |
| 6 (24)           | 2048 | 120.8 | 122.6952 | 13456.2     | 8.2       | 59.3        | 302.0 (37.7)         | 48.0             | 70.746              | 6635.210         |
| 6.5 (26)         | 32   | 161.4 | 171.2713 | 415.2       | .8        | 99.6        | 16.0 (2.0)           | 52.0             | 52.042              | 140.908          |
| 6.5 (26)         | 256  | 161.4 | 171.2786 | 3324.2      | 1.1       | 99.5        | 18.0 (2.2)           | 52.0             | 52.020              | 143.101          |
| 6.5 (26)         | 1024 | 161.3 | 171.2789 | 13311.1     | 1.0       | 99.5        | 19.3 (2.4)           | 52.0             | 52.022              | 150.868          |
| 6.5 (26)         | 2048 | 116.7 | 114.534  | 17227.4     | 5.6       | 56.2        | 379.3 (47.4)         | 52.0             | 74.097              | 10018.004        |

**Sweet spot search**
**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|------------------|-----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 5.6 (22.4)       | 256 | 162.3 | 184.4569 | 3307.7      | 4.7       | 73.8        | 295.3 (36.9)         | 22.5             |
| 5.65 (22.6)      | 256 | 180.1 | 195.8432 | 2980.4      | 3.6       | 99.5        | 107.6 (13.4)         | 22.7             |
| 5.7 (22.8)       | 256 | 182.8 | 194.3643 | 2935.2      | .2        | 99.5        | 11.6 (1.4)           | 22.8             |
| 5.75 (23)        | 256 | 177.7 | 192.5642 | 3021.3      | 1.3       | 99.5        | 12.6 (1.5)           | 23.0             |
| 5.8 (23.2)       | 256 | 179.7 | 191.0372 | 2985.7      | .3        | 99.5        | 12.3 (1.5)           | 23.2             |

**Detailed NVMf target statistics**

**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|------------------|-----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 6.0 (24)         | 256 | 173.2 | 184.7075 | 3098.6      | 1.9       | 99.5        | 12.0 (1.5)           | 24.0             |

~~~
Bdev avg read lat, us: 103.604404
Poll group: "nvmf_tgt_poll_group_4"
  Pacer calls, polls, ios: 4872836, 2044828, 2044828
  Pacer poll, io period, us: 24.135 24.135
  Device: "mlx5_0"
    Polls, comps, reqs: 4872836, 2044652, 1022326
    Comps/poll: .419
    Req lat, us: 142.556
    Req lat (total), us: 557.300
    Req states 1: [3854,0,239,0,0,0,0,2,0,0,0,1,0,0]
    Req states 2: [3854,0,239,0,0,0,0,3,0,0,0,0,0,0]
    Req states 3: [3854,0,239,0,0,0,0,2,0,0,0,1,0,0]
    Req lat 1, us: 1625.323
    Req lat 2, us: 790.442
    Req lat 3, us: 620.226
  Device: "mlx5_1"
    Polls, comps, reqs: 4872836, 2045004, 1022502
    Comps/poll: .419
    Req lat, us: 143.145
    Req lat (total), us: 654.536
    Req states 1: [3853,0,240,0,0,0,0,2,0,0,0,1,0,0]
    Req states 2: [3854,0,240,0,0,0,0,1,0,0,0,1,0,0]
    Req states 3: [3853,0,240,0,0,0,0,2,0,0,0,1,0,0]
    Req lat 1, us: 1767.925
    Req lat 2, us: 825.473
    Req lat 3, us: 642.204
Poll group: "nvmf_tgt_poll_group_5"
  Pacer calls, polls, ios: 6452670, 2053886, 2044828
  Pacer poll, io period, us: 24.029 24.135
  Device: "mlx5_0"
    Polls, comps, reqs: 6452670, 2044672, 1022336
    Comps/poll: .316
    Req lat, us: 139.123
    Req lat (total), us: 445.583
    Req states 1: [4094,0,0,0,0,0,0,2,0,0,0,0,0,0]
    Req states 2: [4094,0,0,0,0,0,0,2,0,0,0,0,0,0]
    Req states 3: [4094,0,0,0,0,0,0,1,0,0,0,1,0,0]
    Req lat 1, us: 1234.318
    Req lat 2, us: 617.627
    Req lat 3, us: 491.995
  Device: "mlx5_1"
    Polls, comps, reqs: 6452670, 2045004, 1022502
    Comps/poll: .316
    Req lat, us: 144.824
    Req lat (total), us: 421.538
    Req states 1: [4096,0,0,0,0,0,0,0,0,0,0,0,0,0]
    Req states 2: [4096,0,0,0,0,0,0,0,0,0,0,0,0,0]
    Req states 3: [4096,0,0,0,0,0,0,0,0,0,0,0,0,0]
    Req lat 1, us: 1068.842
    Req lat 2, us: 532.813
    Req lat 3, us: 428.650
Poll group: "nvmf_tgt_poll_group_6"
  Pacer calls, polls, ios: 3795250, 2053408, 2044828
  Pacer poll, io period, us: 24.034 24.135
  Device: "mlx5_0"
    Polls, comps, reqs: 3795250, 2044653, 1022327
    Comps/poll: .538
    Req lat, us: 145.408
    Req lat (total), us: 395.993
    Req states 1: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req states 2: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req states 3: [4094,0,1,0,0,0,0,1,0,0,0,0,0,0]
    Req lat 1, us: 1041.210
    Req lat 2, us: 536.749
    Req lat 3, us: 433.996
  Device: "mlx5_1"
    Polls, comps, reqs: 3795250, 2045025, 1022512
    Comps/poll: .538
    Req lat, us: 150.907
    Req lat (total), us: 364.664
    Req states 1: [4093,0,0,0,0,0,0,2,0,0,0,1,0,0]
    Req states 2: [4093,0,1,0,0,0,0,2,0,0,0,0,0,0]
    Req states 3: [4094,0,0,0,0,0,0,2,0,0,0,0,0,0]
    Req lat 1, us: 792.280
    Req lat 2, us: 420.308
    Req lat 3, us: 347.950
Poll group: "nvmf_tgt_poll_group_7"
  Pacer calls, polls, ios: 3710633, 2053648, 2044829
  Pacer poll, io period, us: 24.031 24.135
  Device: "mlx5_0"
    Polls, comps, reqs: 3710633, 2044653, 1022327
    Comps/poll: .551
    Req lat, us: 145.735
    Req lat (total), us: 316.307
    Req states 1: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req states 2: [4094,0,1,0,0,0,0,1,0,0,0,0,0,0]
    Req states 3: [4094,0,0,0,0,0,0,2,0,0,0,0,0,0]
    Req lat 1, us: 755.305
    Req lat 2, us: 412.073
    Req lat 3, us: 342.117
  Device: "mlx5_1"
    Polls, comps, reqs: 3710633, 2045004, 1022502
    Comps/poll: .551
    Req lat, us: 151.305
    Req lat (total), us: 295.079
    Req states 1: [4094,0,0,0,0,0,0,1,0,0,0,1,0,0]
    Req states 2: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req states 3: [4094,0,0,0,0,0,0,1,0,0,0,1,0,0]
    Req lat 1, us: 573.404
    Req lat 2, us: 328.635
    Req lat 3, us: 280.964
~~~

| Pacer period, us | QD   | BW    | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|------------------|------|-------|---------|-------------|-----------|-------------|----------------------|------------------|
| 6.0 (24)         | 1024 | 166.7 | 184.442 | 12879.6     | 6.9       | 99.5        | 16.6 (2.0)           | 24.0             |

~~~
Bdev avg read lat, us: 104.128774
Poll group: "nvmf_tgt_poll_group_4"
  Pacer calls, polls, ios: 4794301, 2046593, 2046593
  Pacer poll, io period, us: 24.166 24.166
  Device: "mlx5_0"
    Polls, comps, reqs: 4794301, 2046623, 1023344
    Comps/poll: .426
    Req lat, us: 150.220
    Req lat (total), us: 1743.106
    Req states 1: [3650,0,442,0,0,0,0,3,0,0,0,1,0,0]
    Req states 2: [3586,0,507,0,0,0,0,2,0,0,0,1,0,0]
    Req states 3: [3585,0,509,0,0,0,0,2,0,0,0,0,0,0]
    Req lat 1, us: 2671.404
    Req lat 2, us: 2101.214
    Req lat 3, us: 1857.377
  Device: "mlx5_1"
    Polls, comps, reqs: 4794301, 2046717, 1023392
    Comps/poll: .426
    Req lat, us: 151.930
    Req lat (total), us: 1883.873
    Req states 1: [3650,0,442,0,0,0,0,3,0,0,0,1,0,0]
    Req states 2: [3583,0,509,0,0,0,0,4,0,0,0,0,0,0]
    Req states 3: [3583,0,508,0,0,0,0,3,0,0,0,2,0,0]
    Req lat 1, us: 2648.813
    Req lat 2, us: 2078.657
    Req lat 3, us: 1835.856
Poll group: "nvmf_tgt_poll_group_5"
  Pacer calls, polls, ios: 6356892, 2058120, 2047501
  Pacer poll, io period, us: 24.031 24.156
  Device: "mlx5_0"
    Polls, comps, reqs: 6356892, 2047320, 1023596
    Comps/poll: .322
    Req lat, us: 147.322
    Req lat (total), us: 1450.289
    Req states 1: [3967,0,125,0,0,0,0,4,0,0,0,0,0,0]
    Req states 2: [4096,0,0,0,0,0,0,0,0,0,0,0,0,0]
    Req states 3: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req lat 1, us: 2209.865
    Req lat 2, us: 1743.572
    Req lat 3, us: 1543.890
  Device: "mlx5_1"
    Polls, comps, reqs: 6356892, 2047434, 1023653
    Comps/poll: .322
    Req lat, us: 149.319
    Req lat (total), us: 1402.036
    Req states 1: [3967,0,127,0,0,0,0,2,0,0,0,0,0,0]
    Req states 2: [4096,0,0,0,0,0,0,0,0,0,0,0,0,0]
    Req states 3: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req lat 1, us: 2135.836
    Req lat 2, us: 1682.407
    Req lat 3, us: 1488.965
Poll group: "nvmf_tgt_poll_group_6"
  Pacer calls, polls, ios: 3750616, 2057643, 2047273
  Pacer poll, io period, us: 24.037 24.158
  Device: "mlx5_0"
    Polls, comps, reqs: 3750616, 2047160, 1023545
    Comps/poll: .545
    Req lat, us: 152.233
    Req lat (total), us: 1362.108
    Req states 1: [4025,0,67,0,0,0,0,4,0,0,0,0,0,0]
    Req states 2: [4094,0,0,0,0,0,0,1,0,0,0,1,0,0]
    Req states 3: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req lat 1, us: 2067.266
    Req lat 2, us: 1634.155
    Req lat 3, us: 1448.931
  Device: "mlx5_1"
    Polls, comps, reqs: 3750616, 2047254, 1023592
    Comps/poll: .545
    Req lat, us: 154.245
    Req lat (total), us: 1262.596
    Req states 1: [4025,0,69,0,0,0,0,1,0,0,0,1,0,0]
    Req states 2: [4094,0,0,0,0,0,0,2,0,0,0,0,0,0]
    Req states 3: [4095,0,0,0,0,0,0,1,0,0,0,0,0,0]
    Req lat 1, us: 1908.742
    Req lat 2, us: 1508.160
    Req lat 3, us: 1337.482
Poll group: "nvmf_tgt_poll_group_7"
  Pacer calls, polls, ios: 3717748, 2057796, 2047146
  Pacer poll, io period, us: 24.035 24.160
  Device: "mlx5_0"
    Polls, comps, reqs: 3717748, 2047109, 1023551
    Comps/poll: .550
    Req lat, us: 151.734
    Req lat (total), us: 1122.128
    Req states 1: [4086,0,6,0,0,0,0,3,0,0,0,1,0,0]
    Req states 2: [4093,0,1,0,0,0,0,2,0,0,0,0,0,0]
    Req states 3: [4093,0,0,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 1687.666
    Req lat 2, us: 1340.280
    Req lat 3, us: 1191.754
  Device: "mlx5_1"
    Polls, comps, reqs: 3717748, 2047188, 1023589
    Comps/poll: .550
    Req lat, us: 153.754
    Req lat (total), us: 1033.960
    Req states 1: [4084,0,10,0,0,0,0,2,0,0,0,0,0,0]
    Req states 2: [4094,0,1,0,0,0,0,1,0,0,0,0,0,0]
    Req states 3: [4094,0,0,0,0,0,0,2,0,0,0,0,0,0]
    Req lat 1, us: 1550.188
    Req lat 2, us: 1231.314
    Req lat 3, us: 1095.500
~~~

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 6.0 (24)         | 2048 | 124.1 | 130.1644 | 18674.8     | 6.4       | 60.4        | 983.3 (122.9)        | 24.1             |

~~~
Bdev avg read lat, us: 103.782670
Poll group: "nvmf_tgt_poll_group_4"
  Pacer calls, polls, ios: 5759266, 2309737, 1656661
  Pacer poll, io period, us: 24.457 34.098
  Device: "mlx5_0"
    Polls, comps, reqs: 5759266, 1656734, 828384
    Comps/poll: .287
    Req lat, us: 11248.549
    Req lat (total), us: 5059.107
    Req states 1: [3927,0,0,0,0,0,0,0,0,0,0,169,0,0]
    Req states 2: [3919,0,4,0,0,0,0,0,0,0,0,173,0,0]
    Req states 3: [3893,0,3,0,0,0,0,1,0,0,0,199,0,0]
    Req lat 1, us: 3577.384
    Req lat 2, us: 4364.561
    Req lat 3, us: 4958.596
  Device: "mlx5_1"
    Polls, comps, reqs: 5759266, 1656520, 828278
    Comps/poll: .287
    Req lat, us: 11494.881
    Req lat (total), us: 5204.904
    Req states 1: [3931,0,2,0,0,0,0,0,0,0,0,163,0,0]
    Req states 2: [3945,0,0,0,0,0,0,4,0,0,0,147,0,0]
    Req states 3: [3895,0,0,0,0,0,0,3,0,0,0,198,0,0]
    Req lat 1, us: 3671.092
    Req lat 2, us: 4540.204
    Req lat 3, us: 5086.540
Poll group: "nvmf_tgt_poll_group_5"
  Pacer calls, polls, ios: 7156952, 2343020, 1657086
  Pacer poll, io period, us: 24.109 34.089
  Device: "mlx5_0"
    Polls, comps, reqs: 7156952, 1657279, 828605
    Comps/poll: .231
    Req lat, us: 7680.340
    Req lat (total), us: 3946.078
    Req states 1: [3931,0,2,0,0,0,0,2,0,0,0,161,0,0]
    Req states 2: [4020,0,0,0,0,0,0,3,0,0,0,73,0,0]
    Req states 3: [4000,0,1,0,0,0,0,4,0,0,0,91,0,0]
    Req lat 1, us: 3129.554
    Req lat 2, us: 3831.089
    Req lat 3, us: 3949.036
  Device: "mlx5_1"
    Polls, comps, reqs: 7156952, 1656936, 828491
    Comps/poll: .231
    Req lat, us: 10868.115
    Req lat (total), us: 4557.572
    Req states 1: [3945,0,0,0,0,0,0,2,0,0,0,149,0,0]
    Req states 2: [3953,0,1,0,0,0,0,2,0,0,0,140,0,0]
    Req states 3: [3899,0,0,0,0,0,0,1,0,0,0,196,0,0]
    Req lat 1, us: 3055.970
    Req lat 2, us: 3939.255
    Req lat 3, us: 4469.587
Poll group: "nvmf_tgt_poll_group_6"
  Pacer calls, polls, ios: 4333445, 2338364, 1656791
  Pacer poll, io period, us: 24.157 34.095
  Device: "mlx5_0"
    Polls, comps, reqs: 4333445, 1656915, 828424
    Comps/poll: .382
    Req lat, us: 4363.234
    Req lat (total), us: 3178.605
    Req states 1: [3936,0,0,0,0,0,0,3,0,0,0,157,0,0]
    Req states 2: [4042,0,0,0,0,0,0,3,0,0,0,51,0,0]
    Req states 3: [4003,0,0,0,0,0,0,0,0,0,0,93,0,0]
    Req lat 1, us: 2913.997
    Req lat 2, us: 3051.705
    Req lat 3, us: 3174.923
  Device: "mlx5_1"
    Polls, comps, reqs: 4333445, 1656807, 828375
    Comps/poll: .382
    Req lat, us: 6380.997
    Req lat (total), us: 3406.706
    Req states 1: [3944,0,4,0,0,0,0,1,0,0,0,147,0,0]
    Req states 2: [4061,0,3,0,0,0,0,2,0,0,0,30,0,0]
    Req states 3: [4001,0,0,0,0,0,0,5,0,0,0,90,0,0]
    Req lat 1, us: 2752.034
    Req lat 2, us: 3352.287
    Req lat 3, us: 3408.564
Poll group: "nvmf_tgt_poll_group_7"
  Pacer calls, polls, ios: 4323935, 2339077, 1656652
  Pacer poll, io period, us: 24.150 34.098
  Device: "mlx5_0"
    Polls, comps, reqs: 4323935, 1656757, 828376
    Comps/poll: .383
    Req lat, us: 3034.447
    Req lat (total), us: 2657.651
    Req states 1: [4001,0,1,0,0,0,0,2,0,0,0,92,0,0]
    Req states 2: [4040,0,2,0,0,0,0,2,0,0,0,52,0,0]
    Req states 3: [4006,0,0,0,0,0,0,3,0,0,0,87,0,0]
    Req lat 1, us: 2571.604
    Req lat 2, us: 2527.954
    Req lat 3, us: 2654.929
  Device: "mlx5_1"
    Polls, comps, reqs: 4323935, 1656615, 828279
    Comps/poll: .383
    Req lat, us: 4064.823
    Req lat (total), us: 2704.602
    Req states 1: [3949,0,0,0,0,0,0,2,0,0,0,145,0,0]
    Req states 2: [4074,0,0,0,0,0,0,0,0,0,0,22,0,0]
    Req states 3: [4006,0,4,0,0,0,0,0,0,0,0,86,0,0]
    Req lat 1, us: 2396.637
    Req lat 2, us: 2635.818
    Req lat 3, us: 2698.415
~~~
