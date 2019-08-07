# Copyright (c) 2018-2019, Mellanox Technologies. All rights reserved.

%define scm_version 19.07
%define unmangled_version %{scm_version}
%if "%{?_rev:1}" == ""
%define scm_rev 1
%else
%define scm_rev %{_rev}
%endif
Epoch: 0

Name:		spdk
Version:	%{scm_version}
Release:	%{scm_rev}%{?dist}
Summary:	Storage Performance Development Kit
Packager: 	yuriis@mellanox.com

Group: 		System Environment/Daemons
License: 	BSD and LGPLv2 and GPLv2
URL: 		http://www.spdk.io
Source0:	spdk-%{version}.tar.gz
Source1:	spdk-dpdk-%{version}.tar.gz
Source2:	spdk-intel-ipsec-mb-%{version}.tar.gz
Source3:	spdk-isa-l-%{version}.tar.gz
Source4:	spdk-ocf-%{version}.tar.gz

%define package_version %{epoch}:%{version}-%{release}
%define install_datadir %{buildroot}/%{_datadir}/%{name}
%define install_sbindir %{buildroot}/%{_sbindir}
%define install_bindir %{buildroot}/%{_bindir}
%define install_docdir %{buildroot}/%{_docdir}/%{name}

# Distros that don't support python3 will use python2
%if "%{dist}" == ".el7" || "%{dist}" == ".el7.centos" || "%{dist}" == ".el7.centos.a"
%define use_python2 1
%else
%define use_python2 0
%endif

ExclusiveArch: i686 x86_64 aarch64
%ifarch aarch64
%global machine armv8a
%global target arm64-%{machine}-linuxapp-gcc
%global _config arm64-%{machine}-linuxapp-gcc
%else
%global machine default
%global target %{_arch}-%{machine}-linuxapp-gcc
%global _config %{_arch}-native-linuxapp-gcc
%endif

# DPDK dependencies
BuildRequires: kernel-devel
BuildRequires: kernel-headers
# not present @ CentOS-7.4 w/o EPEL:
# - BuildRequires: libpcap-devel, python-sphinx, inkscape
# - BuildRequires: texlive-collection-latexextra
BuildRequires: doxygen
BuildRequires:graphviz
BuildRequires: numactl-devel
BuildRequires: libiscsi-devel

# SPDK build dependencies
BuildRequires:	git make gcc gcc-c++
BuildRequires:	CUnit-devel, libaio-devel, openssl-devel, libuuid-devel 
BuildRequires:	libiscsi-devel
BuildRequires:  lcov, clang-analyzer
# Additional dependencies for SPDK CLI 
%if "%{use_python2}" == "0"
BuildRequires:	python3-pep8 python3-configshell
%else
BuildRequires:	python-pep8 python-configshell
%endif
# Additional dependencies for NVMe over Fabrics
BuildRequires:	libibverbs-devel, librdmacm-devel
# Additional dependencies for building docs
# not present @ CentOS-7.4 w/o EPEL:
# - mscgen 
# - astyle-devel
%ifarch x86_64
# Additional dependencies for building pmem based backends
# BuildRequires:	libpmemblk-devel
%endif

# SPDK runtime dependencies
#Requires:	libibverbs >= 41mlnx1-OFED.4.4
#Requires:	librdmacm  >= 41mlnx1-OFED.4.2
#Requires:	libibverbs >= 23.0-1.el7
#Requires:	librdmacm  >= 23.0-1.el7
Requires:	libibverbs
Requires:	librdmacm 
Requires:	sg3_utils
# Requires:	avahi
Requires:   libhugetlbfs-utils
%if "%{use_python2}" == "0"
Requires: %{name}%{?_isa} = %{package_version} python3 python3-configshell python3-pexpect
%else
Requires: %{name}%{?_isa} = %{package_version} python python-configshell 
%endif

%description
The Storage Performance Development Kit (SPDK) provides a set of tools and
libraries for writing high performance, scalable, user-mode storage
applications.

%global debug_package %{nil}

%prep
%setup -q
tar zxf %{SOURCE1}
tar zxf %{SOURCE2}
tar zxf %{SOURCE3}
tar zxf %{SOURCE4}
# test -e ./dpdk/config/common_linuxapp

%build
./configure \
	--prefix=/usr \
	--disable-coverage \
    --enable-debug \
	--disable-tests \
	--without-crypto \
	--without-fio \
	--with-vhost \
	--without-pmdk \
	--without-vpp \
	--without-rbd \
	--with-rdma \
	--without-vtune 
	# --with-iscsi-initiator
	#--with-shared 
# SPDK make
make %{?_smp_mflags}

