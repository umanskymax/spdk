~~~
test_1
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 32         | 170.9      | 181.427    | 392.6           | .3         | 98.4            | 93.3 (11.6)               |
| 64         | 170.9      | 181.3245   | 785.8           | .4         | 39.1            | 131.0 (16.3)              |
| 128        | 166.7      | 176.9795   | 1615.4          | .3         | 37.8            | 237.0 (29.6)              |
| 256        | 164.7      | 168.7664   | 3282.9          | 2.1        | 38.8            | 218.6 (27.3)              |
| 1024       | 153.6      | 163.1993   | 7044.5          | .2         | 99.6            | 5.6 (.7)                  |
| 2048       | 154.0      | 163.4692   | 7025.8          | .3         | 99.6            | 6.0 (.7)                  |

test_2
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 32         | 177.3      | 188.4596   | 378.6           | .3         | 97.9            | 22.6 (2.8)                |
| 64         | 177.5      | 188.6934   | 756.5           | .2         | 42.3            | 50.6 (6.3)                |
| 128        | 173.8      | 184.4538   | 1549.6          | .1         | 34.3            | 192.3 (24.0)              |
| 256        | 170.5      | 182.0628   | 3169.5          | .6         | 95.5            | 275.3 (34.4)              |
| 1024       | 152.6      | 162.0436   | 14093.3         | .3         | 99.2            | 3.6 (.4)                  |
| 2048       | 146.8      | 155.89     | 29259.5         | .1         | 99.2            | 5.0 (.6)                  |

test_3
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 32         | 176.0      | 187.0287   | 381.5           | .3         | 97.1            | 24.0 (3.0)                |
| 36         | 176.6      | 187.8329   | 427.6           | .4         | 97.5            | 31.0 (3.8)                |
| 40         | 176.8      | 188.0061   | 474.5           | .6         | 95.7            | 38.0 (4.7)                |
| 44         | 177.1      | 188.2378   | 521.3           | .5         | 91.0            | 34.0 (4.2)                |
| 48         | 176.7      | 187.7405   | 569.9           | .5         | 86.7            | 29.6 (3.7)                |
| 64         | 172.6      | 169.7387   | 777.7           | 2.4        | 69.4            | 51.6 (6.4)                |
| 128        | 161.5      | 181.6892   | 1662.2          | 8.3        | 74.7            | 108.0 (13.5)              |
| 256        | 157.4      | 173.2665   | 3417.3          | 8.1        | 64.5            | 253.6 (31.7)              |
| 1024       | 149.0      | 170.6107   | 14422.2         | 6.8        | 99.4            | 47.0 (5.8)                |
| 2048       | 140.5      | 152.0583   | 27562.9         | 3.2        | 99.3            | 684.3 (85.5)              |

test_4
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 32         | 176.8      | 187.8775   | 379.7           | .4         | 98.9            | 21.3 (2.6)                |
| 64         | 177.1      | 187.9697   | 758.5           | .3         | 98.9            | 28.6 (3.5)                |
| 128        | 173.8      | 184.6562   | 1550.0          | .4         | 98.7            | 51.3 (6.4)                |
| 256        | 170.2      | 182.2758   | 3175.4          | 1.3        | 98.6            | 52.6 (6.5)                |
| 1024       | 151.9      | 161.2414   | 14155.3         | .3         | 99.2            | 7.3 (.9)                  |
| 2048       | 145.5      | 154.4833   | 29514.1         | .2         | 99.2            | 9.0 (1.1)                 |

test_5
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 32         | 176.1      | 187.3874   | 381.2           | .4         | 99.3            | 25.0 (3.1)                |
| 64         | 176.9      | 188.1535   | 759.5           | .4         | 99.1            | 48.0 (6.0)                |
| 128        | 173.8      | 184.8351   | 1548.9          | .3         | 99.0            | 54.0 (6.7)                |
| 256        | 169.3      | 181.2124   | 3192.9          | 1.4        | 99.2            | 56.0 (7.0)                |
| 1024       | 150.8      | 160.1724   | 14278.3         | .2         | 99.5            | 25.3 (3.1)                |
| 2048       | 144.1      | 153.2211   | 29793.5         | .1         | 99.5            | 23.3 (2.9)                |

