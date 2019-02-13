#!/bin/bash -eE
# Build docker image to build SPDK in it
# i.e install all build dependencies
PARENT_IMGID=centos75-nvme-snap-2.0

dockerfile=`mktemp ./Dockerfile.XXXXXX`
trap clean EXIT TERM
function clean()
{
    if [ -e "$dockerfile" ] ; then
        rm -f "$dockerfile"
    fi
}

   # yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 
   # yum -y install epel-release
MY_ARCH=$(uname -m)
cat <<EOF > $dockerfile
FROM harbor.mellanox.com/swx-storage/$MY_ARCH/$PARENT_IMGID
MAINTAINER yuriis@mellanox.com
ADD . scripts/spdk.spec /tmp/
RUN mv -f /etc/yum.repos.d/CentOS-Vault.repo /etc/yum.repos.d/CentOS-Sources.repo /root/ ; \
    yum-builddep -y /tmp/spdk.spec
EOF

docker build -t builder-spdk1907-snap2 -f $dockerfile .
# docker tag builder-spdk1907-snap2:latest harbor.mellanox.com/swx-storage/`uname -r`/builder-spdk1907-snap2:latest
# docker push harbor.mellanox.com/swx-storage/`uname -r`/builder-spdk1907-snap2:latest