# make docs?

%install
mkdir -p %{install_bindir}
mkdir -p %{install_sbindir}
install -p -m 755 app/nvmf_tgt/nvmf_tgt %{install_sbindir}
install -p -m 755 app/spdk_tgt/spdk_tgt %{install_sbindir}
install -p -m 755 app/vhost/vhost %{install_sbindir}
install -p -m 755 app/iscsi_tgt/iscsi_tgt %{install_sbindir}
install -p -m 755 app/iscsi_top/iscsi_top %{install_bindir}
install -p -m 755 app/trace/spdk_trace %{install_bindir}
install -p -m 755 examples/nvme/perf/perf %{install_sbindir}/nvme-perf
install -p -m 755 contrib/setup_nvmf_tgt.py %{install_sbindir}
install -p -m 755 contrib/setup_vhost.py %{install_sbindir}
install -p -m 755 contrib/vhost_add_config.sh %{install_sbindir}
install -p -m 755 contrib/setup_hugepages.sh %{install_sbindir}
mkdir -p %{buildroot}%{_sysconfdir}/systemd/system
mkdir -p %{buildroot}%{_sysconfdir}/default
mkdir -p %{buildroot}%{_sysconfdir}/spdk
mkdir -p %{install_datadir}
install -p -m 644 include/spdk/pci_ids.h %{install_datadir}
install -p -m 644 scripts/common.sh %{install_datadir}
install -p -m 755 scripts/setup.sh %{install_datadir}
install -p -m 755 contrib/arp_fixup.sh %{install_sbindir}

for fn in nvmf_tgt vhost nvmf_proxy ; do
  if [ -e contrib/$fn.service ] ; then
    install -p -m 644 contrib/$fn.service %{buildroot}%{_sysconfdir}/systemd/system
  fi
  if [ -e contrib/$fn-default ] ; then
    install -p -m 644 contrib/$fn-default %{buildroot}%{_sysconfdir}/default/$fn
  fi
  if [ -e contrib/$fn.conf.example ] ; then
    install -p -m 644 contrib/$fn.conf.example %{buildroot}%{_sysconfdir}/spdk/
  fi
done
# Install SPDK rpc services
%if "%{use_python2}" == "0"
  if [ -e %{_libdir}/python3.7 ] ; then
    mkdir -p %{buildroot}/%{_libdir}/python3.7/site-packages/rpc/
    install -p -m 644 scripts/rpc/* %{buildroot}/%{_libdir}/python3.7/site-packages/rpc/
  fi
  install -p -m 755 scripts/rpc.py %{install_bindir}/spdk_rpc.py
%else
  mkdir -p %{buildroot}/%{_libdir}/python2.7/site-packages/rpc/
  install -p -m 644 scripts/rpc/* %{buildroot}/%{_libdir}/python2.7/site-packages/rpc/
  install -p -m 755 scripts/rpc_py2.py %{install_bindir}/spdk_rpc.py
  # sed -i -e 's!/usr/bin/env python3$!/usr/bin/env python2!' %{install_bindir}/spdk_rpc.py
%endif
# mkdir -p %{buildroot}/%{_sysconfdir}/avahi/services/
# install -p -m 644 contrib/avahi-spdk.service %{buildroot}/%{_sysconfdir}/avahi/services/spdk.service

%files
%{_sbindir}/*
%{_bindir}/*
%{_sysconfdir}/systemd/system/*.service
%{_libdir}/*
%{_datadir}/*
%config(noreplace) %{_sysconfdir}/default/*
%config(noreplace) %{_sysconfdir}/spdk/*
%doc README.md LICENSE

%post
case "$1" in
1) # install
	systemctl daemon-reload
#	systemctl restart avahi-daemon || true
	;;
2) # upgrade
	systemctl daemon-reload
#	systemctl restart avahi-daemon || true
	;;
esac

%changelog
* Wed Aug  7 2019 Yuriy Shestakov <yuriis@mellanox.com>
- ported to v19.07 release

* Mon Jul 15 2019 Yuriy Shestakov <yuriis@mellanox.com>
- ported to v19.04.1 release

* Thu May  2 2019 Yuriy Shestakov <yuriis@mellanox.com>
- ported to v19.04 release

* Thu Apr 11 2019 Yuriy Shestakov <yuriis@mellanox.com>
- added vhost config/service definition
- packaged v19.04-pre

* Fri Nov 16 2018 Yuriy Shestakov <yuriis@mellanox.com>
- build in a Docker image with upstream rdma-core libs
- packaged v18.10

* Wed May 16 2018 Yuriy Shestakov <yuriis@mellanox.com>
- Initial packaging
