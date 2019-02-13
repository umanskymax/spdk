#!/bin/bash -E

function add_map()
{
  local iface0=$1
  local iface1=$2
  ip1=$(  ip a l "$iface0" | awk '/inet /{x=$2;gsub("/.*$","", x); print x}' )
  mac1=$( cat /sys/class/net/$iface0/address )
  arp -s -i $iface1 $ip1 $mac1
}
n_rdma=$(ls -1 /sys/class/infiniband/ |wc -l)
if [ $n_rdma -eq 6 ] ; then
# mlx5_2 <-> mlx5_4
  add_map enp3s0f4 enp3s0f2
  add_map enp3s0f2 enp3s0f4
# mlx5_3 <-> mxl5_5
  add_map enp3s0f3 enp3s0f5
  add_map enp3s0f5 enp3s0f3
else
  echo "arp_fixup.sh: 4 NVMe PFs should be enabled on the SmartNIC. Exit" >&2
  exit 1
fi

