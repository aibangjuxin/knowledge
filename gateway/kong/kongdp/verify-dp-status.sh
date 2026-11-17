#!/bin/bash

# Kong Data Plane Status Verification Script
# Usage: ./verify-dp-status.sh [-n namespace] [-s secret-name] [-c cp-service]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="aibang-int-kdp"
SECRET_NAME="lex-tls-secret"
LABEL_SELECTOR="app=busybox-app"
CP_SERVICE="kong-cp"
CP_PORT="8005"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:s:c:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    c) CP_SERVICE="$OPTARG" ;;
    h)
      echo "Usage: $0 [-n namespace] [-s secret-name] [-c cp-service]"
      echo "  -n: Kubernetes namespace (default: aibang-int-kdp)"
      echo "  -s: TLS secret name (default: lex-tls-secret)"
      echo "  -c: Control Plane service name (default: kong-cp)"
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
echo -e "${GREEN}Kong Data Plane Status Verification${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Secret: ${YELLOW}$SECRET_NAME${NC}"
echo -e "CP Service: ${YELLOW}$CP_SERVICE${NC}"

# 1. Infrastructure Layer Check
print_header "1. 基础设施层检查 (Infrastructure Health)"

print_info "1.1 检查 Kong DP Pods 状态..."
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
# DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -eq 0 ]; then
  print_error "未找到 Kong DP Pods (label: $LABEL_SELECTOR)"
  print_info "尝试查找其他可能的 Kong Pods..."
  kubectl get pods -n "$NAMESPACE" | grep -i kong || print_error "未找到任何 Kong 相关 Pods"
else
  print_success "找到 $POD_COUNT 个 Kong DP Pod(s)"
  echo "$DP_PODS" | jq -r '.items[] | "\(.metadata.name) | Status: \(.status.phase) | Ready: \(.status.containerStatuses[0].ready) | Restarts: \(.status.containerStatuses[0].restartCount) | IP: \(.status.podIP)"'
  
  # Check for unhealthy pods
  UNHEALTHY=$(echo "$DP_PODS" | jq -r '.items[] | select(.status.phase != "Running" or .status.containerStatuses[0].ready != true) | .metadata.name')
  if [ -n "$UNHEALTHY" ]; then
    print_warning "发现不健康的 Pods: $UNHEALTHY"
  fi
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
  
  print_info "1.3 检查资源使用情况..."
  kubectl top pod "$DP_POD_NAME" -n "$NAMESPACE" 2>/dev/null || print_warning "无法获取资源使用情况 (metrics-server 可能未安装)"
fi

# 2. Log Analysis
print_header "2. 日志层分析 (Log Analysis)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "2.1 分析最近 100 行日志..."
  LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
  
  if echo "$LOGS" | grep -q "control_plane: connected"; then
    print_success "DP 已成功连接到 CP (control_plane: connected)"
  else
    print_error "未找到成功连接的日志信号"
  fi
  
  if echo "$LOGS" | grep -q "received initial configuration snapshot"; then
    print_success "DP 已接收到初始配置快照"
  else
    print_warning "未找到配置快照接收日志"
  fi
  
  if echo "$LOGS" | grep -q "failed to connect to control plane"; then
    print_error "发现连接失败日志"
    echo "$LOGS" | grep "failed to connect" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "certificate verify failed"; then
    print_error "发现证书验证失败日志"
    echo "$LOGS" | grep "certificate" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "cluster: reconnecting"; then
    print_warning "DP 正在重连 (连接不稳定)"
  fi
  
  print_info "关键日志摘要 (最近 5 条):"
  echo "$LOGS" | grep -E "control_plane|cluster|certificate|configuration" | tail -5 || print_info "无相关日志"
else
  print_error "无法分析日志: 未找到 DP Pod"
fi

# 3. Control Plane Verification
print_header "3. 控制面层验证 (Control Plane Verification)"

