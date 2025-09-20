#!/bin/bash

# 自签名证书生成脚本
# Usage: ./generate-self-signed-cert.sh [domain-name]

set -euo pipefail

# 默认域名
DOMAIN=${1:-"example.com"}
CERT_DIR="./certs"
KEY_FILE="$CERT_DIR/tls.key"
CERT_FILE="$CERT_DIR/tls.crt"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 创建证书目录
mkdir -p "$CERT_DIR"

print_info "生成自签名证书用于域名: $DOMAIN"

# 生成私钥
openssl genrsa -out "$KEY_FILE" 2048
print_success "私钥已生成: $KEY_FILE"

# 生成自签名证书
openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" -days 365 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Test Organization/OU=IT Department/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN,DNS:localhost,IP:127.0.0.1"

print_success "证书已生成: $CERT_FILE"

# 显示证书信息
echo ""
print_info "证书信息:"
openssl x509 -in "$CERT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)"

echo ""
print_info "文件位置:"
echo "  私钥: $(realpath $KEY_FILE)"
echo "  证书: $(realpath $CERT_FILE)"


```bash
# 一行命令生成证书
mkdir -p certs && cd certs && \
openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 365 -nodes \
    -subj "/C=UK/ST=London/L=London/O=AiBang/CN=api01.gcp.uk.aibang.com" \
    -addext "subjectAltName=DNS:api01.gcp.uk.aibang.com,DNS:*.gcp.uk.aibang.com,DNS:localhost" && \
echo "证书生成完成:" && ls -la tls.*
```