FROM centos:7

 # Update database and installed packages.
RUN yum -y update \
 \
 # Install CentOS Linux Software Collections release file.
 && yum -y install centos-release-scl \
 \
 # Install build tools.
 && yum -y install which file devtoolset-7-make devtoolset-7-gcc \
 \
 # Install Perl interpreter since it is required to run OpenSSL build scripts.
 && yum -y install perl \
 \
 # Install iptables since it is required to configure network for OpenVPN.
 && yum -y install iptables \
 \
 # OpenVPN build scripts require generic network tools to be present in the system.
 && yum -y install net-tools \
 \
 # Download LZO library source code.
 && curl -sL http://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz | tar xz -C /tmp \
 \
 # Download LZ4 library source code.
 && curl -sL https://github.com/lz4/lz4/archive/v1.8.2.tar.gz | tar xz -C /tmp \
 \
 # Download zlib library source code.
 && curl -sL http://zlib.net/zlib-1.2.11.tar.gz | tar xz -C /tmp \
 \
 # Download Linux-PAM source code.
 && curl -sL https://github.com/linux-pam/linux-pam/archive/v1.3.1.tar.gz | tar xz -C /tmp \
 \
 # Download OpenSSL library source code.
 && curl -sL https://www.openssl.org/source/openssl-1.1.0h.tar.gz | tar xz -C /tmp \
 \
 # Download OpenVPN source code.
 && curl -sL https://swupdate.openvpn.org/community/releases/openvpn-2.4.6.tar.gz | tar xz -C /tmp \
 \
 # Build LZO.
 && cd /tmp/lzo-2.10 \
 && scl enable devtoolset-7 " \
    ./configure \
       --prefix=/usr/local \
       --disable-dependency-tracking \
    " \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Build LZ4.
 && cd /tmp/lz4-1.8.2 \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Build zlib.
 && cd /tmp/zlib-1.2.11 \
 && scl enable devtoolset-7 " \
    ./configure \
        --prefix=/usr/local \
    " \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Build Linux-PAM.
 && cd /tmp/Linux-PAM-1.3.1 \
 && scl enable devtoolset-7 " \
    ./configure \
       --prefix=/usr/local \
       --includedir=/usr/local/include/security \
       --disable-dependency-tracking \
    " \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Build OpenSSL.
 && cd /tmp/openssl-1.1.0h \
 && scl enable devtoolset-7 " \
    ./Configure \
        gcc \
        --prefix=/usr/local \
        --openssldir=/etc/openssl \
        zlib \
    " \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Build OpenVPN.
 && cd /tmp/openvpn-2.4.6 \
 && scl enable devtoolset-7 " \
   ./configure \
     --prefix=/usr/local \
     --disable-dependency-tracking \
   " \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Check OpenVPN installation. It should print OpenVPN version and exit with code 1.
 && openvpn --version || true \
 \
 # Cleanup.
 && cd / \
 && rm -rf /tmp/openvpn* /tmp/openssl* /tmp/zlib* /tmp/Linux-PAM* /tmp/lzo* /tmp/lz4* \
 && yum clean all \
 && rm -rf /var/cache/yum
