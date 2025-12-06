#!/bin/bash

# Kong Data Plane Status Verification Script (Gemini Optimized)
# Usage: ./verify-dp-status-gemini.sh [-n namespace] [-l label-selector] [-s secret-name]
#
# Optimization:
# - Automatically detects CP address from DP Deployment env vars (KONG_CLUSTER_CONTROL_PLANE)
# - Enhanced error handling and reporting

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="aibang-int-kdp"
#LABEL_SELECTOR="app=kong-dp"
# add a labels 
# kubectl label deployment <deployment-name> <label-key>=<label-value> -n <namespace>
# kubectl label deployment busybox-app app=busybox-app -n bass-int-kdp
LABEL_SELECTOR="app=busybox-app"
SECRET_NAME="lex-tls-secret"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:l:s:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    l) LABEL_SELECTOR="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    h)
      echo "Usage: $0 [-n namespace] [-l label-selector] [-s secret-name]"
      echo "  -n: Kubernetes namespace (default: $NAMESPACE)"
      echo "  -l: DP Deployment label selector (default: $LABEL_SELECTOR)"
      echo "  -s: TLS secret name (default: $SECRET_NAME)"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Helper functions
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Main script
echo -e "${GREEN}Kong Data Plane Status Verification (Optimized)${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Label Selector: ${YELLOW}$LABEL_SELECTOR${NC}"

# 0. Dynamic Configuration Discovery
print_header "0. 动态配置发现 (Configuration Discovery)"

print_info "0.1 查找 Kong DP Deployment..."
DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$DP_DEPLOYMENT" ]; then
  print_error "未找到带有标签 '$LABEL_SELECTOR' 的 Deployment"
  print_info "请检查 Namespace 或 Label Selector 是否正确"
  exit 1
fi

print_success "找到 Deployment: $DP_DEPLOYMENT"

print_info "0.2 从 Deployment 获取 CP 连接信息..."
# Try to get KONG_CLUSTER_CONTROL_PLANE from env
CP_ENV_VALUE=$(kubectl get deployment "$DP_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KONG_CLUSTER_CONTROL_PLANE")].value}' 2>/dev/null || echo "")

if [ -z "$CP_ENV_VALUE" ]; then
  print_warning "未在环境变量中找到 KONG_CLUSTER_CONTROL_PLANE"
  print_info "尝试使用默认值 kong-cp:8005"
  CP_SERVICE="kong-cp"
  CP_PORT="8005"
else
  print_success "发现配置 KONG_CLUSTER_CONTROL_PLANE=$CP_ENV_VALUE"
  # Parse host and port
  # Handle cases like "kong-cp:8005", "https://kong-cp:8005", "kong-cp" (default 8005)
  CLEAN_VAL=${CP_ENV_VALUE#*://} # Remove protocol if present
  
  if [[ "$CLEAN_VAL" == *":"* ]]; then
    CP_SERVICE=$(echo "$CLEAN_VAL" | cut -d: -f1)
    CP_PORT=$(echo "$CLEAN_VAL" | cut -d: -f2)
  else
    CP_SERVICE="$CLEAN_VAL"
    CP_PORT="8005" # Default port if not specified
  fi
fi

echo -e "CP Service Host: ${YELLOW}$CP_SERVICE${NC}"
echo -e "CP Service Port: ${YELLOW}$CP_PORT${NC}"


# 1. Infrastructure Layer Check
print_header "1. 基础设施层检查 (Infrastructure Health)"

print_info "1.1 检查 Kong DP Pods 状态..."
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -eq 0 ]; then
  print_error "未找到 Kong DP Pods"
  exit 1
else
  print_success "找到 $POD_COUNT 个 Kong DP Pod(s)"
  echo "$DP_PODS" | jq -r '.items[] | "\(.metadata.name) | Status: \(.status.phase) | Ready: \(.status.containerStatuses[0].ready) | Restarts: \(.status.containerStatuses[0].restartCount) | IP: \(.status.podIP)"'
fi

# Get first pod name for further checks
DP_POD_NAME=$(echo "$DP_PODS" | jq -r '.items[0].metadata.name // empty')

