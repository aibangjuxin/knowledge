#!/bin/bash
# 平台 ConfigMap 管理脚本
# 用于创建和管理 Java 和 Golang 的 ConfigMap

set -e

# 配置参数
NAMESPACE="${NAMESPACE:-default}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 平台 ConfigMap 管理工具 ===${NC}"
echo ""

# 检查依赖
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is required${NC}" >&2; exit 1; }

# 显示菜单
show_menu() {
    echo -e "${BLUE}请选择操作:${NC}"
    echo "  1) 创建 Java ConfigMap"
    echo "  2) 创建 Golang ConfigMap"
    echo "  3) 创建所有 ConfigMap"
    echo "  4) 查看现有 ConfigMap"
    echo "  5) 删除 ConfigMap"
    echo "  6) 退出"
    echo ""
}

# 创建 Java ConfigMap
create_java_configmap() {
    echo -e "${YELLOW}创建 Java ConfigMap...${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${NAMESPACE}
  name: mycoat-common-spring-conf
  labels:
    app: mycoat-platform
    language: java
data:
  server-conf.properties: |
    # 强制统一端口
    server.port=8443
    # 强制开启 SSL
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=\${KEY_STORE_PWD}
    # 统一 Context Path (Servlet 栈)
    server.servlet.context-path=/\${apiName}/v\${minorVersion}
    # 统一 Base Path (WebFlux 栈)
    spring.webflux.base-path=/\${apiName}/v\${minorVersion}
EOF
    
    echo -e "${GREEN}✓ Java ConfigMap 创建完成${NC}"
    echo "  - Namespace: ${NAMESPACE}"
    echo "  - Name: mycoat-common-spring-conf"
    echo ""
}

# 创建 Golang ConfigMap
create_golang_configmap() {
    echo -e "${YELLOW}创建 Golang ConfigMap...${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${NAMESPACE}
  name: mycoat-common-golang-conf
  labels:
    app: mycoat-platform
    language: golang
data:
  server-conf.properties: |
    # 强制统一端口
    server.port=8443
    # 强制开启 SSL
    server.ssl.enabled=true
    # Golang 使用 PEM 格式证书
    server.ssl.cert-path=/opt/keystore/tls.crt
    server.ssl.key-path=/opt/keystore/tls.key
    # 统一 Context Path
    server.context-path=/\${apiName}/v\${minorVersion}
EOF
    
    echo -e "${GREEN}✓ Golang ConfigMap 创建完成${NC}"
    echo "  - Namespace: ${NAMESPACE}"
    echo "  - Name: mycoat-common-golang-conf"
    echo ""
}

# 查看现有 ConfigMap
view_configmaps() {
    echo -e "${YELLOW}查看现有 ConfigMap...${NC}"
    echo ""
    
    echo -e "${BLUE}Java ConfigMap:${NC}"
    if kubectl get configmap mycoat-common-spring-conf -n ${NAMESPACE} >/dev/null 2>&1; then
        kubectl get configmap mycoat-common-spring-conf -n ${NAMESPACE}
        echo ""
        echo "配置内容:"
        kubectl get configmap mycoat-common-spring-conf -n ${NAMESPACE} -o jsonpath='{.data.server-conf\.properties}' | head -20
        echo ""
    else
        echo -e "${RED}✗ 不存在${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Golang ConfigMap:${NC}"
    if kubectl get configmap mycoat-common-golang-conf -n ${NAMESPACE} >/dev/null 2>&1; then
        kubectl get configmap mycoat-common-golang-conf -n ${NAMESPACE}
        echo ""
        echo "配置内容:"
        kubectl get configmap mycoat-common-golang-conf -n ${NAMESPACE} -o jsonpath='{.data.server-conf\.properties}'
        echo ""
    else
        echo -e "${RED}✗ 不存在${NC}"
    fi
    echo ""
}

# 删除 ConfigMap
delete_configmaps() {
    echo -e "${YELLOW}删除 ConfigMap...${NC}"
    echo ""
    
    read -p "删除 Java ConfigMap? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete configmap mycoat-common-spring-conf -n ${NAMESPACE} 2>/dev/null && \
            echo -e "${GREEN}✓ Java ConfigMap 已删除${NC}" || \
            echo -e "${RED}✗ Java ConfigMap 不存在或删除失败${NC}"
    fi
    
    read -p "删除 Golang ConfigMap? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete configmap mycoat-common-golang-conf -n ${NAMESPACE} 2>/dev/null && \
            echo -e "${GREEN}✓ Golang ConfigMap 已删除${NC}" || \
            echo -e "${RED}✗ Golang ConfigMap 不存在或删除失败${NC}"
    fi
    echo ""
}

# 主循环
while true; do
    show_menu
    read -p "请输入选项 (1-6): " choice
    echo ""
    
    case $choice in
        1)
            create_java_configmap
            ;;
        2)
            create_golang_configmap
            ;;
        3)
            create_java_configmap
            create_golang_configmap
            echo -e "${GREEN}=== 所有 ConfigMap 创建完成 ===${NC}"
            echo ""
            ;;
        4)
            view_configmaps
            ;;
        5)
            delete_configmaps
            ;;
        6)
            echo -e "${GREEN}退出${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${NC}"
            echo ""
            ;;
    esac
    
    read -p "按 Enter 继续..."
    clear
done