test_10
Num shared buffers 128. Buffer cache size 32
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 169.3      | 182.6667   | 3194.9          | 1.4        | 97.9            | 68.6 (8.5)                |
| 1024       | 150.2      | 159.6826   | 14332.8         | .2         | 99.5            | 26.0 (3.2)                |
Num shared buffers 96. Buffer cache size 24
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 170.2      | 181.9666   | 3172.9          | 1.3        | 99.2            | 62.3 (7.7)                |
| 1024       | 152.1      | 161.5945   | 14150.6         | .1         | 99.5            | 26.3 (3.2)                |
Num shared buffers 64. Buffer cache size 16
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 167.4      | 178.1082   | 3214.1          | .9         | 99.4            | 39.3 (4.9)                |
| 1024       | 151.3      | 160.6086   | 14219.1         | .3         | 99.5            | 24.0 (3.0)                |
Num shared buffers 48. Buffer cache size 12
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 164.3      | 174.381    | 3269.9          | .9         | 99.5            | 31.3 (3.9)                |
| 1024       | 151.4      | 160.9011   | 14204.5         | .1         | 99.5            | 25.0 (3.1)                |
Num shared buffers 44. Buffer cache size 11
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 163.4      | 173.5546   | 3288.2          | .8         | 99.5            | 27.6 (3.4)                |
| 1024       | 151.6      | 160.7702   | 14188.9         | .1         | 99.5            | 24.6 (3.0)                |
Num shared buffers 40. Buffer cache size 10
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 161.9      | 171.8977   | 3316.2          | .9         | 99.5            | 28.0 (3.5)                |
| 1024       | 151.1      | 159.4914   | 14234.5         | .2         | 99.5            | 24.6 (3.0)                |
Num shared buffers 36. Buffer cache size 9
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 159.3      | 169.51     | 3370.5          | 1.0        | 99.5            | 25.3 (3.1)                |
| 1024       | 151.6      | 161.0522   | 14187.8         | .2         | 99.5            | 25.0 (3.1)                |
Num shared buffers 32. Buffer cache size 8
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 154.3      | 164.0146   | 3477.8          | 1.4        | 99.5            | 22.0 (2.7)                |
| 1024       | 151.7      | 161.0154   | 14186.7         | .4         | 99.5            | 25.0 (3.1)                |
Num shared buffers 24. Buffer cache size 6
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 134.6      | 142.6857   | 3988.2          | 2.2        | 99.5            | 18.3 (2.2)                |
| 1024       | 124.5      | 132.0277   | 17253.3         | 2.7        | 99.5            | 17.0 (2.1)                |
Num shared buffers 16. Buffer cache size 4
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 99.5       | 104.9816   | 5394.1          | 3.9        | 99.5            | 13.3 (1.6)                |
| 1024       | 93.5       | 98.8514    | 22962.4         | 3.6        | 99.5            | 11.3 (1.4)                |

test_11
| 0xF | 96 | 0
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 85         | 169.1      | 179.7768   | 3175.8          | .1         | 97.3            | 52.6 (6.5)                |
| 341        | 160.0      | 170.0047   | 13418.1         | .8         | 97.8            | 48.6 (6.0)                |
| 0xF | 96 | 16
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 85         | 161.7      | 172.3329   | 3308.0          | .4         | 99.0            | 65.0 (8.1)                |
| 341        | 157.3      | 166.5514   | 13635.0         | .9         | 99.0            | 58.3 (7.2)                |
| 0xF | 96 | 32
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 85         | 120.6      | 127.2307   | 4431.9          | 1.3        | 98.9            | 66.6 (8.3)                |
| 341        | 116.7      | 121.8888   | 18380.5         | 1.7        | 98.8            | 66.3 (8.2)                |
| 0xF | 48 | 0
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 85         | 162.3      | 172.4511   | 3297.5          | .3         | 99.5            | 33.3 (4.1)                |
| 341        | 156.7      | 164.1952   | 13695.1         | 1.0        | 99.4            | 34.3 (4.2)                |
| 0xF | 48 | 16
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 85         | 104.0      | 109.0722   | 5138.2          | 1.7        | 99.3            | 35.6 (4.4)                |
| 341        | 104.2      | 103.9965   | 20594.1         | 3.5        | 99.2            | 35.3 (4.4)                |
| 0xF | 48 | 32
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 85         | 62.3       | 64.9966    | 8578.5          | 1.4        | 99.1            | 41.0 (5.1)                |
| 341        | 66.1       | 63.2596    | 32457.6         | 3.0        | 99.0            | 44.6 (5.5)                |

