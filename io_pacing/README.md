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
| [Test 11](#test-11) | None             | 16 NVMe, split 3          | Basic test                                   |
| [Test 12](#test-12) | NumSharedBuffers | 16 NVMe, split 3          | Basic test                                   |
| [Test 13](#test-13) | None             | 16 NVMe, split 3, 1 delay | Basic test                                   |
| [Test 14](#test-14) | NumSharedBuffers | 16 NVMe, split 3, 1 delay | Basic test                                   |
| [Test 15](#test-15) | None             | 16 NVMe, split 3, 2 delay | Basic test                                   |
| [Test 16](#test-16) | NumSharedBuffers | 16 NVMe, split 3, 2 delay | Basic test                                   |

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

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 167.1      | 181.425    | 99.9            | 10.1
16         | 176.8      | 192.4352   | 189.2           | 9.9
32         | 179.2      | 194.919    | 373.9           | 7.5
64         | 181.2      | 196.3038   | 739.9           | 4.8
128        | 181.5      | 196.3335   | 1477.7          | 7.7
256        | 184.8      | 196.3406   | 2903.2          | 0
~~~

**Initiator**: `fio+kernel 8 jobs`

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

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 98.8       | 106.5925   | 169.1           | 5.2
16         | 162.9      | 177.3973   | 205.3           | 10.4
32         | 178.2      | 188.405    | 375.9           | 8.5
64         | 154.1      | 186.9401   | 870.3           | 3.1
128        | 149.1      | 172.697    | 1798.7          | 3.7
256        | 145.1      | 131.8397   | 3698.2          | 4.2
~~~

Closer look at 40-48 queue depth range.

~~~
QD         | BW         | WIRE BW    | AVG LAT, us
40         | 175.7      | 193.2358   | 476.6
41         | 166.7      | 193.6239   | 514.9
42         | 166.7      | 193.1893   | 527.7
43         | 164.2      | 191.6463   | 548.2
44         | 161.1      | 191.3681   | 571.8
48         | 157.9      | 192.3115   | 636.6
~~~

**Initiator**: `fio+kernel 8 jobs`

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

| Num buffers | Buf cache | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV |
|-------------|-----------|-----|-------|----------|-------------|-----------|
| 128         | 12        | 256 | 161.1 | 190.8806 | 3330.8      | 3.9       |
| 96          | 6         | 256 | 180.7 | 195.5755 | 2970.4      | 5.3       |
| 64          | 4         | 256 | 170.2 | 194.2269 | 3153.8      | 7.7       |
| 48          | 3         | 256 | 180.6 | 195.3472 | 2971.3      | 5.4       |
| 44          | 2         | 256 | 178.8 | 192.0676 | 3002.4      | 4.0       |
| 40          | 2         | 256 | 177.8 | 191.2827 | 3018.4      | 4.5       |
| 36          | 2         | 256 | 176.9 | 188.9295 | 3034.2      | 5.2       |
| 32          | 2         | 256 | 171.6 | 191.2294 | 3127.2      | 6.2       |
| 24          | 1         | 256 | 142.1 | 152.6891 | 3775.0      | 2.9       |
| 16          | 1         | 256 | 112.8 | 125.2018 | 4759.4      | 3.9       |

### Test 10

Check performance effect of number of data buffers with 4 cores. All
buffers are shared equally between all threads at start with
`BufCacheSize` parameter.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/4)) config_nvme`

**Initiator**: `fio+SPDK`

test_10
| Num buffers | Buf cache | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV |
|-------------|-----------|-----|-------|----------|-------------|-----------|
| 128         | 32        | 256 | 175.3 | 179.7331 | 3070.2      | 4.3       |
| 96          | 24        | 256 | 184.8 | 196.3222 | 2903.2      | 0         |
| 64          | 16        | 256 | 184.8 | 196.3309 | 2903.5      | 0         |
| 48          | 12        | 256 | 184.8 | 196.2957 | 2904.0      | 0         |
| 44          | 11        | 256 | 184.7 | 196.2403 | 2905.0      | 0         |
| 40          | 10        | 256 | 184.6 | 195.9709 | 2907.4      | .1        |
| 36          | 9         | 256 | 183.5 | 194.6438 | 2925.3      | .1        |
| 32          | 8         | 256 | 180.5 | 191.9847 | 2972.7      | .3        |
| 24          | 6         | 256 | 151.8 | 161.1801 | 3534.6      | .3        |
| 16          | 4         | 256 | 114.9 | 123.3957 | 4669.5      | .5        |

### Test 11

Split each NVMe disk into 3 partitions with SPDK split block device.

**IO pacing**: `None`

**Configuration**: `config_nvme_split3`

**Initiator**: `fio+SPDK`

Number of buffers 4095, buffer cache size 32.

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 61.1       | 66.4308    | 273.7           | 3.2
16         | 113.6      | 123.2159   | 294.6           | 5.3
32         | 177.7      | 193.0578   | 376.9           | 8.0
64         | 133.0      | 141.9838   | 1008.3          | 2.3
128        | 110.6      | 119.4736   | 2426.0          | 2.2
256        | 107.1      | 115.637    | 5011.1          | 2.1
~~~

### Test 12

Split each NVMe disk into 3 partitions with SPDK split block device.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme_split3`

**Initiator**: `fio+SPDK`

Number of buffers 96, buffer cache size 6.

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV |
|-----|-------|----------|-------------|-----------|
| 8   | 180.2 | 193.8022 | 278.8       | 2.4       |
| 16  | 178.0 | 191.901  | 564.7       | 2.2       |
| 32  | 179.3 | 193.484  | 1122.1      | 2.3       |
| 64  | 178.3 | 190.4941 | 2258.1      | 1.6       |
| 128 | 181.9 | 193.2196 | 4558.9      | 1.1       |
| 256 | 182.4 | 193.44   | 9354.5      | 2.6       |

### Test 13

Split each NVMe disk into 3 partitions with SPDK split block device.
Delay block devices is added on top of one third of partitions. Delay
time is 1 ms.

**IO pacing**: `None`

**Configuration**: `config_nvme_split3_delay1`

**Initiator**: `fio+SPDK`

CPU mask 0xFFFF, number of buffers 4095, buffer cache size 32.

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 29.9       | 32.3077    | 562.7           | .9
16         | 55.8       | 59.2461    | 600.3           | 1.8
32         | 106.4      | 115.1262   | 629.6           | 3.6
64         | 163.0      | 175.7864   | 822.6           | 4.9
128        | 108.6      | 117.3446   | 2469.8          | 2.4
256        | 106.7      | 113.3583   | 5030.5          | 1.1
~~~

CPU mask 0xF, number of buffers 4095, buffer cache size 32.

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 31.0       | 32.9594    | 543.2           | 0
16         | 57.2       | 60.8346    | 585.2           | 0
32         | 109.1      | 115.7588   | 614.4           | .3
64         | 176.3      | 188.0159   | 760.6           | .3
128        | 106.0      | 112.8389   | 2529.4          | 1.5
256        | 105.8      | 112.5577   | 5070.9          | 1.2
~~~

### Test 14

Split each NVMe disk into 3 partitions with SPDK split block device.
Delay block devices is added on top of one third of partitions. Delay
time is 1 ms.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme_split3_delay1`

**Initiator**: `fio+SPDK`

CPU mask 0xFFFF, number of buffers 96, buffer cache size 6.

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV |
|-----|-------|----------|-------------|-----------|
| 8   | 180.2 | 193.8022 | 278.8       | 2.4       |
| 16  | 178.0 | 191.901  | 564.7       | 2.2       |
| 32  | 179.3 | 193.484  | 1122.1      | 2.3       |
| 64  | 178.3 | 190.4941 | 2258.1      | 1.6       |
| 128 | 181.9 | 193.2196 | 4558.9      | 1.1       |
| 256 | 182.4 | 193.44   | 9354.5      | 2.6       |

### Test 15

Split each NVMe disk into 3 partitions with SPDK split block device.
Delay block devices is added on top of two thirds of partitions. Delay
time is 1 ms.

**IO pacing**: `None`

**Configuration**: `config_nvme_split3_delay2`

**Initiator**: `fio+SPDK`

CPU mask 0xFFFF, number of buffers 4095, buffer cache size 32.

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 19.0       | 20.5105    | 883.2           | .5
16         | 36.7       | 39.6856    | 913.0           | 1.1
32         | 71.1       | 76.9438    | 942.6           | 2.1
64         | 129.6      | 141.1166   | 1034.2          | 4.2
128        | 107.9      | 115.2508   | 2487.1          | 2.6
256        | 105.2      | 112.922    | 5102.1          | 2.1
~~~

CPU mask 0xF, number of buffers 4095, buffer cache size 32.

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 19.5       | 20.7461    | 860.2           | 0
16         | 37.6       | 39.9532    | 891.6           | 0
32         | 73.0       | 77.5455    | 918.4           | .1
64         | 133.5      | 141.8261   | 1004.3          | .2
128        | 104.9      | 111.4933   | 2557.8          | 1.8
256        | 103.8      | 110.1529   | 5171.4          | 1.2
~~~

### Test 16

Split each NVMe disk into 3 partitions with SPDK split block device.
Delay block devices is added on top of two thirds of partitions. Delay
time is 1 ms.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme_split3_delay2`

**Initiator**: `fio+SPDK`

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV |
|-----|-------|----------|-------------|-----------|
| 8   | 119.1 | 129.7133 | 422.0       | 2.5       |
| 16  | 167.4 | 178.8634 | 600.6       | 4.7       |
| 32  | 152.8 | 162.3213 | 1360.9      | 2.8       |
| 64  | 138.9 | 148.3271 | 2898.5      | 1.8       |
| 128 | 142.1 | 149.9065 | 6100.5      | 2.2       |
| 256 | 141.0 | 149.944  | 12418.3     | 3.1       |
