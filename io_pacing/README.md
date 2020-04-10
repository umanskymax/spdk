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

### Test 4

**IO pacing**: `Limit number of SPDK buffers to 96`

**Target cmd line**: `sudo ./install/bin/spdk_tgt -c nvmf_null_16_num_buffers.conf -m 0xFFFF`

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

Num shared buffers 128. Buffer cache size 8

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 97.3       | 105.1353   | 171.7           | 5.8
16         | 161.2      | 175.0354   | 207.4           | 10.1
32         | 177.0      | 192.3259   | 378.5           | 9.9
64         | 162.5      | 192.4828   | 824.9           | 6.6
128        | 161.9      | 194.0563   | 1657.4          | 5.5
256        | 162.1      | 182.5859   | 3310.5          | 3.3
~~~

Num shared buffers 96. Buffer cache size 6

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 98.5       | 106.7853   | 169.6           | 5.4
16         | 162.3      | 175.6355   | 206.1           | 10.3
32         | 180.5      | 192.2055   | 371.1           | 6.6
64         | 181.8      | 193.3736   | 737.4           | 5.1
128        | 181.6      | 194.5455   | 1476.9          | 5.5
256        | 182.9      | 195.7027   | 2934.0          | 3.3
~~~

Num shared buffers 64. Buffer cache size 4

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 99.9       | 108.4319   | 167.2           | 5.1
16         | 164.4      | 179.3884   | 203.4           | 10.0
32         | 176.9      | 192.5691   | 378.6           | 10.0
64         | 181.1      | 194.1889   | 740.4           | 5.9
128        | 181.1      | 193.6662   | 1481.1          | 5.7
256        | 149.2      | 195.3338   | 3853.0          | 13.9
~~~

Num shared buffers 48. Buffer cache size 3

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 99.1       | 107.3868   | 168.5           | 5.5
16         | 163.5      | 176.4363   | 204.6           | 10.3
32         | 176.7      | 191.9288   | 379.0           | 10.2
64         | 180.9      | 192.6408   | 741.1           | 6.2
128        | 181.5      | 195.3365   | 1478.2          | 5.1
256        | 182.3      | 195.0589   | 2944.4          | 3.9
~~~

Num shared buffers 32. Buffer cache size 2

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 98.8       | 108.0339   | 169.1           | 5.5
16         | 164.3      | 179.0546   | 203.6           | 10.6
32         | 177.1      | 185.2458   | 378.2           | 6.5
64         | 178.2      | 188.9545   | 752.3           | 7.1
128        | 177.6      | 189.5432   | 1510.4          | 5.9
256        | 176.7      | 184.75     | 3037.5          | 4.2
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
