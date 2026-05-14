#!/bin/bash

# 生成包含中间证书的证书链
# Usage: ./generate-cert-chain.sh [domain]

set -euo pipefail

DOMAIN=${1:-"example.com"}
CERT_DIR="./cert-chain"

mkdir -p "$CERT_DIR"

echo "生成包含中间证书的证书链..."

# 1. 生成根CA私钥和证书
openssl genrsa -out "$CERT_DIR/ca.key" 4096
openssl req -new -x509 -days 3650 -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Root CA/CN=Root CA"

echo "✓ 根CA证书已生成"

# 2. 生成中间CA私钥和CSR
openssl genrsa -out "$CERT_DIR/intermediate.key" 2048
openssl req -new -key "$CERT_DIR/intermediate.key" -out "$CERT_DIR/intermediate.csr" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Intermediate CA/CN=Intermediate CA"

# 3. 用根CA签发中间CA证书
openssl x509 -req -in "$CERT_DIR/intermediate.csr" -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/intermediate.crt" -days 1825

echo "✓ 中间CA证书已生成"

# 4. 生成服务器私钥和CSR
openssl genrsa -out "$CERT_DIR/tls.key" 2048
openssl req -new -key "$CERT_DIR/tls.key" -out "$CERT_DIR/server.csr" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Test Server/CN=$DOMAIN"

# 5. 用中间CA签发服务器证书
cat > "$CERT_DIR/server.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/intermediate.crt" \
    -CAkey "$CERT_DIR/intermediate.key" -CAcreateserial -out "$CERT_DIR/server.crt" \
    -days 365 -extensions v3_req -extfile "$CERT_DIR/server.conf"

echo "✓ 服务器证书已生成"

# 6. 创建完整的证书链文件
cat "$CERT_DIR/server.crt" "$CERT_DIR/intermediate.crt" "$CERT_DIR/ca.crt" > "$CERT_DIR/tls.crt"

echo "✓ 证书链已创建: $CERT_DIR/tls.crt"
echo "✓ 私钥文件: $CERT_DIR/tls.key"

# 显示证书链信息
echo ""
echo "证书链包含的证书:"
grep -c "BEGIN CERTIFICATE" "$CERT_DIR/tls.crt"

# 清理临时文件
rm -f "$CERT_DIR"/*.csr "$CERT_DIR"/*.conf "$CERT_DIR"/*.srl "$CERT_DIR/server.crt"