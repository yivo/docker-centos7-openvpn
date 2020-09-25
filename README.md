# docker-centos7-openvpn

Docker container with CentOS 7 and OpenVPN server.

[View on Docker Hub](https://hub.docker.com/r/eahome00/centos7-openvpn/)

## Installation Guide

This guide will walk you through the process of installing and configuring OpenVPN server as Docker container.

Get Docker daemon and follow the instructions.

### Step 1: Configuration variables.

This is minimal configuration for your new OpenVPN server. 

Make changes, save somewhere and execute the following snippet on **host machine**:

```bash
    export OVPN_SERVER_ROOT="/etc/openvpn"
      export OVPN_SERVER_IP=$(curl http://ipecho.net/plain)
    export OVPN_SERVER_PORT="80"
export OVPN_SERVER_PROTOCOL="UDP"
    export OVPN_SERVER_NAME="${OVPN_SERVER_PORT}${OVPN_SERVER_PROTOCOL}"
  export OVPN_SERVER_CIPHER="AES-128-GCM"
        export RSA_KEY_SIZE="3072"
         export DH_KEY_SIZE="3072"
       export EASY_RSA_ROOT="${OVPN_SERVER_ROOT}/easy-rsa"
  export USE_PUBLIC_DH_TOOL="1" # Set to "1" if you want to use https://2ton.com.au/dhtool/ for getting DH parameter instead of generating by yourself using OpenSSL utility.
```

### Step 2: Permanent OpenVPN directory.

Create OpenVPN directory on **host machine**.

This directory will be populated with configuration files, keys, certificates, etc.

```bash
mkdir -p /etc/openvpn-${OVPN_SERVER_NAME}
```

### Step 3: Run container and attach to it.

To run container and create new instance of container's shell execute the following snippet on **host machine**.

```bash
docker run \
  -it \
  --rm \
  --mount type=bind,source=/etc/openvpn-${OVPN_SERVER_NAME},target=/etc/openvpn \
  eahome00/centos7-openvpn:2.4.9 \
  /bin/bash -l
```

### Step 4: Set configuration variables in container.

Execute the snippet from first step in **container**. 

Don't forget about your changes to configuration variables.

### Step 5: Easy RSA and cryptographic magic.

Execute the following snippet in **container**.

In most cases you can run this snippet as is since it is very generic.

Check annotations to understand what is this script performs.

```bash
# Download Easy RSA and unpack to /etc/openvpn/easy-rsa.
curl -sL https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.4/EasyRSA-3.0.4.tgz | tar xz -C ${OVPN_SERVER_ROOT}
mv ${OVPN_SERVER_ROOT}/EasyRSA-3.0.4 ${EASY_RSA_ROOT}

# Populate Easy RSA vars.
echo "set_var EASYRSA_KEY_SIZE ${RSA_KEY_SIZE}" > ${EASY_RSA_ROOT}/vars

# Create the PKI, set up the CA, the DH params and the server + client certificates.
cd ${EASY_RSA_ROOT}
./easyrsa init-pki
./easyrsa --batch build-ca nopass
if [ "${USE_PUBLIC_DH_TOOL}" = "1" ]; then
  curl https://2ton.com.au/getprimes/random/dhparam/${DH_KEY_SIZE} > dh.pem
else
  openssl dhparam -out dh.pem ${DH_KEY_SIZE}
fi
./easyrsa build-server-full server nopass
./easyrsa build-client-full client nopass
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

# Generate TLS-auth key.
openvpn --genkey --secret /etc/openvpn/tls-auth.key

# Copy all the generated files to /etc/openvpn.
cp pki/ca.crt \
   pki/private/ca.key \
   dh.pem \
   pki/issued/server.crt \
   pki/private/server.key \
   pki/crl.pem \
   ${OVPN_SERVER_ROOT}
```

### Step 6: Generating OpenVPN server configuration file.

Execute the following snippet in **container**.

This file is primary configuration of OpenVPN server. 

You should customize this file to your needs.

By default OpenVPN server forces Google DNS usage, serves multiple clients, and compresses data using LZO.

```bash
# Generate server configuration file.
cat > ${OVPN_SERVER_ROOT}/server.conf << EOF
port ${OVPN_SERVER_PORT}
proto ${OVPN_SERVER_PROTOCOL,,}
dev tun
user nobody
group nobody
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
push "redirect-gateway def1 bypass-dhcp"
crl-verify crl.pem
ca ca.crt
cert server.crt
key server.key
tls-auth tls-auth.key 0
dh dh.pem
auth SHA256
cipher ${OVPN_SERVER_CIPHER}
ncp-ciphers ${OVPN_SERVER_CIPHER}
tls-server
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
duplicate-cn
compress lz4-v2
EOF
```

### Step 7: Generating OpenVPN client configuration file.

Execute the following snippet in **container**.

This file is used by OpenVPN clients.

```bash
# Generate client configuration file.
cat > ${OVPN_SERVER_ROOT}/client.ovpn << EOF
client
proto ${OVPN_SERVER_PROTOCOL,,}
remote ${OVPN_SERVER_IP} ${OVPN_SERVER_PORT}
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
auth-nocache
cipher ${OVPN_SERVER_CIPHER}
tls-client
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3
compress lz4-v2
<ca>
$(cat ${EASY_RSA_ROOT}/pki/ca.crt)
</ca>
<cert>
$(cat ${EASY_RSA_ROOT}/pki/issued/client.crt)
</cert>
<key>
$(cat ${EASY_RSA_ROOT}/pki/private/client.key)
</key>
key-direction 1
<tls-auth>
$(cat ${OVPN_SERVER_ROOT}/tls-auth.key)
</tls-auth>
EOF
```

### Step 8: Generating OpenVPN server startup file.

Execute the following snippet in **container**.

```bash
cat > ${OVPN_SERVER_ROOT}/server.sh << EOF
#!/bin/sh

# Create TUN/TAP device if it doesn't exist.
# See https://groups.google.com/d/msg/docker-user/2jFeDGJj36E/XjFh5i1ARpcJ
mkdir -p /dev/net
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun

# Check TUN/TAP device. It should output "cat: /dev/net/tun: File descriptor in bad state" and exit with code 1.
cat /dev/net/tun || true

# Enable and configure NAT.
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE || 
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE

openvpn --config ${OVPN_SERVER_ROOT}/server.conf --cd ${OVPN_SERVER_ROOT}
EOF
```

### Step 9: Set up permissions.

Execute the following snippet in **container**.

```bash
chown -R root:root ${OVPN_SERVER_ROOT}
chmod -R 600 ${OVPN_SERVER_ROOT}
chmod u+x ${OVPN_SERVER_ROOT}/server.sh
```

### Step 10: Stop container and detach from it.

Press `CTRL+C` or type `exit` in **container's shell**.

### Step 11: Copy OpenVPN client configuration.

`client.ovpn` is accessible on host machine at `/etc/openvpn-80UDP/client.ovpn`.

Use SCP to transfer it or just copy-paste.

`scp root@docker-host:/etc/openvpn-80UDP/client.ovpn ~/80UDP.ovpn`

### Step 12: Run OpenVPN server.

Execute the following snippet on **host machine** to run OpenVPN server in **foreground**:

```bash
docker run \
  -it \
  --rm \
  --cap-add=NET_ADMIN \
  --mount type=bind,source=/etc/openvpn-${OVPN_SERVER_NAME},target=/etc/openvpn,readonly \
  -p 0.0.0.0:${OVPN_SERVER_PORT}:${OVPN_SERVER_PORT}/${OVPN_SERVER_PROTOCOL} \
  --name openvpn-${OVPN_SERVER_NAME} \
  --log-driver=json-file \
  --log-opt max-size=8M \
  --log-opt max-file=1 \
  eahome00/centos7-openvpn:2.4.9 \
  /etc/openvpn/server.sh
```

Execute the following snippet on **host machine** to run OpenVPN server in **background**:

```bash
docker run \
  -d \
  --restart=unless-stopped \
  --cap-add=NET_ADMIN \
  --mount type=bind,source=/etc/openvpn-${OVPN_SERVER_NAME},target=/etc/openvpn,readonly \
  -p 0.0.0.0:${OVPN_SERVER_PORT}:${OVPN_SERVER_PORT}/${OVPN_SERVER_PROTOCOL} \
  --name openvpn-${OVPN_SERVER_NAME} \
  --log-driver=json-file \
  --log-opt max-size=8M \
  --log-opt max-file=1 \
  eahome00/centos7-openvpn:2.4.9 \
  /etc/openvpn/server.sh
```

### Step 13: Docker Compose config (optional).

1. Create root directory for Docker Compose config and navigate to it:

```bash
mkdir ~/openvpn-${OVPN_SERVER_NAME} && cd ~/openvpn-${OVPN_SERVER_NAME}
```

2. Generate `docker-compose.yaml` file:

```bash
cat > docker-compose.yaml << EOF
version: '3.5'

services:
  server:
    image: eahome00/centos7-openvpn:2.4.9
    command: '/etc/openvpn/server.sh'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    ports:
      - ${OVPN_SERVER_PORT}:${OVPN_SERVER_PORT}/$(echo ${OVPN_SERVER_PROTOCOL} | tr "[:upper:]" "[:lower:]")
    volumes:
      - type: bind
        source: /etc/openvpn-${OVPN_SERVER_NAME}
        target: /etc/openvpn
        read_only: true
    logging:
      driver: json-file
      options:
        max-size: 8MB
        max-file: '1'
EOF
```
3. Run OpenVPN server:

```bash
docker-compose up -d
```

## Credits

Big thanks to maintainers and contributors of the following projects for their amazing work:

* https://github.com/Nyr/openvpn-install

* https://github.com/Angristan/OpenVPN-install
