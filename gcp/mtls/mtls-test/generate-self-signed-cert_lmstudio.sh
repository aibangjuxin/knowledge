#!/bin/bash

set -e

# 设置证书有效期和默认信息
CERT_DURATION=3650
COUNTRY="CN"
ORGANIZATION="Test Organization"
CITY="Test City"
EMAIL="test@example.com"

# 定义文件名
ROOT_KEY="root.key"
ROOT_CERT="root.crt"
INTERMEDIATE_KEY="intermediate.key"
INTERMEDIATE_CSR="intermediate.csr"
INTERMEDIATE_CERT="intermediate.crt"

# 检查是否安装了 OpenSSL
if ! command -v openssl &> /dev/null; then
  echo "错误: OpenSSL 未找到，请先安装 OpenSSL。"
  exit 1
fi

echo "开始生成证书..."

# 生成根证书私钥和证书
echo "生成根证书私钥..."
openssl genrsa -out "$ROOT_KEY" 2048

echo "生成根证书..."
openssl req -x509 -new -nodes -key "$ROOT_KEY" \
  -sha256 -days "$CERT_DURATION" \
  -out "$ROOT_CERT" \
  -subj "/C=$COUNTRY/O=$ORGANIZATION/L=$CITY/CN=Root CA/emailAddress=$EMAIL"

# 生成中间证书私钥
echo "生成中间证书私钥..."
openssl genrsa -out "$INTERMEDIATE_KEY" 2048

# 生成中间证书CSR
echo "生成中间证书CSR..."
openssl req -new -key "$INTERMEDIATE_KEY" \
  -out "$INTERMEDIATE_CSR" \
  -subj "/C=$COUNTRY/O=$ORGANIZATION/L=$CITY/CN=Intermediate CA/emailAddress=$EMAIL"

# 使用根证书签发中间证书
echo "使用根证书签发中间证书..."
openssl x509 -req -in "$INTERMEDIATE_CSR" \
  -CA "$ROOT_CERT" -CAkey "$ROOT_KEY" \
  -CAcreateserial -out "$INTERMEDIATE_CERT" \
  -days "$CERT_DURATION" -sha256 \
  -extfile <(printf "\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,cRLSign,keyCertSign\n")

echo ""
echo "证书生成完成:"
echo "  根证书: $ROOT_CERT"
echo "  根证书私钥: $ROOT_KEY"
echo "  中间证书: $INTERMEDIATE_CERT"
echo "  中间证书私钥: $INTERMEDIATE_KEY"
echo "  中间证书CSR: $INTERMEDIATE_CSR"

echo ""
echo "注意：这些证书仅用于测试和开发目的。在生产环境中，请使用可信CA签发的证书。"

exit 0
