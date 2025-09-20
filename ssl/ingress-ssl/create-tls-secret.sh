#!/bin/bash

# 创建 TLS Secret 到 K8s 脚本
# Usage: ./create-tls-secret.sh <secret-name> <namespace> <cert-file> <key-file>

set -euo pipefail

SECRET_NAME=${1:-"my-tls-secret"}
NAMESPACE=${2:-"default"}
CERT_FILE=${3:-"tls.crt"}
KEY_FILE=${4:-"tls.key"}

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 检查文件是否存在
if [ ! -f "$CERT_FILE" ]; then
    print_error "证书文件不存在: $CERT_FILE"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    print_error "私钥文件不存在: $KEY_FILE"
    exit 1
fi

print_info "准备创建 TLS Secret: $SECRET_NAME"
print_info "目标 Namespace: $NAMESPACE"
print_info "证书文件: $CERT_FILE"
print_info "私钥文件: $KEY_FILE"

# 创建 namespace（如果不存在）
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_info "创建 namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
    print_success "Namespace '$NAMESPACE' 已创建"
else
    print_info "Namespace '$NAMESPACE' 已存在"
fi

# 编码证书和密钥文件
CERT_BASE64=$(base64 -w 0 "$CERT_FILE")
KEY_BASE64=$(base64 -w 0 "$KEY_FILE")

# 生成 YAML 文件
cat > tls-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: kubernetes.io/tls
data:
  tls.crt: $CERT_BASE64
  tls.key: $KEY_BASE64
EOF

print_success "YAML 文件已生成: tls-secret.yaml"

# 应用到集群
if kubectl apply -f tls-secret.yaml; then
    print_success "TLS Secret '$SECRET_NAME' 已创建到 namespace '$NAMESPACE'"
else
    print_error "创建 TLS Secret 失败"
    exit 1
fi

# 验证创建结果
echo ""
print_info "验证创建结果:"
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE"

echo ""
print_info "Secret 详细信息:"
kubectl describe secret "$SECRET_NAME" -n "$NAMESPACE"

# 清理临时 YAML 文件
rm -f tls-secret.yaml
print_info "临时文件已清理"