#!/usr/bin/env bash

SSL_DIR=/tmp/ca
mkdir -p $SSL_DIR

openssl genrsa -out $SSL_DIR/ca.key 2048

cat <<EOF > $SSL_DIR/ca.cnf
[ req ]
default_bits = 2048
distinguished_name  = subject
prompt = no
encrypt_key = no

[ subject ]
C=US
ST=Colorado
O=Homebot
OU=Engineering
CN=homebot.test

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
EOF

# Generate root certificate
openssl req \
  -config $SSL_DIR/ca.cnf \
  -x509 \
  -new \
  -nodes \
  -key $SSL_DIR/ca.key \
  -sha256 \
  -days 398 \
  -out $SSL_DIR/ca.pem \
  -extensions v3_ca

# if [ "$(uname)" == "Darwin" ]; then
#   echo # sudo security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" $SSL_DIR/ca.pem
# elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
#   echo # sudo cp $SSL_DIR/ca.pem /usr/local/share/ca-certificates/ && sudo update-ca-certificates

#   if grep -i -q microsoft /proc/version; then
#     echo "WSL Detected"
#   fi
# else
#   echo "OS not supported"
# fi

openssl genrsa -out $SSL_DIR/homebot.key 2048

cat <<EOF > $SSL_DIR/homebot.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = US
ST = Colorado
L = Denver
O = Homebot
OU = Engineering Test
CN = *.homebot.test
[v3_req]
keyUsage = critical, digitalSignature, keyAgreement
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.homebot.test
DNS.2 = homebot.test
DNS.3 = *.homebotdev.com
DNS.4 = homebotdev.com
EOF

openssl req \
  -new \
  -config $SSL_DIR/homebot.cnf \
  -key $SSL_DIR/homebot.key \
  -out $SSL_DIR/homebot.csr

openssl x509 \
  -req \
  -extfile $SSL_DIR/homebot.cnf \
  -extensions v3_req \
  -in $SSL_DIR/homebot.csr \
  -CA $SSL_DIR/ca.pem \
  -CAkey $SSL_DIR/ca.key \
  -out $SSL_DIR/homebot.crt \
  -CAcreateserial \
  -days 398 \
  -sha256

# Create cert chain
cat $SSL_DIR/homebot.key $SSL_DIR/homebot.crt $SSL_DIR/ca.pem > $SSL_DIR/cert-chain.pem

# Move to /User location
USER_CERT_DIR=$(dirname "$0")
# mkdir -p $USER_CERT_DIR
mv /tmp/ca/* $USER_CERT_DIR/
rm -rf /tmp/ca
