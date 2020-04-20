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

| Test #              | IO pacing        | Disks                     | Description                                  |
|---------------------|------------------|---------------------------|----------------------------------------------|
| [Test 1](#test-1)   | none             | 1 Null                    | Basic test                                   |
| [Test 2](#test-2)   | none             | 16 Null                   | Basic test                                   |
| [Test 3](#test-3)   | none             | 16 NVMe                   | Basic test                                   |
| [Test 4](#test-4)   | NumSharedBuffers | 16 Null                   | Basic test                                   |
| [Test 5](#test-5)   | NumSharedBuffers | 16 NVMe                   | Basic test                                   |
| [Test 6](#test-6)   | NumSharedBuffers | 16 NVMe                   | Stability test: multiple same test runs      |
| [Test 7](#test-7)   | NumSharedBuffers | 16 NVMe                   | Different number of target cores             |
| [Test 8](#test-8)   | NumSharedBuffers | 16 NVMe                   | Different buffer cache size                  |
| [Test 9](#test-9)   | NumSharedBuffers | 16 NVMe                   | Different number of buffers, 16 target cores |
| [Test 10](#test-10) | NumSharedBuffers | 16 NVMe                   | Different number of buffers, 4 target cores  |
| [Test 11](#test-11) | NumSharedBuffers | 16 NVMe, split 3, delay   | No limit of IO depth for delay devices       |
| [Test 12](#test-12) | NumSharedBuffers | 16 NVMe, split 3, delay   | Control IO depthfor delay devices            |
| [Test 13](#test-13) | N/A              | 16 NVMe, split 3, delay   | Test disk latencies                          |

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

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|-------|----------|-------------|-----------|-------------|
| 16  | 174.3 | 185.7256 | 192.0       | 1.8       | 99.5        |
| 32  | 184.8 | 196.3077 | 362.6       | .2        | 98.6        |
| 36  | 184.8 | 196.3322 | 407.9       | .1        | 96.7        |
| 40  | 184.8 | 196.3332 | 453.3       | .1        | 91.3        |
| 44  | 182.9 | 196.2461 | 503.9       | .8        | 82.9        |
| 48  | 176.5 | 181.7952 | 569.6       | 1.9       | 80.0        |
| 64  | 168.2 | 180.9102 | 797.2       | 2.3       | 76.0        |
| 128 | 166.7 | 180.8241 | 1609.2      | 3.4       | 65.6        |
| 256 | 159.9 | 161.1326 | 3356.1      | 4.7       | 73.0        |

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

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 169.4      | 181.0699   | 98.5            | 7.8
16         | 176.9      | 192.2888   | 189.1           | 9.8
32         | 179.0      | 194.0834   | 374.2           | 7.9
64         | 179.1      | 194.9661   | 748.5           | 7.5
128        | 182.7      | 195.3542   | 1468.5          | 3.8
256        | 183.4      | 196.2781   | 2925.4          | 3.0
~~~

**Initiator**: `fio+kernel 8 jobs`

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

~~~
QD         | BW         | WIRE BW
8          | 96.1       | 101.7948
16         | 167.9      | 179.8046
32         | 182.3      | 193.8036
64         | 182.7      | 194.3911
128        | 182.8      | 195.7273
256        | 183.1      | 194.1423
~~~

**Initiator**: `fio+kernel 8 jobs`

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

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
32         | 176.9      | 192.2347   | 378.7           | 9.8
32         | 177.0      | 192.4698   | 378.5           | 10.0
32         | 176.9      | 192.2402   | 378.5           | 9.9
32         | 177.1      | 192.4382   | 378.3           | 9.8
32         | 180.6      | 192.3668   | 370.9           | 6.8
32         | 180.5      | 192.3641   | 371.2           | 6.8
32         | 180.6      | 193.0917   | 370.9           | 6.9
32         | 180.5      | 192.1806   | 371.1           | 6.6
32         | 180.6      | 192.4038   | 370.8           | 6.5
32         | 180.5      | 192.7743   | 371.0           | 6.7
64         | 181.7      | 193.5087   | 737.9           | 5.3
64         | 181.0      | 194.7834   | 740.8           | 6.0
64         | 180.9      | 193.7332   | 741.0           | 5.9
64         | 180.4      | 193.4756   | 743.1           | 6.5
64         | 180.4      | 189.1203   | 743.0           | 6.1
64         | 180.2      | 193.1752   | 743.9           | 6.4
64         | 180.8      | 193.6194   | 741.7           | 6.0
64         | 181.1      | 194.0841   | 740.2           | 5.8
64         | 181.6      | 194.0415   | 738.4           | 5.3
64         | 181.1      | 194.9034   | 740.4           | 6.0
128        | 180.7      | 193.9188   | 1484.3          | 5.8
128        | 181.4      | 194.375    | 1478.8          | 5.6
128        | 181.6      | 193.8817   | 1477.5          | 5.4
128        | 181.6      | 193.9154   | 1476.9          | 5.1
128        | 169.5      | 193.7034   | 1582.1          | 8.1
128        | 181.6      | 193.469    | 1477.0          | 5.1
128        | 181.8      | 195.2503   | 1475.3          | 4.7
128        | 181.4      | 194.1011   | 1478.8          | 5.5
128        | 181.0      | 194.4087   | 1482.4          | 5.8
128        | 181.6      | 194.3961   | 1476.9          | 5.4
256        | 182.4      | 195.7237   | 2941.4          | 4.0
256        | 182.4      | 195.8498   | 2941.3          | 3.8
256        | 182.6      | 195.7576   | 2938.3          | 3.5
256        | 182.5      | 195.8429   | 2940.7          | 3.8
256        | 182.9      | 196.0517   | 2934.8          | 3.4
256        | 182.3      | 195.6491   | 2943.9          | 4.2
256        | 181.5      | 195.4919   | 2955.9          | 4.6
256        | 182.2      | 195.6533   | 2944.5          | 3.9
256        | 182.8      | 195.5254   | 2936.2          | 3.5
256        | 182.4      | 195.6647   | 2941.8          | 3.9
~~~

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

| Num buffers | Buf cache | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------|-----|-------|----------|-------------|-----------|-------------|
| 128         | 32        | 256 | 177.2 | 191.1354 | 3027.6      | 1.8       | 80.2        |
| 96          | 24        | 256 | 184.6 | 196.3288 | 2906.6      | .3        | 90.4        |
| 64          | 16        | 256 | 184.8 | 196.2836 | 2904.4      | .1        | 99.5        |
| 48          | 12        | 256 | 184.8 | 196.2855 | 2904.4      | .1        | 99.5        |
| 44          | 11        | 256 | 184.7 | 196.2007 | 2905.8      | .1        | 99.5        |
| 40          | 10        | 256 | 184.4 | 196.0787 | 2909.8      | .2        | 99.5        |
| 36          | 9         | 256 | 183.8 | 195.2361 | 2920.3      | .2        | 99.5        |
| 32          | 8         | 256 | 181.5 | 192.9179 | 2957.6      | .3        | 99.5        |
| 24          | 6         | 256 | 157.1 | 167.6508 | 3415.3      | .5        | 99.6        |
| 16          | 4         | 256 | 115.8 | 122.8991 | 4635.6      | .1        | 99.5        |


### Test 11

Split each NVMe disk into 3 partitions with SPDK split block device
and build delay block device on top of some partitions.

IO depth is shared equally between all disks. FIO runs 3 jobs with
queue depth of 85 each. This gives us total IO depth of 255 per
initiator.

**IO pacing**: `Number of buffers`

**Configuration**: `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

| Num buffers | Num delay bdevs | QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------------|----|-------|----------|-------------|-----------|-------------|
| 96          | 0               | 85 | 182.1 | 193.3071 | 3022.7      | .2        | 93.5        |
| 96          | 16              | 85 | 184.3 | 195.8785 | 2900.2      | 0         | 93.3        |
| 96          | 32              | 85 | 128.1 | 133.3879 | 4297.4      | 2.0       | 87.5        |
| 48          | 0               | 85 | 184.7 | 196.2756 | 2893.4      | 0         | 99.5        |
| 48          | 16              | 85 | 108.9 | 116.9105 | 4907.7      | 1.5       | 99.4        |
| 48          | 32              | 85 | 64.5  | 67.2054  | 8287.5      | 1.4       | 99.2        |


### Test 12

Split each NVMe disk into 3 partitions with SPDK split block device
and build delay block device on top of some partitions.

FIO runs 3 jobs with 16 disks each. Job 1 is always delay devices, job
2 may be good (16 delay bdevs) or delay (32 dely bdevs), job 3 is
always good. IO depth is fixed to 256 for job 3. For jobs 1 and 2 it
is set to value in QD column in the table below. For 32 delay bdevs
effective IO depth is twice the QD since we have 2 jobs each with it's
own IO depth.

**IO pacing**: `Number of buffers`

**Configuration**: `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

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

### Test 13

Test latencies with different configurations.

**IO pacing**: `N/A`

**Configuration**: `config_null_16`, `config_nvme`, `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

16 Null disks

| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate
| 1          | 71.6       | 75.7205    | 33.8            | .2         | 99.0
| 1          | 71.6       | 75.9995    | 33.8            | .2         | 99.0
| 1          | 71.5       | 75.3912    | 33.9            | .2         | 99.0
| 1          | 71.8       | 76.22      | 33.8            | .2         | 99.1
| 1          | 71.4       | 75.3232    | 34.0            | .2         | 99.1

16 NVMe disks

| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate
| 1          | 13.2       | 13.9669    | 158.1           | .1         | 99.0
| 1          | 13.1       | 13.972     | 158.4           | .1         | 99.0
| 1          | 13.2       | 13.9672    | 157.9           | .1         | 98.9
| 1          | 13.2       | 14.0219    | 157.7           | .1         | 99.0
| 1          | 13.1       | 13.9356    | 158.6           | .1         | 98.8

48 split disks

| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate
| 1          | 37.6       | 39.8285    | 166.7           | .1         | 99.3
| 1          | 37.5       | 39.7433    | 166.9           | .1         | 99.3
| 1          | 37.5       | 39.8247    | 166.8           | 0          | 99.3
| 1          | 37.6       | 39.79      | 166.7           | .1         | 99.2
| 1          | 37.5       | 39.8147    | 166.8           | .1         | 99.3

48 split+delay disks

| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate
| 1          | 5.3        | 5.6853     | 1179.0          | 0          | 98.2
| 1          | 5.3        | 5.6539     | 1179.7          | 0          | 98.1
| 1          | 5.3        | 5.6705     | 1178.6          | 0          | 98.0
| 1          | 5.3        | 5.6788     | 1180.5          | 0          | 97.8
| 1          | 5.3        | 5.6622     | 1180.1          | 0          | 97.7
