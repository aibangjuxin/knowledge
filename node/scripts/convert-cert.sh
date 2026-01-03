#!/bin/bash
# 证书格式转换脚本
# 将 PKCS12 格式转换为 PEM 格式（供 Node.js 使用）

set -e

# 输入参数
P12_FILE="${1:-/opt/keystore/mycoat-sbrt.p12}"
PASSWORD="${2:-${KEY_STORE_PWD}}"
OUTPUT_CERT="${3:-/opt/keystore/tls.crt}"
OUTPUT_KEY="${4:-/opt/keystore/tls.key}"

echo "Converting PKCS12 to PEM format..."
echo "Input: $P12_FILE"
echo "Output Cert: $OUTPUT_CERT"
echo "Output Key: $OUTPUT_KEY"

# 检查输入文件是否存在
if [ ! -f "$P12_FILE" ]; then
    echo "Error: PKCS12 file not found: $P12_FILE"
    exit 1
fi

# 检查密码是否提供
if [ -z "$PASSWORD" ]; then
    echo "Error: Password not provided. Set KEY_STORE_PWD environment variable or pass as second argument."
    exit 1
fi

# 提取证书
openssl pkcs12 -in "$P12_FILE" \
    -passin "pass:$PASSWORD" \
    -out "$OUTPUT_CERT" \
    -clcerts -nokeys

# 提取私钥
openssl pkcs12 -in "$P12_FILE" \
    -passin "pass:$PASSWORD" \
    -out "$OUTPUT_KEY" \
    -nocerts -nodes

# 设置权限
chmod 644 "$OUTPUT_CERT"
chmod 600 "$OUTPUT_KEY"

echo "Conversion completed successfully!"
echo "Certificate: $OUTPUT_CERT"
echo "Private Key: $OUTPUT_KEY"
