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
 && curl -sL https://github.com/lz4/lz4/archive/v1.8.0.tar.gz | tar xz -C /tmp \
 \
 # Download zlib library source code.
 && curl -sL http://zlib.net/zlib-1.2.11.tar.gz | tar xz -C /tmp \
 \
 # Download Linux-PAM source code.
 && curl -sL http://www.linux-pam.org/library/Linux-PAM-1.3.0.tar.gz | tar xz -C /tmp \
 \
 # Download OpenSSL library source code.
 && curl -sL https://www.openssl.org/source/openssl-1.1.0g.tar.gz | tar xz -C /tmp \
 \
 # Download OpenVPN source code.
 && curl -sL https://swupdate.openvpn.org/community/releases/openvpn-2.4.4.tar.gz | tar xz -C /tmp \
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
 && cd /tmp/lz4-1.8.0 \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install" \
 \
 # Symlink shared libraries since "make install" doesn't do it for some reasons.
 # Without this OpenVPN executable fails to load "liblz4.so.0".
 # Use "ldd $(which openvpn)" to check how executable resolves shared libraries.
 && ln -s /usr/local/lib/liblz4.so* /lib64 \
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
 && cd /tmp/Linux-PAM-1.3.0 \
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
 && cd /tmp/openssl-1.1.0g \
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
 && cd /tmp/openvpn-2.4.4 \
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
 # Create TUN/TAP device if it doesn't exist.
 # See https://groups.google.com/d/msg/docker-user/2jFeDGJj36E/XjFh5i1ARpcJ
 && mkdir -p /dev/net \
 && /bin/sh -c "[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun" \
 \
 # Check TUN/TAP device. It should output "cat: /dev/net/tun: File descriptor in bad state" and exit with code 1.
 && cat /dev/net/tun || true \
 \
 # Cleanup.
 && cd / \
 && rm -rf /tmp/openvpn* /tmp/openssl* /tmp/zlib* /tmp/Linux-PAM* /tmp/lzo* /tmp/lz4* \
 && yum clean all \
 && rm -rf /var/cache/yum