test_12

Job 3 QD 256
| 0xF | 48 | 16
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 163.1      | 173.2084   | 3318.9          | .6         | 99.4            | 29.6 (3.7)                |
| 2          | 162.8      | 172.7818   | 3350.9          | .5         | 99.4            | 35.3 (4.4)                |
| 4          | 162.1      | 172.0051   | 3416.4          | .5         | 99.4            | 26.3 (3.2)                |
| 8          | 161.0      | 171.3677   | 3543.1          | .6         | 99.4            | 29.3 (3.6)                |
| 16         | 158.6      | 168.3445   | 3806.5          | .7         | 99.4            | 30.6 (3.8)                |
| 32         | 152.4      | 162.1959   | 4402.7          | .9         | 99.4            | 31.3 (3.9)                |
| 64         | 136.5      | 144.3933   | 5897.2          | 1.4        | 99.4            | 28.6 (3.5)                |
| 0xF | 48 | 32
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 162.6      | 172.7337   | 3330.0          | .4         | 99.4            | 23.3 (2.9)                |
| 2          | 162.2      | 172.2692   | 3363.5          | .5         | 99.4            | 22.0 (2.7)                |
| 4          | 161.3      | 171.3497   | 3432.6          | .5         | 99.4            | 30.3 (3.7)                |
| 8          | 159.3      | 168.972    | 3581.4          | .7         | 99.4            | 28.3 (3.5)                |
| 16         | 151.4      | 161.1332   | 3989.6          | .9         | 99.4            | 29.6 (3.7)                |
| 32         | 130.7      | 137.9971   | 5133.3          | 1.8        | 99.3            | 27.3 (3.4)                |
| 64         | 101.3      | 106.1375   | 7944.8          | 2.6        | 99.3            | 33.3 (4.1)                |

Job 3 QD 1024
| 0xF | 48 | 16
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 141.5      | 149.765    | 15208.5         | .6         | 99.4            | 24.6 (3.0)                |
| 2          | 161.3      | 171.4983   | 13374.2         | .2         | 99.5            | 34.3 (4.2)                |
| 4          | 159.9      | 169.7728   | 13544.6         | .3         | 99.4            | 42.0 (5.2)                |
| 8          | 158.6      | 168.3692   | 13754.6         | .5         | 99.4            | 39.0 (4.8)                |
| 16         | 159.1      | 169.0077   | 13934.2         | .8         | 99.4            | 40.0 (5.0)                |
| 32         | 154.6      | 163.1266   | 14759.5         | 1.4        | 99.3            | 25.0 (3.1)                |
| 64         | 148.0      | 155.9475   | 16324.8         | 1.9        | 99.4            | 34.3 (4.2)                |
| 0xF | 48 | 32
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 154.0      | 163.613    | 13991.1         | .2         | 99.4            | 26.3 (3.2)                |
| 2          | 157.2      | 166.9471   | 13727.3         | .1         | 99.4            | 34.3 (4.2)                |
| 4          | 158.0      | 167.6685   | 13704.9         | .1         | 99.4            | 40.6 (5.0)                |
| 8          | 157.7      | 167.0871   | 13835.1         | 1.4        | 99.4            | 36.0 (4.5)                |
| 16         | 154.4      | 161.9207   | 14339.7         | 1.1        | 99.4            | 31.3 (3.9)                |
| 32         | 141.8      | 149.4109   | 16091.1         | 1.6        | 99.3            | 28.0 (3.5)                |
| 64         | 125.9      | 128.9647   | 19191.5         | 3.4        | 99.3            | 27.6 (3.4)                |

