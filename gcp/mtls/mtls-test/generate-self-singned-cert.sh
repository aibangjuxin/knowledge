#!/bin/bash

set -e

# 默认参数
CERT_DIR="./certs"
DAYS_VALID=365
COMMON_NAME="localhost"

# 创建目录
mkdir -p "${CERT_DIR}"

echo "📁 生成证书目录: ${CERT_DIR}"

# 生成私钥 (2048 位)
openssl genrsa -out "${CERT_DIR}/server.key" 2048
echo "🔐 私钥生成完成: ${CERT_DIR}/server.key"

# 生成自签名证书请求 (CSR)
openssl req -new -key "${CERT_DIR}/server.key" -subj "/CN=${COMMON_NAME}" -out "${CERT_DIR}/server.csr"
echo "📄 证书请求生成完成: ${CERT_DIR}/server.csr"

# 生成自签名证书（有效期默认 365 天）
openssl x509 -req -in "${CERT_DIR}/server.csr" -signkey "${CERT_DIR}/server.key" -days "${DAYS_VALID}" -out "${CERT_DIR}/server.crt"
echo "✅ 自签名证书生成完成: ${CERT_DIR}/server.crt"

# 可选：生成 PEM 格式组合文件（方便某些服务如 nginx 使用）
cat "${CERT_DIR}/server.crt" "${CERT_DIR}/server.key" >"${CERT_DIR}/server.pem"
echo "🔗 PEM 文件生成完成: ${CERT_DIR}/server.pem"

echo ""
echo "📦 所有文件已生成:"
ls -l "${CERT_DIR}"

echo ""
echo "✅ 自签名证书生成完毕，可用于本地测试"
