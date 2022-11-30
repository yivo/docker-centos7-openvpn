# docker-centos7-openvpn

Docker container with CentOS 7 and OpenVPN server.

[View on Docker Hub](https://hub.docker.com/r/eahome00/centos7-openvpn/)

## Installation Guide

This guide will walk you through the process of installing and configuring OpenVPN server as Docker container.

Get Docker daemon and follow the instructions.

### Step 1: Configuration variables

This is minimal configuration for your new OpenVPN server. 

Make changes, save somewhere and execute the following snippet on **host machine**:

```bash
    export OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH="/etc/openvpn"
      export OPENVPN_SERVER_IP=$(curl http://ipecho.net/plain)
    export OPENVPN_SERVER_PORT="80"
export OPENVPN_SERVER_PROTOCOL="udp"
    export OPENVPN_SERVER_NAME="${OPENVPN_SERVER_PORT}${OPENVPN_SERVER_PROTOCOL}"
    export OPENVPN_SERVER_HOME_DIRECTORY_PATH="${HOME}/openvpn_${OPENVPN_SERVER_NAME}"
  export OPENVPN_SERVER_CIPHER="AES-128-GCM"
           export RSA_KEY_SIZE="2048"
            export DH_KEY_SIZE="2048"
          export EASY_RSA_ROOT="${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/EasyRSA-3.1.1"
```

### Step 2: Permanent OpenVPN directory

Create OpenVPN directory on **host machine**.

This directory will be populated with configuration files, keys, certificates, etc.

```bash
mkdir -p ${OPENVPN_SERVER_HOME_DIRECTORY_PATH}
mkdir -p ${OPENVPN_SERVER_HOME_DIRECTORY_PATH}/configuration
```

### Step 3: Run container and attach to it

To run container and create new instance of container's shell execute the following snippet on **host machine**.

```bash
docker run \
  -it \
  --rm \
  --mount type=bind,source=${OPENVPN_SERVER_HOME_DIRECTORY_PATH}/configuration,target=${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH} \
  eahome00/centos7-openvpn:2.5.8 \
  /bin/bash -l
```

### Step 4: Set configuration variables in container

Execute the snippet from first step in **container**. 

Don't forget about your changes to configuration variables.

### Step 5: Easy RSA and cryptographic magic

Execute the following snippet in **container**.

Check annotations to understand what is this script performs.

```bash
# Download Easy RSA and unpack to /etc/openvpn/easy-rsa.
curl -sL https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.1/EasyRSA-3.1.1.tgz | tar xz -C ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}

# Populate Easy RSA vars.
echo "set_var EASYRSA_KEY_SIZE ${RSA_KEY_SIZE}" > ${EASY_RSA_ROOT}/vars

# Create the PKI, set up the CA, the DH params and the server + client certificates.
cd ${EASY_RSA_ROOT}
./easyrsa init-pki
rm -f vars
./easyrsa --batch build-ca nopass
openssl dhparam -out dh.pem ${DH_KEY_SIZE}
EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass
EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full client nopass
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

# Generate TLS authentication key.
openvpn --genkey secret ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/tls-auth.key

# Copy all the generated files to /etc/openvpn.
cp pki/ca.crt \
   pki/private/ca.key \
   dh.pem \
   pki/issued/server.crt \
   pki/private/server.key \
   pki/crl.pem \
   ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}
```

### Step 6: Generating OpenVPN server configuration file

Execute the following snippet in **container**.

This file is primary configuration of OpenVPN server. 

You may customize this file to fit your needs.

By default OpenVPN server forces CloudFlare DNS usage and allows to serve multiple clients.

```bash
# Generate server configuration file.
cat > ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.conf << EOF
port ${OPENVPN_SERVER_PORT}
proto ${OPENVPN_SERVER_PROTOCOL,,}4
dev tun
user nobody
group nobody
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "dhcp-option DNS 1.0.0.1"
push "dhcp-option DNS 1.1.1.1"
push "redirect-gateway def1 bypass-dhcp"
crl-verify crl.pem
ca ca.crt
cert server.crt
key server.key
tls-auth tls-auth.key 0
dh dh.pem
auth SHA256
cipher ${OPENVPN_SERVER_CIPHER}
data-ciphers ${OPENVPN_SERVER_CIPHER}
tls-server
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256
verb 3
duplicate-cn
EOF

if [[ "${OPENVPN_SERVER_PROTOCOL}" = "udp" ]]; then
  echo "explicit-exit-notify" >> ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.conf
fi
```

### Step 7: Generating OpenVPN client configuration file

Execute the following snippet in **container**.

This file is used by OpenVPN clients.

```bash
# Generate client configuration file.
cat > ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/client.ovpn << EOF
client
proto ${OPENVPN_SERVER_PROTOCOL,,}4
remote ${OPENVPN_SERVER_IP} ${OPENVPN_SERVER_PORT}
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
auth-nocache
cipher ${OPENVPN_SERVER_CIPHER}
tls-client
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256
ignore-unknown-option block-outside-dns
setenv opt block-outside-dns
verb 3
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
$(cat ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/tls-auth.key)
</tls-auth>
EOF

if [[ "${OPENVPN_SERVER_PROTOCOL}" = "udp" ]]; then
  echo "explicit-exit-notify" >> ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/client.ovpn
fi
```

### Step 8: Generating OpenVPN server startup file

Execute the following snippet in **container**.

```bash
cat > ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.sh << EOF
#!/bin/sh

# Create TUN/TAP device if it doesn't exist.
# See https://groups.google.com/d/msg/docker-user/2jFeDGJj36E/XjFh5i1ARpcJ
mkdir -p /dev/net
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun

# Check TUN/TAP device. It should output "cat: /dev/net/tun: File descriptor in bad state" and exit with code 1.
cat /dev/net/tun || true

# Enable and configure NAT.
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || { 
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
}

openvpn --config ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.conf --cd ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}
EOF
```

### Step 9: Set up permissions

Execute the following snippet in **container**.

```bash
chown -R root:root ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}
chmod -R 600 ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}
chmod 755 ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}
chmod 700 ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.sh

touch ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/ipp.txt
chown nobody:nobody ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/ipp.txt
chmod 660 ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/ipp.txt

chown nobody:nobody ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/crl.pem
chmod 400 ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/crl.pem
```

### Step 10: Stop container and detach from it

Press `CTRL+C` or type `exit` in **container's shell**.

### Step 11: Copy OpenVPN client configuration

`client.ovpn` is accessible on host machine at `/etc/openvpn-80UDP/client.ovpn`.

Use SCP to transfer it or just copy-paste.

`scp root@docker-host:/etc/openvpn-80UDP/client.ovpn ~/80UDP.ovpn`

### Step 12: Configure host

```bash
cat >> /etc/sysctl.d/99-openvpn.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

sysctl --system
```

### Step 12: Run OpenVPN server

Execute the following snippet on **host machine** to run OpenVPN server in **foreground**:

```bash
docker run \
  -it \
  --rm \
  --cap-add=NET_ADMIN \
  --mount type=bind,source=${OPENVPN_SERVER_HOME_DIRECTORY_PATH}/configuration,target=${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH},readonly \
  -p 0.0.0.0:${OPENVPN_SERVER_PORT}:${OPENVPN_SERVER_PORT}/${OPENVPN_SERVER_PROTOCOL} \
  --name openvpn_${OPENVPN_SERVER_NAME} \
  --log-driver=json-file \
  --log-opt max-size=8M \
  --log-opt max-file=1 \
  eahome00/centos7-openvpn:2.5.8 \
  ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.sh
```

Execute the following snippet on **host machine** to run OpenVPN server in **background**:

```bash
docker run \
  -d \
  --restart=unless-stopped \
  --cap-add=NET_ADMIN \
  --mount type=bind,source=${OPENVPN_SERVER_HOME_DIRECTORY_PATH}/configuration,target=${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH},readonly \
  -p 0.0.0.0:${OPENVPN_SERVER_PORT}:${OPENVPN_SERVER_PORT}/${OPENVPN_SERVER_PROTOCOL} \
  --name openvpn_${OPENVPN_SERVER_NAME} \
  --log-driver=json-file \
  --log-opt max-size=8M \
  --log-opt max-file=1 \
  eahome00/centos7-openvpn:2.5.8 \
  ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.sh
```

### Step 13: Docker Compose config (optional)

1. Generate `docker-compose.yaml` file:

```bash
cd ${OPENVPN_SERVER_HOME_DIRECTORY_PATH}

cat > docker-compose.yaml << EOF
version: "3.9"

services:
  server:
    image: eahome00/centos7-openvpn:2.5.8
    command: "${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}/server.sh"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    ports:
      - ${OPENVPN_SERVER_PORT}:${OPENVPN_SERVER_PORT}/${OPENVPN_SERVER_PROTOCOL}
    volumes:
      - type: bind
        source: ./configuration
        target: ${OPENVPN_SERVER_CONFIGURATION_DIRECTORY_PATH}
    logging:
      driver: json-file
      options:
        max-size: 8MB
        max-file: "1"
EOF
```

2. Run OpenVPN server:

```bash
docker compose up -d
```

## Credits

Big thanks to maintainers and contributors of the following projects for their amazing work:

* https://github.com/Nyr/openvpn-install

* https://github.com/Angristan/OpenVPN-install
  
* https://github.com/OpenVPN/openvpn-build