print_info "3.1 查询 CP 集群状态..."
CP_POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$CP_POD" ]; then
  print_success "找到 CP Pod: $CP_POD"
  CLUSTER_STATUS=$(kubectl exec -it "$CP_POD" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
  
  DP_COUNT=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
  print_info "CP 注册的 DP 节点数: $DP_COUNT"
  
  if [ "$DP_COUNT" -gt 0 ]; then
    print_success "CP 集群状态:"
    echo "$CLUSTER_STATUS" | jq -r '.data_planes[] | "  ID: \(.id) | IP: \(.ip) | Status: \(.status) | Last Seen: \(.last_seen)s | Version: \(.version)"'
    
    # Check if our DP pod IP is registered
    if [ -n "$DP_POD_NAME" ]; then
      DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
      if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
        print_success "当前 DP Pod ($DP_IP) 已在 CP 注册"
      else
        print_error "当前 DP Pod ($DP_IP) 未在 CP 注册表中找到"
      fi
    fi
  else
    print_error "CP 未注册任何 DP 节点"
  fi
else
  print_warning "未找到 CP Pod (label: app=kong-cp), 跳过 CP 验证"
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
    echo "$DNS_TEST" | grep -E "Address|Name" | head -3
  fi
  
  # Test TCP connectivity with curl
  print_info "4.2 测试 TCP 连接..."
  CONN_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- timeout 5 sh -c "curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT 2>&1" || echo "CONNECTION_FAILED")
  
  if echo "$CONN_TEST" | grep -q "Connected to"; then
    print_success "TCP 连接成功 (网络层通畅)"
  elif echo "$CONN_TEST" | grep -q "SSL certificate problem"; then
    print_warning "TCP 连接成功，但证书验证失败 (网络通，需检查证书)"
  elif echo "$CONN_TEST" | grep -q "Connection timed out\|CONNECTION_FAILED"; then
    print_error "连接超时 (检查防火墙规则/安全组)"
  elif echo "$CONN_TEST" | grep -q "Could not resolve host"; then
    print_error "无法解析主机名 (DNS 问题)"
  else
    print_warning "连接测试结果不明确"
    echo "$CONN_TEST" | head -5
  fi
else
  print_error "无法进行网络测试: 未找到 DP Pod"
fi

# 5. Security & Certificate Verification
print_header "5. 安全层与证书验证 (Certificate & Security)"

print_info "5.1 检查 TLS Secret 是否存在..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  print_success "Secret '$SECRET_NAME' 存在"
  
  print_info "5.2 验证证书内容..."
  CERT_INFO=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -subject -enddate 2>/dev/null || echo "CERT_ERROR")
  
  if [ "$CERT_INFO" = "CERT_ERROR" ]; then
    print_error "无法读取或解析证书"
  else
    print_success "证书信息:"
    echo "$CERT_INFO" | while IFS= read -r line; do
      if echo "$line" | grep -q "subject="; then
        echo "  Subject: $(echo "$line" | sed 's/subject=//')"
      elif echo "$line" | grep -q "notAfter="; then
        EXPIRY=$(echo "$line" | sed 's/notAfter=//')
        echo "  过期时间: $EXPIRY"
        
        # Check if certificate is expired
        EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" "+%s" 2>/dev/null || echo "0")
        NOW_EPOCH=$(date "+%s")
        if [ "$EXPIRY_EPOCH" -lt "$NOW_EPOCH" ]; then
          print_error "证书已过期!"
        else
          DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
          if [ "$DAYS_LEFT" -lt 30 ]; then
            print_warning "证书将在 $DAYS_LEFT 天后过期"
          else
            print_success "证书有效 (剩余 $DAYS_LEFT 天)"
          fi
        fi
      fi
    done
  fi
  
  print_info "5.3 检查证书详细信息..."
  kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -text 2>/dev/null | grep -E "Subject:|Issuer:|Not Before|Not After" || print_warning "无法获取详细证书信息"
  
else
  print_error "Secret '$SECRET_NAME' 不存在"
  print_info "可用的 Secrets:"
  kubectl get secrets -n "$NAMESPACE" | grep -i tls || echo "  未找到 TLS secrets"
fi

if [ -n "$DP_POD_NAME" ]; then
  print_info "5.4 检查 DP Pod 内挂载的证书..."
  MOUNTED_CERT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- ls -la /etc/secrets/kong-cluster-cert/ 2>/dev/null || echo "NOT_MOUNTED")
  
  if [ "$MOUNTED_CERT" = "NOT_MOUNTED" ]; then
    print_warning "证书未挂载到 /etc/secrets/kong-cluster-cert/ (可能使用其他路径)"
  else
    print_success "证书已挂载:"
    echo "$MOUNTED_CERT"
  fi
fi

# Summary
print_header "6. 诊断总结 (Summary)"

echo -e "${BLUE}检查项完成情况:${NC}"
echo "  [1] 基础设施层: Pod 状态、资源、事件"
echo "  [2] 日志层: 连接信号、配置快照、错误日志"
echo "  [3] 控制面层: CP 注册状态验证"
echo "  [4] 网络层: DNS、TCP 连通性测试"
echo "  [5] 安全层: 证书有效性、挂载状态"

print_info "建议: 查看上述输出中的 ❌ 和 ⚠️ 标记，优先解决标记为错误的问题"

echo -e "\n${GREEN}脚本执行完成!${NC}\n"
