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
	shift
	local output=$1
	shift
	local section=$1
	shift
	local key=$1
	shift
	local val=$*


	local tmp_file=${file}.tmp

	${script_dir}/mlnx-spdk-update-conf.awk -v section=$section -v key="$key" value="$val" ${file} > ${tmp_file}
	rc=$?
	if [[ $rc == 0 ]]; then
		mv ${tmp_file} ${output}
	else
		echo "ERROR $rc for file=${file} section=${section} key=$key val=${val}"
		exit $rc
	fi
}

cp ${ceph_conf} ${ceph_conf}.bak

all_disks=$(awk -F" +" '/TransportId/{print $5"n1"}'  ${ceph_conf}  | xargs)
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

			for rotate in True False; do

			    if [[ $rotate == "True" ]]; then
				rotate_name="rotate"
			    else
				rotate_name="no_rotate"
			    fi

			    result_conf=spdk_nvmf_trgt_${flow_name}_${erasure_name}_${rotate_name}_${nd_name}.conf
			    echo "Number of disks $nd erased device $erase_device skip erasure $skip_erasure destination ${result_conf}"
			    echo "Disks $disks"

			    #			continue

			    update_cfg_file ${ceph_conf} ${result_conf} RAID1 NumDevices $nd
			    update_cfg_file ${result_conf} ${result_conf} RAID1 ErasedDevice $erase_device
			    update_cfg_file ${result_conf} ${result_conf} RAID1 SkipJerasure $skip_erasure
			    update_cfg_file ${result_conf} ${result_conf} RAID1 Rotate $rotate
			    update_cfg_file ${result_conf} ${result_conf} RAID1 Devices ${disks}
			done
		done
	done
done
