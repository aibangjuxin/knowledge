#!/bin/bash
# 用法: ./check-tls-secret.sh <secret-name> <namespace>

set -e

SECRET_NAME=$1
NAMESPACE=$2

if [ -z "$SECRET_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "用法: $0 <secret-name> <namespace>"
  exit 1
fi

echo "🔍 检查 Secret: $SECRET_NAME (namespace: $NAMESPACE)"
echo "------------------------------------------------------"

# 1. 确认 Secret 类型
SECRET_TYPE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')
if [ "$SECRET_TYPE" != "kubernetes.io/tls" ]; then
  echo "❌ Secret 类型错误: $SECRET_TYPE (必须是 kubernetes.io/tls)"
  exit 1
else
  echo "✅ Secret 类型正确: $SECRET_TYPE"
fi

# 2. 导出证书和私钥
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/tls.crt
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/tls.key

# 3. 校验证书和私钥是否匹配
CRT_MD5=$(openssl x509 -in /tmp/tls.crt -noout -modulus | openssl md5)
KEY_MD5=$(openssl rsa -in /tmp/tls.key -noout -modulus | openssl md5)

if [ "$CRT_MD5" != "$KEY_MD5" ]; then
  echo "❌ 证书和私钥不匹配"
  echo "CRT: $CRT_MD5"
  echo "KEY: $KEY_MD5"
  exit 1
else
  echo "✅ 证书和私钥匹配"
fi

# 4. 显示证书基本信息
echo "------------------------------------------------------"
echo "📜 证书信息:"
openssl x509 -in /tmp/tls.crt -noout -subject -issuer -dates -ext subjectAltName || true

# 5. 检查是否包含中间证书
CHAIN_COUNT=$(grep -c "END CERTIFICATE" /tmp/tls.crt)
if [ "$CHAIN_COUNT" -gt 1 ]; then
  echo "✅ 证书链完整, 包含 $CHAIN_COUNT 个证书"
else
  echo "⚠️ 证书链可能不完整, 仅检测到 1 个证书"
  echo "   如果使用的是 CA 签发的证书, 请确认已包含中间证书"
fi

echo "------------------------------------------------------"
echo "🔎 检查完成"