if [ -n "$DP_POD_NAME" ]; then
  print_info "1.2 检查 Pod 事件..."
  EVENTS=$(kubectl describe pod "$DP_POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 10 "Events:" || echo "无法获取事件")
  if echo "$EVENTS" | grep -qE "Error|Failed|BackOff"; then
    print_error "发现异常事件:"
    echo "$EVENTS" | grep -E "Error|Failed|BackOff" | tail -5
  else
    print_success "未发现异常事件"
  fi
fi

# 2. Log Analysis
print_header "2. 日志层分析 (Log Analysis)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "2.1 分析最近 100 行日志..."
  LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
  
  if echo "$LOGS" | grep -q "control_plane: connected"; then
    print_success "DP 已成功连接到 CP (control_plane: connected)"
  elif echo "$LOGS" | grep -q "received initial configuration snapshot"; then
    print_success "DP 已接收到初始配置快照 (隐含连接成功)"
  else
    print_warning "未找到明确的连接成功信号 (可能是日志滚动了)"
  fi
  
  if echo "$LOGS" | grep -q "failed to connect to control plane"; then
    print_error "发现连接失败日志"
    echo "$LOGS" | grep "failed to connect" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "certificate verify failed"; then
    print_error "发现证书验证失败日志"
    echo "$LOGS" | grep "certificate" | tail -3
  fi
else
  print_error "无法分析日志: 未找到 DP Pod"
fi

# 3. Control Plane Verification
print_header "3. 控制面层验证 (Control Plane Verification)"

# Try to find CP pod based on CP Service name (heuristic)
# Assuming CP deployment has label app=kong-cp or similar, but let's try to guess from service
print_info "3.1 尝试查找 CP Pod..."
# Heuristic: try to find a pod that looks like the CP service name
CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" | grep "${CP_SERVICE%-*}" | grep -v "$DP_POD_NAME" | head -1 | awk '{print $1}')

if [ -n "$CP_POD_GUESS" ]; then
  print_info "推测 CP Pod 为: $CP_POD_GUESS"
  CLUSTER_STATUS=$(kubectl exec -it "$CP_POD_GUESS" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
  
  DP_COUNT=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
  print_info "CP 注册的 DP 节点数: $DP_COUNT"
  
  if [ "$DP_COUNT" -gt 0 ]; then
    if [ -n "$DP_POD_NAME" ]; then
      DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
      if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
        print_success "当前 DP Pod ($DP_IP) 已在 CP 注册"
      else
        print_error "当前 DP Pod ($DP_IP) 未在 CP 注册表中找到"
      fi
    fi
  else
    print_warning "CP 返回的 DP 列表为空 (或者无法连接 CP Admin API)"
  fi
else
  print_warning "无法自动定位 CP Pod，跳过 CP 端验证"
fi

# 4. Network Connectivity
print_header "4. 网络层连通性探测 (Network Connectivity)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "4.1 测试 DP 到 CP 的网络连接 ($CP_SERVICE:$CP_PORT)..."
  
  # Test DNS resolution
  DNS_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- nslookup "$CP_SERVICE" 2>&1 || echo "DNS_FAILED")
  if echo "$DNS_TEST" | grep -q "DNS_FAILED\|can't resolve"; then
    print_error "DNS 解析失败: $CP_SERVICE"
  else
    print_success "DNS 解析成功"
  fi
  
  # Test TCP connectivity with curl
  print_info "4.2 测试 TCP 连接..."
  # Use the dynamically discovered CP_SERVICE and CP_PORT
  CONN_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- timeout 5 sh -c "curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT 2>&1" || echo "CONNECTION_FAILED")
  
  if echo "$CONN_TEST" | grep -q "Connected to"; then
    print_success "TCP 连接成功 (网络层通畅)"
  elif echo "$CONN_TEST" | grep -q "SSL certificate problem"; then
    print_warning "TCP 连接成功，但证书验证失败 (网络通，需检查证书)"
  elif echo "$CONN_TEST" | grep -q "Connection timed out\|CONNECTION_FAILED"; then
    print_error "连接超时 (检查防火墙规则/安全组)"
  else
    print_warning "连接测试结果不明确"
    echo "$CONN_TEST" | head -5
  fi
else
  print_error "无法进行网络测试: 未找到 DP Pod"
fi

# 5. Security & Certificate Verification
print_header "5. 安全层与证书验证 (Certificate & Security)"

print_info "5.1 检查 TLS Secret '$SECRET_NAME'..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  print_success "Secret 存在"
  
  # Check expiry
  CERT_EXPIRY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  if [ -n "$CERT_EXPIRY" ]; then
    print_info "证书过期时间: $CERT_EXPIRY"
    # Simple check if expired (requires date utils, skipping complex logic for brevity, just showing date)
  fi
else
  print_error "Secret '$SECRET_NAME' 不存在"
fi

if [ -n "$DP_POD_NAME" ]; then
  print_info "5.2 检查 DP Pod 内挂载的证书..."
  # Check env var for cert path if possible, otherwise guess default
  CERT_PATH="/etc/secrets/kong-cluster-cert/"
  MOUNTED_CERT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- ls -la $CERT_PATH 2>/dev/null || echo "NOT_MOUNTED")
  
  if [ "$MOUNTED_CERT" = "NOT_MOUNTED" ]; then
    print_warning "默认路径 $CERT_PATH 未找到证书"
  else
    print_success "证书已挂载"
  fi
fi

echo -e "\n${GREEN}脚本执行完成!${NC}\n"
