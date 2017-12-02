# docker-centos7-openvpn

Docker container with CentOS 7 and OpenVPN server.

[View on Docker Hub](https://hub.docker.com/r/eahome00/centos7-openvpn/)

## Installation Guide

This guide will walk you through the process of installing and configuring OpenVPN server as Docker container.

Get Docker and follow the instructions.

### Step 1: Configuration variables.

This is minimal configuration for your new OpenVPN server. 

Make changes, save somewhere and execute the following snippet on **host machine**.

```bash
    OVPN_SERVER_ROOT="/etc/openvpn"
      OVPN_SERVER_IP=$(curl http://ipecho.net/plain)
    OVPN_SERVER_PORT="80"
OVPN_SERVER_PROTOCOL="UDP"
    OVPN_SERVER_NAME="${OVPN_SERVER_PORT}${OVPN_SERVER_PROTOCOL}"
  OVPN_SERVER_CIPHER="AES-128-CBC"
        RSA_KEY_SIZE="3072"
         DH_KEY_SIZE="3072"
       EASY_RSA_ROOT="${OVPN_SERVER_ROOT}/easy-rsa"
```

### Step 2: Permanent OpenVPN directory.

Create OpenVPN directory on **host machine**.

```bash
mkdir -p /etc/openvpn-${OVPN_SERVER_NAME}
```

### Step 3: Run container and attach to it.

To run container and create new instance of container's shell execute the following snippet on **host machine**.

```bash
docker run \
  -it \
  --mount type=bind,source=/etc/openvpn-${OVPN_SERVER_NAME},target=/etc/openvpn \
  eahome00/centos7-openvpn \
  /bin/bash
```

### Step 4: Set configuration variables in container.

Execute the snippet from step 1 in **container**.

### Step 5: Easy RSA and cryptographic magic.

Execute the following snippet in **container**.

```bash
# Download Easy RSA and unpack to /etc/openvpn/easy-rsa.
curl -sL https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.3/EasyRSA-3.0.3.tgz | tar xz -C ${OVPN_SERVER_ROOT}
mv ${OVPN_SERVER_ROOT}/EasyRSA-3.0.3 ${EASY_RSA_ROOT}

# Populate Easy RSA vars.
echo "set_var EASYRSA_KEY_SIZE ${RSA_KEY_SIZE}" > ${EASY_RSA_ROOT}/vars

# Create the PKI, set up the CA, the DH params and the server + client certificates.
cd ${EASY_RSA_ROOT}
./easyrsa init-pki
./easyrsa --batch build-ca nopass
openssl dhparam -out dh.pem ${DH_KEY_SIZE}
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
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "redirect-gateway def1 bypass-dhcp"
crl-verify crl.pem
ca ca.crt
cert server.crt
key server.key
tls-auth tls-auth.key 0
dh dh.pem
auth SHA256
cipher AES-128-CBC
tls-server
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
duplicate-cn
compress lzo
EOF
```

### Step 7: Generating OpenVPN client configuration file.

Execute the following snippet in **container**.

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
setenv opt block-outside-dns
verb 3
compress lzo
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

mkdir -p /dev/net
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun

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

Execute the following snippet on **host machine**.

```bash
docker run \
  -it \
  --cap-add=NET_ADMIN \
  --mount type=bind,source=/etc/openvpn-${OVPN_SERVER_NAME},target=/etc/openvpn,readonly \
  -p 0.0.0.0:${OVPN_SERVER_PORT}:${OVPN_SERVER_PORT}/${OVPN_SERVER_PROTOCOL} \
  eahome00/centos7-openvpn \
  /etc/openvpn/server.sh
```
