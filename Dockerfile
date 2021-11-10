FROM centos:7.9.2009

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
 # Install XZ.
 && yum -y install xz \
 \
 # Install C library static libraries for static linking.
 && yum -y install glibc-static \
 \
 # Download LZ4 library source code.
 && curl -sL https://github.com/lz4/lz4/archive/v1.9.3.tar.gz | tar xz -C /tmp \
 \
 # Download OpenSSL library source code.
 && curl -sL https://www.openssl.org/source/openssl-1.1.1l.tar.gz | tar xz -C /tmp \
 \
 # Download OpenVPN source code.
 && curl -sL https://swupdate.openvpn.org/community/releases/openvpn-2.5.4.tar.gz | tar xz -C /tmp \
 \
 # Create directory build.
 && mkdir /openvpn-build

 # Build LZ4.
RUN cd /tmp/lz4-1.9.3 \
 && scl enable devtoolset-7 " \
    make \
      -j $(nproc) \
      CC=gcc \
      LD=gcc \
      BUILD_STATIC=yes \
      BUILD_SHARED=no \
      PREFIX=/openvpn-build \
      VERBOSE=1 \
      CFLAGS='-m64' \
      LDFLAGS='-static -m64' \
    " \
 && scl enable devtoolset-7 " \
    make install \
      -j $(nproc) \
      CC=gcc \
      LD=gcc \
      BUILD_STATIC=yes \
      BUILD_SHARED=no \
      PREFIX=/openvpn-build \
      VERBOSE=1 \
      CFLAGS='-m64' \
      LDFLAGS='-static -m64' \
    "

 # Build OpenSSL.
RUN cd /tmp/openssl-1.1.1l \
 && scl enable devtoolset-7 " \
    ./Configure \
       gcc \
       -static \
       -static-libgcc \
       -m64 \
       no-shared \
       no-autoload-config \
       no-tests \
       --prefix=/openvpn-build \
       --openssldir=/openvpn-build/ssl \
    " \
 && scl enable devtoolset-7 "make -j $(nproc)" \
 && scl enable devtoolset-7 "make install_sw" \
 && scl enable devtoolset-7 "make install_ssldirs"

 # Build OpenVPN. To look for options: "./configure --help".
RUN cd /tmp/openvpn-2.5.4 \
 && scl enable devtoolset-7 " \
   ./configure \
       --prefix=/openvpn-build \
       --enable-static \
       --disable-shared \
       --disable-debug \
       --disable-plugins \
       --enable-port-share \
       --enable-lz4 \
       --disable-plugin-auth-pam \
       --disable-lzo \
       OPENSSL_LIBS='-L/openvpn-build/lib -lssl -lcrypto' \
       OPENSSL_CFLAGS='-I/openvpn-build/include' \
       OPENSSL_CRYPTO_LIBS='-L/openvpn-build/lib -lcrypto' \
       OPENSSL_CRYPTO_CFLAGS='-I/openvpn-build/include' \
       LZ4_CFLAGS='-I/openvpn-build/include' \
       LZ4_LIBS='-L/openvpn-build/lib -llz4' \
   " \
 && scl enable devtoolset-7 "make -j $(nproc) LIBS='-all-static'" \
 && scl enable devtoolset-7 "make install"

 # Make openvpn executable available system-wide.
RUN ln -s /openvpn-build/sbin/openvpn /usr/local/sbin/ \
 \
 # Make openssl executable available system-wide.
 && ln -s /openvpn-build/bin/openssl /usr/local/bin/ \
 \
 # Check OpenVPN installation. It should print OpenVPN version and exit with code 1.
 && sh -c "openvpn --version || true" \
 \
 # Cleanup.
 && cd / \
 && rm -rf /tmp/openvpn* /tmp/openssl* /tmp/lz4* \
 && yum clean all \
 && rm -rf /var/cache/yum
