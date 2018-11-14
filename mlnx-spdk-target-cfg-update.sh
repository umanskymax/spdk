#!/bin/bash

ceph_conf=${ceph_conf:="./nvmf.conf"}
script_name=$(basename "$0")
script_dir=$(dirname "$0")

#function show_usage()
#{
#	echo "Usage: $script_name [set|unset]"
#}
#
#if [[ "$#" -ne 1 ]]; then
#	echo "Illegal number of parameters"
#	show_usage
#	exit 1
#fi
#
#if [[ ! -f ${ceph_conf} ]]; then
#	echo "Can't find  ${ceph_conf}"
#	exit 1
#fi
#
#key=$1
#value="true"
#
#case $key in
#	set)
#		value="true"
#		;;
#	unset)
#		value="false"
#		;;
#	*)
#		echo "Unknown argument $key"
#		exit 1
#esac

function update_cfg_file()
{
	local file=$1
	local section=$2
	local key=$3
	local val=$4
	local output=$5


	local tmp_file=${file}.${section}.${key}.${val}

	${script_dir}/mlnx-spdk-update-conf.awk -v section=$section -v key=$key value=$val ${file} > ${tmp_file}
	rc=$?
	if [[ $rc == 0 ]]; then
		mv ${tmp_file} ${output}
	else
		echo "ERROR $rc for file=${file} section=${section} key=$key val=${val}"
		exit $rc
	fi
}

cp ${ceph_conf} ${ceph_conf}.bak

all_disks=$(awk -F" +" '/TransportId/{print $5}'  ${ceph_conf}  | xargs)
echo $all_disks

for nd in 4 8 16; do

	nd_name="nd$nd"
	disks=$(echo $all_disks | cut -f -$nd -d " ")

	for skip_erasure in True False; do

		if [[ $skip_erasure == "True" ]]; then
			erasure_name="jerasure"
		else
			erasure_name="no_jerasure"
		fi

		for erase_device in "-1" "1"; do


			if [[ $erase_device == "-1" ]]; then
				flow_name="good_flow"
			else
				flow_name="bad_flow"
			fi

			result_conf=spdk_nvmf_trgt_${flow_name}_${erasure_name}_${nd_name}.conf
			echo "Number of disks $nd erased device $erase_device skip erasure $skip_erasure destination ${result_conf}"
			echo "Disks $disks"

			update_cfg_file ${ceph_conf} RAID2 NumDevices $nd ${result_conf}
			update_cfg_file ${ceph_conf} RAID2 ErasedDevice $erase_device ${result_conf}
			update_cfg_file ${ceph_conf} RAID2 SkipJerasure $skip_erasure ${result_conf}
			update_cfg_file ${ceph_conf} RAID2 Devices $disks ${result_conf}
		done
	done
done
