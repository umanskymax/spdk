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
sudo ./install-$HOSTNAME/bin/spdk_tgt -c ./io_pacing/configs/nvmf_nvme.conf -m 0xFFFF
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

## Test setups

### Setup 1 - spdk-tgt-bw-03

**Target**: `spdk-tgt-bw-03` connected with 2 ports to switch sw-ceph02

**Disks**: 16 `INTEL SSDPE21D280GA`

**Initiator 1**: `r-dcs79` connected to switch sw-ceph02

**Initiator 2**: `spdk03` connected to switch sw-spdk01

### Setup 2 - swx-bw-07

**Target**: `swx-bw-07` connected with 2 ports to switch sw-spdk01

**Disks**: 16 `SAMSUNG MZWLL1T6HAJQ-00005`

**Initiator 1**: `spdk04` connected to switch sw-spdk01

**Initiator 2**: `spdk05` connected to switch sw-spdk01

## Results

Results for Samsung disks: [samsung_results.md](samsung_results.md)

Results for Intel disks write flow: [intel_write.md](intel_write.md)

Results for Intel disks small IOs: [intel_small.md](intel_small.md)

| Test #              | IO pacing            | Disks                   | Description                                  |
|---------------------|----------------------|-------------------------|----------------------------------------------|
| [Test 1](#test-1)   | none                 | 1 Null                  | Basic test                                   |
| [Test 2](#test-2)   | none                 | 16 Null                 | Basic test                                   |
| [Test 3](#test-3)   | none                 | 16 NVMe                 | Basic test                                   |
| [Test 4](#test-4)   | NumSharedBuffers     | 16 Null                 | Basic test                                   |
| [Test 5](#test-5)   | NumSharedBuffers     | 16 NVMe                 | Basic test                                   |
| [Test 6](#test-6)   | NumSharedBuffers     | 16 NVMe                 | Stability test: multiple same test runs      |
| [Test 7](#test-7)   | NumSharedBuffers     | 16 NVMe                 | Different number of target cores             |
| [Test 8](#test-8)   | NumSharedBuffers     | 16 NVMe                 | Different buffer cache size                  |
| [Test 9](#test-9)   | NumSharedBuffers     | 16 NVMe                 | Different number of buffers, 16 target cores |
| [Test 10](#test-10) | NumSharedBuffers     | 16 NVMe                 | Different number of buffers, 4 target cores  |
| [Test 11](#test-11) | NumSharedBuffers     | 16 NVMe, split 3, delay | No limit of IO depth for delay devices       |
| [Test 12](#test-12) | NumSharedBuffers     | 16 NVMe, split 3, delay | Control IO depth for delay devices           |
| [Test 13](#test-13) | N/A                  | 16 NVMe, split 3, delay | Test disk latencies                          |
| [Test 14](#test-14) | Rate based, adaptive | 16 NVMe                 | Basic test                                   |
| [Test 15](#test-15) | Rate based, fixed    | 16 NVMe                 | Basic test                                   |
| [Test 16](#test-16) | Rate based, adaptive | 16 NVMe, split 3, delay | Test 12 with IO pacer                        |

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

Basic test with rate based IO pacing. Adaptive rate IO pacer. FIO with 8 jobs.

**IO pacing**: `Rate based`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF0 (4 cores)

Adaptive mechanism works as follows. IO pacer measures average IO
period, i.e. how often IOs leave the pacer and go to buffer allocation
and disk. Every tuning period (10 ms) pacer period is adjusted to
match the measured IO period minus 1 us. Adjustments to pacer period
are done in steps (1 us). For example, if current pacer period is 25
us and measured IO period is 35 us, pacer period will be set to 26
us. This works in both directions, up and down. Adjustments to pacer
period are limited by a range with lower bound being the configured
pacer period value (the first column in the table below) and upper
bound being twice the lower bound.

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 5.6 (22.4)       | 256  | 129.0 | 118.9491 | 4159.1      | 1.2       | 87.6        | 257.3 (32.1)         |
| 5.6 (22.4)       | 1024 | 116.7 | 126.7461 | 17978.0     | 1.2       | 99.4        | 1026.3 (128.2)       |
| 5.6 (22.4)       | 2048 | 119.2 | 138.0614 | 35387.6     | 1.4       | 63.2        | 1037.0 (129.6)       |
| 5.65 (22.6)      | 256  | 129.7 | 124.9634 | 4136.2      | 1.3       | 92.9        | 98.3 (12.2)          |
| 5.65 (22.6)      | 1024 | 119.3 | 110.5019 | 17997.6     | 1.2       | 50.6        | 684.6 (85.5)         |
| 5.65 (22.6)      | 2048 | 120.4 | 111.7765 | 34830.7     | 1.5       | 50.8        | 1088.6 (136.0)       |
| 5.675 (22.7)     | 256  | 174.6 | 195.3761 | 3073.1      | 1.3       | 53.8        | 27.6 (3.4)           |
| 5.675 (22.7)     | 1024 | 130.7 | 115.8018 | 16421.1     | 1.8       | 52.5        | 1025.0 (128.1)       |
| 5.675 (22.7)     | 2048 | 156.5 | 195.073  | 27471.3     | 1.9       | 99.3        | 27.3 (3.4)           |
| 5.7 (22.8)       | 256  | 183.0 | 194.6647 | 2932.2      | 0         | 99.5        | 25.6 (3.2)           |
| 5.7 (22.8)       | 1024 | 159.8 | 185.5446 | 13439.6     | 2.0       | 99.4        | 36.0 (4.5)           |
| 5.7 (22.8)       | 2048 | 182.7 | 194.1884 | 23501.3     | 0         | 99.3        | 27.0 (3.3)           |
| 5.725 (22.9)     | 256  | 182.3 | 193.7391 | 2944.4      | 0         | 99.5        | 25.6 (3.2)           |
| 5.725 (22.9)     | 1024 | 182.1 | 193.4434 | 11791.5     | 0         | 99.4        | 25.6 (3.2)           |
| 5.725 (22.9)     | 2048 | 169.2 | 193.2842 | 25395.9     | 1.3       | 99.1        | 32.3 (4.0)           |
| 5.75 (23)        | 256  | 181.5 | 192.9044 | 2957.2      | 0         | 99.5        | 24.3 (3.0)           |
| 5.75 (23)        | 1024 | 181.3 | 192.6004 | 11839.8     | 0         | 99.4        | 26.6 (3.3)           |
| 5.75 (23)        | 2048 | 173.6 | 192.5688 | 24150.8     | .7        | 99.0        | 30.0 (3.7)           |
| 5.775 (23.1)     | 256  | 180.7 | 192.1829 | 2969.0      | 0         | 99.5        | 25.0 (3.1)           |
| 5.775 (23.1)     | 1024 | 171.1 | 191.9538 | 12370.6     | .8        | 66.7        | 26.3 (3.2)           |
| 5.775 (23.1)     | 2048 | 176.6 | 191.7225 | 23859.1     | 0         | 99.3        | 32.0 (4.0)           |
| 5.8 (23.2)       | 256  | 179.9 | 191.2576 | 2982.5      | 0         | 99.5        | 24.3 (3.0)           |
| 5.8 (23.2)       | 1024 | 179.8 | 191.0265 | 11943.7     | 0         | 99.4        | 24.0 (3.0)           |
| 5.8 (23.2)       | 2048 | 179.7 | 190.9277 | 23895.5     | 0         | 99.4        | 28.0 (3.5)           |
| 6 (24)           | 256  | 174.2 | 185.1402 | 3081.3      | .1        | 99.5        | 23.0 (2.8)           |
| 6 (24)           | 1024 | 174.0 | 184.9201 | 12338.7     | 0         | 99.5        | 22.3 (2.7)           |
| 6 (24)           | 2048 | 174.0 | 184.6929 | 24680.9     | .1        | 99.4        | 22.3 (2.7)           |

**Detailed NVMf target statistics**

**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------------------|-----|-------|----------|-------------|-----------|-------------|----------------------|
| 5.7 (22.8)       | 256 | 166.1 | 194.3685 | 25902.5     | 1.7       | 99.3        | 27.3 (3.4)           |

~~~
CPU mask 0xF0, num cores 4, IO pacer period 5700, adjusted period 22800
Bdev avg read lat, us: 247.819538
Poll group: "nvmf_tgt_poll_group_4"
  Pacer calls, polls, ios: 5158146, 1674906, 1643446
  Pacer poll, io period, us: 25.026 25.505
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 5158146, 1715921, 857960
    Comps/poll: .332
    Req lat, us: 4130.835
    Req lat (total), us: 3728.752
    Req states 1: [3584,0,509,0,0,0,0,2,0,0,0,1,0,0]
    Req states 2: [3585,0,509,0,0,0,0,0,0,0,0,2,0,0]
    Req states 3: [3585,0,508,0,0,0,0,1,0,0,0,2,0,0]
    Req lat 1, us: 3291.641
    Req lat 2, us: 5243.603
    Req lat 3, us: 3867.714
  Device: "mlx5_1"
    Polls, comps, reqs: 5158146, 1570970, 785485
    Comps/poll: .304
    Req lat, us: 3997.106
    Req lat (total), us: 3762.826
    Req states 1: [3584,0,508,0,0,0,0,2,0,0,0,2,0,0]
    Req states 2: [3584,0,505,0,0,0,0,4,0,0,0,3,0,0]
    Req states 3: [3584,0,508,0,0,0,0,3,0,0,0,1,0,0]
    Req lat 1, us: 2260.442
    Req lat 2, us: 4880.427
    Req lat 3, us: 3465.314
Poll group: "nvmf_tgt_poll_group_5"
  Pacer calls, polls, ios: 4612768, 1685853, 1643446
  Pacer poll, io period, us: 24.863 25.505
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 4612768, 1715941, 857970
    Comps/poll: .371
    Req lat, us: 342.025
    Req lat (total), us: 592.427
    Req states 1: [4090,0,1,0,0,0,0,5,0,0,0,0,0,0]
    Req states 2: [4091,0,2,0,0,0,0,2,0,0,0,1,0,0]
    Req states 3: [4091,0,1,0,0,0,0,4,0,0,0,0,0,0]
    Req lat 1, us: 1202.860
    Req lat 2, us: 801.954
    Req lat 3, us: 612.220
  Device: "mlx5_1"
    Polls, comps, reqs: 4612768, 1570968, 785484
    Comps/poll: .340
    Req lat, us: 642.176
    Req lat (total), us: 476.522
    Req states 1: [4092,0,2,0,0,0,0,1,0,0,0,1,0,0]
    Req states 2: [4092,0,0,0,0,0,0,3,0,0,0,1,0,0]
    Req states 3: [4092,0,1,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 110.647
    Req lat 2, us: 644.583
    Req lat 3, us: 479.246
Poll group: "nvmf_tgt_poll_group_6"
  Pacer calls, polls, ios: 2967952, 1688370, 1654105
  Pacer poll, io period, us: 24.826 25.340
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 2967952, 1726312, 863156
    Comps/poll: .581
    Req lat, us: 4122.330
    Req lat (total), us: 3984.763
    Req states 1: [3584,0,510,0,0,0,0,2,0,0,0,0,0,0]
    Req states 2: [3584,0,508,0,0,0,0,4,0,0,0,0,0,0]
    Req states 3: [3584,0,509,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 4169.757
    Req lat 2, us: 5629.531
    Req lat 3, us: 4136.811
  Device: "mlx5_1"
    Polls, comps, reqs: 2967952, 1581914, 790957
    Comps/poll: .532
    Req lat, us: 3749.652
    Req lat (total), us: 4127.519
    Req states 1: [3583,0,508,0,0,0,0,4,0,0,0,1,0,0]
    Req states 2: [3583,0,509,0,0,0,0,2,0,0,0,2,0,0]
    Req states 3: [3583,0,509,0,0,0,0,3,0,0,0,1,0,0]
    Req lat 1, us: 4129.940
    Req lat 2, us: 5530.674
    Req lat 3, us: 3853.771
Poll group: "nvmf_tgt_poll_group_7"
  Pacer calls, polls, ios: 2884457, 1688553, 1653954
  Pacer poll, io period, us: 24.824 25.343
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 2884457, 1726190, 863115
    Comps/poll: .598
    Req lat, us: 2125.312
    Req lat (total), us: 2818.057
    Req states 1: [3817,0,276,0,0,0,0,1,0,0,0,2,0,0]
    Req states 2: [3728,0,364,0,0,0,0,4,0,0,0,0,0,0]
    Req states 3: [3777,0,316,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 4743.063
    Req lat 2, us: 3971.255
    Req lat 3, us: 2924.934
  Device: "mlx5_1"
    Polls, comps, reqs: 2884457, 1581793, 790914
    Comps/poll: .548
    Req lat, us: 2587.222
    Req lat (total), us: 2906.083
    Req states 1: [3825,0,267,0,0,0,0,4,0,0,0,0,0,0]
    Req states 2: [3737,0,355,0,0,0,0,1,0,0,0,3,0,0]
    Req states 3: [3790,0,302,0,0,0,0,2,0,0,0,2,0,0]
    Req lat 1, us: 3580.901
    Req lat 2, us: 4094.080
    Req lat 3, us: 2859.373

~~~

**IO pacer log**

~~~
io_pacer.c: 213:spdk_io_pacer_create: *NOTICE*: Created IO pacer 0xaaaae1ee2490: period_ns 22800, period_ticks 3562, max_queues 0
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 23796 ns, new period 3718 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 33780 ns, new period 5278 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 43764 ns, new period 6838 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 260:spdk_io_pacer_create_queue: *NOTICE*: Allocated more queues for IO pacer 0xaaaae1ee2490: max_queues 32
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 0000000100000009
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 000000010000000d
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 0000000100000005
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 0000000100000001
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2287, io period 43725 ns, new period 42676 ns, new period 6668 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2433, io period 41101 ns, new period 40101 ns, new period 6265 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3171, io period 31535 ns, new period 30535 ns, new period 4771 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4286, io period 23331 ns, new period 22331 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4347, io period 23004 ns, new period 22004 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4353, io period 22972 ns, new period 21972 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4357, io period 22951 ns, new period 21951 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4358, io period 22946 ns, new period 21946 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4352, io period 22977 ns, new period 21977 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4360, io period 22935 ns, new period 21935 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3576, io period 27964 ns, new period 26964 ns, new period 4213 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3565, io period 28050 ns, new period 27050 ns, new period 4226 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3135, io period 31897 ns, new period 28155 ns, new period 4399 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4278, io period 23375 ns, new period 22375 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4333, io period 23078 ns, new period 22078 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4334, io period 23073 ns, new period 22073 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4356, io period 22956 ns, new period 21956 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2189, io period 45682 ns, new period 26792 ns, new period 4186 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2175, io period 45977 ns, new period 36776 ns, new period 5746 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2179, io period 45892 ns, new period 44892 ns, new period 7014 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2390, io period 41841 ns, new period 40841 ns, new period 6381 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3101, io period 32247 ns, new period 31247 ns, new period 4882 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4279, io period 23369 ns, new period 22369 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2840, io period 35211 ns, new period 26792 ns, new period 4186 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2927, io period 34164 ns, new period 33164 ns, new period 5181 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2975, io period 33613 ns, new period 28699 ns, new period 4484 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2693, io period 37133 ns, new period 36133 ns, new period 5645 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2542, io period 39339 ns, new period 38339 ns, new period 5990 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3326, io period 30066 ns, new period 29066 ns, new period 4541 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4328, io period 23105 ns, new period 22105 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4332, io period 23084 ns, new period 22084 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4347, io period 23004 ns, new period 22004 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4339, io period 23046 ns, new period 22046 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4341, io period 23036 ns, new period 22036 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4345, io period 23014 ns, new period 22014 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4321, io period 23142 ns, new period 22142 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4342, io period 23030 ns, new period 22030 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4348, io period 22999 ns, new period 21999 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4352, io period 22977 ns, new period 21977 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4344, io period 23020 ns, new period 22020 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4339, io period 23046 ns, new period 22046 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4348, io period 22999 ns, new period 21999 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4353, io period 22972 ns, new period 21972 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4358, io period 22946 ns, new period 21946 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4335, io period 23068 ns, new period 22068 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4325, io period 23121 ns, new period 22121 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4357, io period 22951 ns, new period 21951 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4328, io period 23105 ns, new period 22105 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4335, io period 23068 ns, new period 22068 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4357, io period 22951 ns, new period 21951 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4318, io period 23158 ns, new period 22158 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4347, io period 23004 ns, new period 22004 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4335, io period 23068 ns, new period 22068 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4353, io period 22972 ns, new period 21972 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4334, io period 23073 ns, new period 22073 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2204, io period 45372 ns, new period 28788 ns, new period 4498 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 38772 ns, new period 6058 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 237:spdk_io_pacer_destroy: *NOTICE*: Destroyed IO pacer 0xaaaae1ee2490
~~~

### Test 15

Basic test with rate based IO pacing. Tuner disabled (fixed rate).

**IO pacing**: `Rate based`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 5.6 (22.4)       | 256  | 160.0 | 180.231  | 3357.1      | 6.7       | 74.0        | 367.0 (45.8)         | 22.5             |
| 5.65 (22.6)      | 256  | 178.1 | 195.7152 | 3013.5      | 4.3       | 99.5        | 129.6 (16.2)         | 22.7             |
| 5.675 (22.7)     | 256  | 183.5 | 195.0755 | 2924.5      | .1        | 99.5        | 25.0 (3.1)           | 22.7             |
| 5.7 (22.8)       | 256  | 182.8 | 194.2888 | 2936.3      | .2        | 99.5        | 23.6 (2.9)           | 22.8             |
| 5.725 (22.9)     | 256  | 181.9 | 193.3365 | 2949.9      | .2        | 99.5        | 24.3 (3.0)           | 22.9             |
| 5.75 (23)        | 256  | 181.2 | 192.5431 | 2961.5      | .2        | 99.5        | 22.6 (2.8)           | 23.0             |
| 5.8 (23.2)       | 256  | 179.7 | 190.9718 | 2986.4      | .3        | 99.5        | 22.6 (2.8)           | 23.2             |
| 6 (24)           | 256  | 169.8 | 184.7295 | 3163.1      | 1.0       | 99.5        | 183.6 (22.9)         | 24.0             |
| 5.6 (22.4)       | 1024 | 156.1 | 170.3481 | 11276.8     | 5.7       | 76.7        | 596.0 (74.5)         | 22.5             |
| 5.65 (22.6)      | 1024 | 154.2 | 171.9468 | 11708.2     | 5.4       | 73.9        | 588.6 (73.5)         | 22.7             |
| 5.675 (22.7)     | 1024 | 141.7 | 165.9734 | 10886.6     | 9.2       | 58.9        | 572.6 (71.5)         | 22.8             |
| 5.7 (22.8)       | 1024 | 160.9 | 148.8915 | 12118.0     | 11.1      | 67.7        | 255.6 (31.9)         | 22.8             |
| 5.725 (22.9)     | 1024 | 137.9 | 124.2786 | 11597.4     | 10.7      | 60.5        | 758.0 (94.7)         | 23.0             |
| 5.75 (23)        | 1024 | 152.6 | 192.9411 | 11941.0     | 13.8      | 99.2        | 428.0 (53.5)         | 23.0             |
| 5.8 (23.2)       | 1024 | 157.3 | 134.1641 | 12723.2     | 11.6      | 65.3        | 28.3 (3.5)           | 23.2             |
| 6 (24)           | 1024 | 173.7 | 184.5522 | 12364.5     | .5        | 99.5        | 22.3 (2.7)           | 24.0             |

### Test 16

IO pacer period 5750, adjusted period 23000, num delay 16
| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 169.6 | 191.0841 | 12737.7     | 3.4       | 99.4        | 19.0 (2.3)           | 26.7             |
| 2  | 175.5 | 190.674  | 12290.3     | 1.3       | 99.4        | 21.0 (2.6)           | 26.2             |
| 4  | 175.1 | 190.9027 | 12369.1     | 2.5       | 99.3        | 22.0 (2.7)           | 26.1             |
| 8  | 179.4 | 190.7852 | 12162.6     | .9        | 98.9        | 30.6 (3.8)           | 25.9             |
| 16 | 179.2 | 190.2876 | 12363.9     | 1.0       | 97.3        | 38.6 (4.8)           | 25.8             |
| 32 | 123.5 | 114.2105 | 18478.2     | 4.9       | 38.4        | 1293.3 (161.6)       | 27.0             |
| 64 | 123.1 | 110.4748 | 19634.4     | 5.1       | 30.6        | 1319.3 (164.9)       | 28.1             |

IO pacer period 5750, adjusted period 23000, num delay 32
| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 175.9 | 191.2743 | 12239.3     | 3.1       | 99.4        | 16.0 (2.0)           | 25.5             |
| 2  | 179.6 | 190.8678 | 12006.9     | .2        | 99.4        | 23.0 (2.8)           | 25.4             |
| 4  | 173.5 | 190.4886 | 12486.1     | .2        | 99.1        | 29.0 (3.6)           | 25.6             |
| 8  | 178.6 | 189.9393 | 12211.3     | .3        | 97.8        | 41.0 (5.1)           | 25.5             |
| 16 | 105.0 | 110.8799 | 21078.7     | 2.2       | 44.3        | 1336.3 (167.0)       | 27.6             |
| 32 | 104.6 | 110.4205 | 21820.5     | 1.9       | 34.1        | 1379.6 (172.4)       | 29.2             |
| 64 | 104.5 | 110.3843 | 23120.3     | 1.5       | 30.0        | 1079.0 (134.8)       | 30.4             |

IO pacer period 6000, adjusted period 24000, num delay 16
| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 163.5 | 183.6816 | 13211.4     | 4.2       | 92.7        | 17.0 (2.1)           | 27.2             |
| 2  | 172.3 | 183.4786 | 12484.2     | .8        | 99.4        | 19.6 (2.4)           | 26.8             |
| 4  | 172.6 | 183.2886 | 12542.7     | .6        | 99.4        | 20.3 (2.5)           | 26.7             |
| 8  | 172.5 | 183.1826 | 12648.9     | 1.1       | 99.1        | 25.3 (3.1)           | 26.6             |
| 16 | 172.3 | 183.0874 | 12856.7     | 1.0       | 97.3        | 38.6 (4.8)           | 26.6             |
| 32 | 154.1 | 182.1496 | 14811.4     | 4.7       | 90.7        | 714.0 (89.2)         | 27.2             |
| 64 | 171.2 | 182.0205 | 14119.8     | .5        | 88.1        | 52.0 (6.5)           | 27.1             |

IO pacer period 6000, adjusted period 24000, num delay 32
| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 172.5 | 183.4912 | 12471.7     | .3        | 99.4        | 16.3 (2.0)           | 26.1             |
| 2  | 172.4 | 183.0833 | 12503.9     | .3        | 99.3        | 24.0 (3.0)           | 26.3             |
| 4  | 166.5 | 98.1667  | 13021.3     | 3.4       | 99.1        | 28.6 (3.5)           | 26.5             |
| 8  | 171.8 | 182.5819 | 12699.0     | .4        | 96.4        | 37.0 (4.6)           | 26.5             |
| 16 | 137.2 | 181.5809 | 16143.7     | 7.6       | 89.5        | 588.6 (73.5)         | 27.7             |
| 32 | 105.5 | 111.3706 | 19815.1     | 2.0       | 35.0        | 897.6 (112.2)        | 29.3             |
| 64 | 104.3 | 110.2806 | 23161.0     | 1.5       | 29.6        | 1436.6 (179.5)       | 30.5             |

### Test 18

Mixed IO sizes.

CPU mask 0xFFFF, IO pacer period 5700, adjusted period 91200

| IO size        | Pacer threshold | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----------------|-----------------|-----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 128k           | 0               | 256 | 165.5 | 179.1065 | 25953.1     | 1.6       | 98.0        | 133.3 (1.0)          | 122.0            |
| 128k/80:4k/20  | 0               | 256 | 100.2 | 108.775  | 33997.6     | .3        | 56.3        | 10333.3 (80.7)       | 145.2            |
| 128k/20:4k/80  | 0               | 256 | 100.8 | 107.7723 | 9572.5      | .4        | 51.1        | 3940.6 (30.7)        | 112.3            |
| 128k/80:16k/20 | 0               | 256 | 100.0 | 108.4131 | 34749.5     | .4        | 59.6        | 9684.6 (75.6)        | 148.6            |
| 128k/20:16k/80 | 0               | 256 | 100.1 | 108.4904 | 12688.9     | .4        | 60.3        | 5081.3 (39.6)        | 114.7            |
| 128k           | 4096            | 256 | 156.8 | 194.7037 | 27406.6     | 2.1       | 98.8        | 144.0 (1.1)          | 123.1            |
| 128k/80:4k/20  | 4096            | 256 | 133.1 | 108.4132 | 26046.5     | 2.2       | 83.4        | 161.0 (1.2)          | 140.9            |
| 128k/20:4k/80  | 4096            | 256 | 109.3 | 105.5914 | 8624.3      | 1.5       | 57.4        | 3400.6 (26.5)        | 165.8            |
| 128k/80:16k/20 | 4096            | 256 | 102.2 | 107.614  | 34653.3     | .4        | 62.0        | 10288.0 (80.3)       | 148.9            |
| 128k/20:16k/80 | 4096            | 256 | 101.8 | 107.606  | 12640.6     | .3        | 60.3        | 5195.3 (40.5)        | 113.6            |
| 128k           | 16384           | 256 | 164.7 | 194.001  | 26127.0     | 1.7       | 88.5        | 138.6 (1.0)          | 122.2            |
| 128k/80:4k/20  | 16384           | 256 | 133.6 | 186.864  | 25470.5     | 2.2       | 74.2        | 96.0 (.7)            | 135.6            |
| 128k/20:4k/80  | 16384           | 256 | 110.6 | 176.8402 | 8507.0      | 1.6       | 61.3        | 165.0 (1.2)          | 165.9            |
| 128k/80:16k/20 | 16384           | 256 | 133.6 | 112.1761 | 26637.2     | 2.2       | 93.8        | 148.0 (1.1)          | 138.7            |
| 128k/20:16k/80 | 16384           | 256 | 99.2  | 108.023  | 12761.3     | .4        | 62.4        | 4772.0 (37.2)        | 184.2            |