test_13

Null
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 37.6       | 39.6599    | 27.6            | .3         | 98.8            | 0 (0)                     |
| 1          | 37.6       | 39.7294    | 27.6            | .4         | 98.8            | .3 (0)                    |
| 1          | 37.6       | 39.6861    | 27.6            | .3         | 98.8            | 0 (0)                     |

Local Nvme
| QD | BW   | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
| 1  | 10.5 |         | 98.93       |           |             |                      |                  |
| 1  | 11.1 |         | 94.34       |           |             |                      |                  |
| 1  | 11.1 |         | 94.17       |           |             |                      |                  |

Nvme
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 7.3        | 7.788      | 143.1           | 0          | 98.8            | .3 (0)                    |
| 1          | 7.3        | 7.841      | 141.6           | 0          | 98.7            | 0 (0)                     |
| 1          | 7.3        | 7.856      | 141.6           | 0          | 98.6            | .3 (0)                    |

Split
| 0xF | 48 | 0
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 20.7       | 22.0364    | 151.3           | 0          | 99.2            | 1.0 (.1)                  |
| 1          | 20.9       | 22.2455    | 149.8           | 0          | 99.2            | .3 (0)                    |
| 1          | 20.9       | 22.2737    | 149.8           | 0          | 99.2            | 1.0 (.1)                  |

Delay
| 0xF | 48 | 48
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 1          | 2.6        | 2.8676     | 1166.7          | 0          | 98.2            | 1.0 (.1)                  |
| 1          | 2.6        | 2.8643     | 1166.8          | 0          | 98.0            | 2.0 (.2)                  |
| 1          | 2.6        | 2.8659     | 1166.6          | 0          | 98.1            | .6 (0)                    |

test_14
CPU mask 0xF0, num cores 4, IO pacer period 5600, adjusted period 22400, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 162.9      | 174.1939   | 26650.4         | .2         | 93.2            | 1317.6 (164.7)            | 27.5
CPU mask 0xF0, num cores 4, IO pacer period 5650, adjusted period 22600, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 160.2      | 172.8867   | 27011.5         | .4         | 95.1            | 1032.0 (129.0)            | 27.8
CPU mask 0xF0, num cores 4, IO pacer period 5675, adjusted period 22700, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 162.9      | 171.1994   | 26664.3         | .2         | 93.2            | 1139.3 (142.4)            | 27.5
CPU mask 0xF0, num cores 4, IO pacer period 5700, adjusted period 22800, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 161.8      | 173.3885   | 26814.4         | .2         | 93.3            | 1047.0 (130.8)            | 27.7
CPU mask 0xF0, num cores 4, IO pacer period 5725, adjusted period 22900, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 162.4      | 173.4282   | 26727.0         | .2         | 93.2            | 1112.3 (139.0)            | 27.6
CPU mask 0xF0, num cores 4, IO pacer period 5750, adjusted period 23000, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 162.4      | 172.9882   | 26724.5         | .2         | 93.9            | 1203.3 (150.4)            | 27.6
CPU mask 0xF0, num cores 4, IO pacer period 5775, adjusted period 23100, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 161.8      | 172.66     | 26802.5         | .2         | 93.7            | 1212.3 (151.5)            | 27.7
CPU mask 0xF0, num cores 4, IO pacer period 5800, adjusted period 23200, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 161.4      | 171.6836   | 26859.9         | .2         | 93.6            | 1276.0 (159.5)            | 27.7
CPU mask 0xF0, num cores 4, IO pacer period 6000, adjusted period 24000, tuner period 10000, tuner step 1000
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV  | L3 Hit Rate     | Bufs in-flight (MiB)      | Pacer period, us
| 256        | 152.4      | 159.8559   | 28247.8         | .6         | 96.3            | 261.6 (32.7)              | 29.3
~~~
