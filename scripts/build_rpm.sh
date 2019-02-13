#!/bin/bash
args="$@"
wd=$(dirname $0)
wdir=$(dirname $wd)
cd $wdir
mkdir -p $HOME/rpmbuild/{SOURCES,RPMS,SRPMS,SPECS,BUILD,BUILDROOT}
set -e
if [ -z "$VER" ] ; then
    export VER=19.04
fi
branch=$(git rev-parse --abbrev-ref HEAD)
sha1=$(git rev-parse HEAD |cut -c -8)

git archive \
    --format=tar.gz --prefix=spdk-$VER/ -o ~/rpmbuild/SOURCES/spdk-$VER.tar.gz  HEAD
echo ***********
ls -l ~/rpmbuild/SOURCES/spdk-$VER.tar.gz
echo ***********
git submodule init
git submodule update
(cd dpdk;
 git archive \
    --format=tar.gz --prefix=dpdk/ -o ~/rpmbuild/SOURCES/spdk-dpdk-$VER.tar.gz  HEAD
)

(
cd intel-ipsec-mb ;
  git archive \
    --format=tar.gz --prefix=intel-ipsec-mb/ -o ~/rpmbuild/SOURCES/spdk-intel-ipsec-mb-$VER.tar.gz  HEAD
)

(
cd isa-l ;
  git archive \
    --format=tar.gz --prefix=isa-l/ -o ~/rpmbuild/SOURCES/spdk-isa-l-$VER.tar.gz  HEAD
)
(
cd ocf;
  git archive \
    --format=tar.gz --prefix=ocf/ -o ~/rpmbuild/SOURCES/spdk-ocf-$VER.tar.gz  HEAD
)

# BUILD_NUMBER is an env var passed by Jenkins
# https://stackoverflow.com/questions/16155792/using-jenkins-build-number-in-rpm-spec-file
fakeroot  \
  rpmbuild -bs \
    -D "_version ${VER}" -D "_rev ${BUILD_NUMBER:-1}" \
    --define "_branch ${branch}" \
    --define "_sha1 ${sha1}" $args \
    scripts/spdk.spec 

chown 0.0  ~/rpmbuild/SOURCES/spdk-*-$VER.tar.gz
ls -l ~/rpmbuild/SOURCES/*
# just a workaround for missed *-source repos:
fgrep -l vault.centos /etc/yum.repos.d/*.repo |while read fn ; do mv $fn /tmp/ ; done
#--disablerepo=extras-source --disablerepo=centosplus-source \
#--disablerepo=base-source \
#
yum-builddep -y scripts/spdk.spec
rpmbuild -bb \
    -D "_version ${VER}" -D "_rev ${BUILD_NUMBER:-1}" \
    --define "_branch ${branch}" \
    --define "_sha1 ${sha1}" $args \
    scripts/spdk.spec


if [ -d /scratch/upload ] ; then
  cp -p ~/rpmbuild/RPMS/`uname -m`/spdk-*$VER-${BUILD_NUMBER:-1}*.rpm /scratch/upload
  cp -p ~/rpmbuild/SRPMS/spdk-*$VER-${BUILD_NUMBER:-1}*.src.rpm /scratch/upload
fi
