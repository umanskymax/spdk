#!/bin/sh
# VER=18.10
VER=19.03
git submodule init
git submodule update
for mod in dpdk ocf intel-ipsec-mb isa-l ; do
    (cd $mod;
      git archive \
            --format=tar.gz --prefix=$mod/ -o ~/rpmbuild/SOURCES/spdk-$mod-$VER.tar.gz  HEAD
    )
done

git archive --format=tar.gz --prefix=spdk-$VER/ -o ~/rpmbuild/SOURCES/spdk-$VER.tar.gz  HEAD
