#!/bin/bash

# Default password if not set
CERT_PWD=${HTTPS_CERT_PWD:-"changeit"}

echo "Generating Self-Signed Certificates..."
echo "Using Password: $CERT_PWD"

# Generate Private Key (Encrypted with AES-128)
openssl genrsa -aes128 -passout pass:$CERT_PWD -out key.pem 2048

# Generate Certificate (using the key)
openssl req -new -x509 -key key.pem -out cert.pem -days 365 -passin pass:$CERT_PWD -subj '/CN=localhost/O=Demo/C=US'

echo "Certificates generated: key.pem, cert.pem"
