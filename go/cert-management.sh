#!/bin/bash
# 平台证书管理脚本
# 用于生成和管理 Java PKCS12 和 Golang PEM 格式证书

set -e

# 配置参数
NAMESPACE="${NAMESPACE:-default}"
CERT_NAME="${CERT_NAME:-mycoat-sbrt}"
KEY_STORE_PWD="${KEY_STORE_PWD:-changeit}"
CERT_DAYS="${CERT_DAYS:-365}"
CERT_SUBJECT="${CERT_SUBJECT:-/C=CN/ST=Beijing/L=Beijing/O=MyCoat/CN=*.example.com}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 平台证书管理工具 ===${NC}"
echo ""

# 检查依赖
command -v openssl >/dev/null 2>&1 || { echo -e "${RED}Error: openssl is required${NC}" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is required${NC}" >&2; exit 1; }

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

cd ${TEMP_DIR}

echo -e "${YELLOW}步骤 1/5: 生成私钥和证书${NC}"
# 生成私钥和自签名证书（PEM 格式）
openssl req -x509 -newkey rsa:4096 \
    -keyout ${CERT_NAME}.key \
    -out ${CERT_NAME}.crt \
    -days ${CERT_DAYS} -nodes \
    -subj "${CERT_SUBJECT}"

echo -e "${GREEN}✓ 证书生成完成${NC}"
echo "  - 证书: ${CERT_NAME}.crt"
echo "  - 私钥: ${CERT_NAME}.key"
echo ""

echo -e "${YELLOW}步骤 2/5: 生成 PKCS12 格式（Java 使用）${NC}"
# 生成 PKCS12 格式
openssl pkcs12 -export \
    -in ${CERT_NAME}.crt \
    -inkey ${CERT_NAME}.key \
    -out ${CERT_NAME}.p12 \
    -name ${CERT_NAME} \
    -passout pass:${KEY_STORE_PWD}

echo -e "${GREEN}✓ PKCS12 证书生成完成${NC}"
echo "  - 文件: ${CERT_NAME}.p12"
echo "  - 密码: ${KEY_STORE_PWD}"
echo ""

echo -e "${YELLOW}步骤 3/5: 验证证书${NC}"
# 验证 PEM 证书
openssl x509 -in ${CERT_NAME}.crt -text -noout | grep -E "Subject:|Issuer:|Not Before|Not After" || true

# 验证 PKCS12
openssl pkcs12 -in ${CERT_NAME}.p12 -passin pass:${KEY_STORE_PWD} -noout && \
    echo -e "${GREEN}✓ PKCS12 证书验证通过${NC}" || \
    echo -e "${RED}✗ PKCS12 证书验证失败${NC}"
echo ""

echo -e "${YELLOW}步骤 4/5: 创建 Kubernetes Secret${NC}"
# 创建统一 Secret（包含两种格式）
kubectl create secret generic mycoat-keystore-unified \
    --namespace=${NAMESPACE} \
    --from-file=mycoat-sbrt.p12=${CERT_NAME}.p12 \
    --from-file=tls.crt=${CERT_NAME}.crt \
    --from-file=tls.key=${CERT_NAME}.key \
    --from-literal=password=${KEY_STORE_PWD} \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Secret 创建/更新完成${NC}"
echo "  - Namespace: ${NAMESPACE}"
echo "  - Secret: mycoat-keystore-unified"
echo ""

echo -e "${YELLOW}步骤 5/5: 验证 Secret${NC}"
# 验证 Secret
kubectl get secret mycoat-keystore-unified -n ${NAMESPACE} >/dev/null 2>&1 && \
    echo -e "${GREEN}✓ Secret 验证通过${NC}" || \
    echo -e "${RED}✗ Secret 验证失败${NC}"

# 显示 Secret 内容（不显示实际数据）
echo ""
echo "Secret 包含的文件:"
kubectl get secret mycoat-keystore-unified -n ${NAMESPACE} -o jsonpath='{.data}' | \
    jq -r 'keys[]' 2>/dev/null || \
    kubectl get secret mycoat-keystore-unified -n ${NAMESPACE} -o json | \
    grep -o '"[^"]*":' | tr -d '":' | grep -v metadata

echo ""
echo -e "${GREEN}=== 证书管理完成 ===${NC}"
echo ""
echo "使用说明:"
echo "  Java 应用使用:"
echo "    - 文件: mycoat-sbrt.p12"
echo "    - 密码: 从 Secret 的 'password' 字段读取"
echo ""
echo "  Golang 应用使用:"
echo "    - 证书: tls.crt"
echo "    - 私钥: tls.key"
echo ""
echo "证书信息:"
openssl x509 -in ${CERT_NAME}.crt -noout -dates
echo ""

# 可选：保存证书到本地
read -p "是否保存证书到当前目录? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp ${CERT_NAME}.crt ./
    cp ${CERT_NAME}.key ./
    cp ${CERT_NAME}.p12 ./
    echo -e "${GREEN}证书已保存到当前目录${NC}"
fi
