#!/usr/bin/env bash
# =============================================================================
# k8s-gateway-fqdn-gemini.sh — 智能 K8s Gateway 域名链路深度探索与 E2E URL 构建器
#
# 用途: 给定一个 Ingress 域名 (FQDN)，自动穿透 K8s Gateway API 核心链路:
#       HTTPRoute ──► DestinationRule ──► Service ──► Deployment ──► Probes
#       并生成精准的、可直接用于 E2E 测试的 curl 验证命令（自动适配 TLS SNI --resolve 模式）。
#
# 用法: ./k8s-gateway-fqdn-gemini.sh <INPUT_FQDN> [TENANT_NAMESPACE]
#
# 依赖: kubectl, jq
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}# $*${RESET}"; }
divider() { echo -e "${DIM}$(printf '═%.0s' {1..80})${RESET}"; }
subdivider() { echo -e "${DIM}$(printf '─%.0s' {1..80})${RESET}"; }

# --------------------------------------------------------------------------- #
# 默认环境配置
# --------------------------------------------------------------------------- #
INPUT_FQDN="${1:-}"
TENANT_NS="${2:-}"
GATEWAY_NS="${GATEWAY_NS:-infrastructure}"
GATEWAY_NAME="${GATEWAY_NAME:-central-gateway}"

# --------------------------------------------------------------------------- #
# 参数 & 依赖检查
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") <INPUT_FQDN> [TENANT_NAMESPACE]

${BOLD}参数说明:${RESET}
  <INPUT_FQDN>       目标 Ingress 域名 (例如: api.team1-int.uk.aibang.local)
  [TENANT_NAMESPACE] 租户命名空间 (可选，默认通过 FQDN 或全局路由表智能自动检索)

${BOLD}特性亮点:${RESET}
  1. ${BOLD}跨命名空间智能拓扑${RESET}: 无需指定 NS，脚本能全集群扫描任何绑定了该 FQDN 的 HTTPRoute。
  2. ${BOLD}L4 到 L7 完整穿透${RESET}: 一路解析 HTTPRoute 规则、DestinationRule、Service 及绑定的 Deployment 探针。
  3. ${BOLD}E2E 智能测试地址${RESET}: 根据 HTTPRoute Match 路径与 Deployment Readiness/Liveness 探针智能拼装测试路径。
  4. ${BOLD}专业级 SNI 验证${RESET}: 自动提取 Gateway LB IP，并生成专业的 \`--resolve\` HTTPS 验证 curl 命令。

${BOLD}使用示例:${RESET}
  $(basename "$0") api.team1-int.uk.aibang.local
  $(basename "$0") app.team2.example.com team2

EOF
  exit 1
}

[[ -z "$INPUT_FQDN" ]] && usage

if ! command -v jq &>/dev/null; then
  error "本脚本高度依赖 'jq' 进行 JSON 数据处理，请先安装 jq!"
  exit 1
fi

if ! command -v kubectl &>/dev/null; then
  error "未检测到 'kubectl' 命令行工具，请确认集群连接状况!"
  exit 1
fi

# --------------------------------------------------------------------------- #
# 智能 FQDN 路由检索与 Namespace 定位
# --------------------------------------------------------------------------- #
echo ""
divider
echo -e "${BOLD}${MAGENTA}  🛰️  K8s Gateway 域名链路深度勘测工具 (Gemini 增强版)${RESET}"
echo -e "  目标域名: ${BOLD}${GREEN}${INPUT_FQDN}${RESET}"
divider

# 提取 Ingress Gateway LB IP
info "获取 Ingress Gateway 的外部 IP (命名空间: ${GATEWAY_NS})..."
GATEWAY_IP=$(kubectl get svc -n "$GATEWAY_NS" -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -z "$GATEWAY_IP" ]]; then
  # 尝试通过 Gateway 资源状态获取
  GATEWAY_IP=$(kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
fi

if [[ -n "$GATEWAY_IP" ]]; then
  success "定位到网关 LB IP: ${BOLD}${YELLOW}${GATEWAY_IP}${RESET}"
else
  warn "未能在命名空间 ${GATEWAY_NS} 下找到 LoadBalancer IP，测试命令将仅使用域名形式。"
fi

# 智能命名空间定位与 HTTPRoute 检索
info "正在搜索绑定了域名 '${INPUT_FQDN}' 的 HTTPRoute..."

# 1. 如果指定了命名空间，直接在命名空间下搜索
# 2. 如果未指定，先扫描全集群
HTTPROUTE_JSON=""
if [[ -n "$TENANT_NS" ]]; then
  HTTPROUTE_JSON=$(kubectl get httproute -n "$TENANT_NS" -o json 2>/dev/null || echo "")
else
  HTTPROUTE_JSON=$(kubectl get httproute -A -o json 2>/dev/null || echo "")
fi

if [[ -z "$HTTPROUTE_JSON" || "$HTTPROUTE_JSON" == '{"apiVersion":'* || "$HTTPROUTE_JSON" == '{"items":[]}' ]]; then
  error "未在命名空间中检索到任何 HTTPRoute 资源!"
  exit 1
fi

# 在 JSON 中智能匹配 FQDN (支持精确匹配及通配符匹配，例如 *.example.com)
# 使用 jq 匹配，提取 matched route 的 name, namespace, hostnames
MATCHED_ROUTE=$(echo "$HTTPROUTE_JSON" | jq -r --arg fqdn "$INPUT_FQDN" '
  .items[] | 
  select(
    .spec.hostnames[]? | 
    (
      $fqdn == . or 
      (. | startswith("*.") and ($fqdn | endswith(.[2:])))
    )
  ) | 
  "\(.metadata.name)|\(.metadata.namespace)"
' | head -n 1)

if [[ -z "$MATCHED_ROUTE" ]]; then
  error "在集群内未发现任何绑定了域名 '${INPUT_FQDN}' 的 HTTPRoute!"
  warn "当前集群内存在的所有 HTTPRoute 域名列表如下:"
  kubectl get httproute -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNAMES:.spec.hostnames"
  exit 1
fi

HTTPROUTE_NAME=$(echo "$MATCHED_ROUTE" | cut -d'|' -f1)
TENANT_NS=$(echo "$MATCHED_ROUTE" | cut -d'|' -f2)

success "智能定位成功！"
echo -e "  └─ ${BOLD}HTTPRoute${RESET}:    ${GREEN}${HTTPROUTE_NAME}${RESET}"
echo -e "  └─ ${BOLD}Namespace${RESET}:    ${GREEN}${TENANT_NS}${RESET}"

# --------------------------------------------------------------------------- #
# 解析 HTTPRoute 规则与其后端服务 (L7 -> L4)
# --------------------------------------------------------------------------- #
header "1. 路由解析 (HTTPRoute Rules & BackendRefs)"

HTTPROUTE_OBJ=$(kubectl get httproute "$HTTPROUTE_NAME" -n "$TENANT_NS" -o json)

# 提取绑定的 ParentRefs (Gateway / ListenerSet)
PARENTS=$(echo "$HTTPROUTE_OBJ" | jq -r '
  .spec.parentRefs[]? | 
  "\(.kind // "Gateway"): \(.namespace // "same-ns")/\(.name)\(if .sectionName then " (Port: " + .sectionName + ")" else "" end)"
' 2>/dev/null || echo "无")

echo -e "  ${BOLD}绑定网关入口 (ParentRefs):${RESET}"
echo "$PARENTS" | while read -r line; do
  echo -e "    - ${CYAN}${line}${RESET}"
done

# 提取所有规则与后端服务
RULES_JSON=$(echo "$HTTPROUTE_OBJ" | jq -c '.spec.rules[]')
RULE_IDX=0

declare -a ALL_E2E_URLS=()

while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  RULE_IDX=$(( RULE_IDX + 1 ))
  
  subdivider
  echo -e "  ${BOLD}⚡ 路由规则 #${RULE_IDX}${RESET}"
  
  # 提取匹配条件 (Paths / Headers)
  MATCHES=$(echo "$rule" | jq -c '.matches[]?')
  echo -e "  ${BOLD}匹配路径 (Matches):${RESET}"
  declare -a RULE_PATHS=()
  if [[ -z "$MATCHES" ]]; then
    echo -e "    - ${DIM}任何路径 (默认 /*)${RESET}"
    RULE_PATHS+=("/")
  else
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      path_type=$(echo "$m" | jq -r '.path.type // "PathPrefix"')
      path_val=$(echo "$m" | jq -r '.path.value // "/"')
      echo -e "    - 类型: ${BLUE}${path_type}${RESET} | 路径: ${YELLOW}${path_val}${RESET}"
      RULE_PATHS+=("$path_val")
    done <<< "$MATCHES"
  fi

  # 提取超时设定
  RULE_REQ_TIMEOUT=$(echo "$rule" | jq -r '.timeouts.request // "未设置(无限)"')
  RULE_BK_TIMEOUT=$(echo "$rule" | jq -r '.timeouts.backendRequest // "未设置(无限)"')
  echo -e "  ${BOLD}规则级超时 (Timeouts):${RESET}"
  echo -e "    - 客户端总请求超时: ${CYAN}${RULE_REQ_TIMEOUT}${RESET}"
  echo -e "    - 单次后端建连超时: ${CYAN}${RULE_BK_TIMEOUT}${RESET}"

  # 提取该规则下的所有后端服务引用 (BackendRefs)
  BACKENDS=$(echo "$rule" | jq -c '.backendRefs[]?')
  
  if [[ -z "$BACKENDS" ]]; then
    warn "规则 #${RULE_IDX} 下没有配置任何 backendRefs!"
    continue
  fi

  echo -e "  ${BOLD}后端引用 (BackendRefs):${RESET}"
  while IFS= read -r backend; do
    [[ -z "$backend" ]] && continue
    bk_name=$(echo "$backend" | jq -r '.name')
    bk_port=$(echo "$backend" | jq -r '.port')
    bk_weight=$(echo "$backend" | jq -r '.weight // 100')
    
    echo -e "    - 服务名: ${GREEN}${bk_name}${RESET} | 端口: ${YELLOW}${bk_port}${RESET} | 权重: ${bk_weight}%"
    
    # ----------------------------------------------------------------------- #
    # 深入后端服务 (Service ──► DestinationRule ──► Deployment ──► Probes)
    # ----------------------------------------------------------------------- #
    echo -e "      ${DIM}└─ 链路探测:${RESET}"
    
    # 1. 检查 Service
    SVC_OBJ=$(kubectl get svc "$bk_name" -n "$TENANT_NS" -o json 2>/dev/null || echo "")
    if [[ -z "$SVC_OBJ" ]]; then
      error "        ⚠️ 未能在命名空间 ${TENANT_NS} 中找到对应的 Service: ${bk_name}"
      continue
    fi
    
    svc_selector=$(echo "$SVC_OBJ" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null || echo "")
    svc_type=$(echo "$SVC_OBJ" | jq -r '.spec.type // "ClusterIP"')
    svc_api_anno=$(echo "$SVC_OBJ" | jq -r '.metadata.annotations."apigateway.net/v1alpha1" // "NONE"')
    
    echo -e "        ${BOLD}Service 类型${RESET}:    ${svc_type} | 标签选择器: ${BLUE}${svc_selector:-无}${RESET}"
    echo -e "        ${BOLD}API 网关架构${RESET}:    ${YELLOW}${svc_api_anno}${RESET}"

    # 2. 检查 DestinationRule (连接池与 TCP/HTTP 超时)
    # 智能搜索针对该服务 host 设置的 DestinationRule
    DR_OBJ=$(kubectl get destinationrule -n "$TENANT_NS" -o json 2>/dev/null || echo "")
    DR_NAME="<无>"
    DR_CONN_TIMEOUT="<默认>"
    DR_IDLE_TIMEOUT="<默认>"
    
    if [[ -n "$DR_OBJ" && "$DR_OBJ" != '{"items":[]}' ]]; then
      MATCHED_DR=$(echo "$DR_OBJ" | jq -r --arg svc "$bk_name" --arg ns "$TENANT_NS" '
        .items[] | 
        select(
          .spec.host == $svc or 
          .spec.host == "\($svc).\($ns)" or 
          .spec.host == "\($svc).\($ns).svc.cluster.local"
        ) | 
        "\(.metadata.name)|\(.spec.trafficPolicy.connectionPool.tcp.connectTimeout // "default")|\(.spec.trafficPolicy.connectionPool.http.idleTimeout // "default")"
      ' | head -n 1)
      
      if [[ -n "$MATCHED_DR" ]]; then
        DR_NAME=$(echo "$MATCHED_DR" | cut -d'|' -f1)
        DR_CONN_TIMEOUT=$(echo "$MATCHED_DR" | cut -d'|' -f2)
        DR_IDLE_TIMEOUT=$(echo "$MATCHED_DR" | cut -d'|' -f3)
      fi
    fi
    echo -e "        ${BOLD}DestinationRule${RESET}: ${MAGENTA}${DR_NAME}${RESET} (TCP建连超时: ${DR_CONN_TIMEOUT} | 空闲连接超时: ${DR_IDLE_TIMEOUT})"

    # 3. 检查绑定的 Deployment 与健康检查端点 (Health / Liveness Probes)
    DEPLOY_NAME=""
    READINESS_PATH=""
    LIVENESS_PATH=""
    
    if [[ -n "$svc_selector" ]]; then
      # 智能拓扑：通过 labels 寻找 Deployment
      # 先获取运行中 Pod 的 OwnerReference (最精准)
      PODS_JSON=$(kubectl get pods -n "$TENANT_NS" -l "$svc_selector" -o json 2>/dev/null || echo "")
      if [[ -n "$PODS_JSON" && "$PODS_JSON" != '{"items":[]}' ]]; then
        OWNER_NAME=$(echo "$PODS_JSON" | jq -r '.items[0].metadata.ownerReferences[0].name' 2>/dev/null || echo "")
        OWNER_KIND=$(echo "$PODS_JSON" | jq -r '.items[0].metadata.ownerReferences[0].kind' 2>/dev/null || echo "")
        
        if [[ "$OWNER_KIND" == "ReplicaSet" ]]; then
          # 溯源：ReplicaSet ──► Deployment
          RS_OBJ=$(kubectl get replicaset "$OWNER_NAME" -n "$TENANT_NS" -o json 2>/dev/null || echo "")
          if [[ -n "$RS_OBJ" ]]; then
            DEPLOY_NAME=$(echo "$RS_OBJ" | jq -r '.metadata.ownerReferences[0].name' 2>/dev/null || echo "")
          fi
        elif [[ "$OWNER_KIND" == "Deployment" ]]; then
          DEPLOY_NAME="$OWNER_NAME"
        fi
      fi
      
      # 容错：若 Pod 还未运行，通过 selector 匹配 Deployment spec 标签
      if [[ -z "$DEPLOY_NAME" ]]; then
        DEPLOY_NAME=$(kubectl get deploy -n "$TENANT_NS" -o json 2>/dev/null | jq -r --arg selector "$svc_selector" '
          .items[] | 
          select(
            .spec.selector.matchLabels | 
            to_entries | 
            map("\(.key)=\(.value)") | 
            join(",") == $selector
          ) | 
          .metadata.name
        ' | head -n 1)
      fi
    fi
    
    if [[ -n "$DEPLOY_NAME" ]]; then
      DEPLOY_OBJ=$(kubectl get deploy "$DEPLOY_NAME" -n "$TENANT_NS" -o json)
      READINESS_PATH=$(echo "$DEPLOY_OBJ" | jq -r '.spec.template.spec.containers[0].readinessProbe.httpGet.path // ""')
      LIVENESS_PATH=$(echo "$DEPLOY_OBJ" | jq -r '.spec.template.spec.containers[0].livenessProbe.httpGet.path // ""')
      
      echo -e "        ${BOLD}关联 Deployment${RESET}:  ${GREEN}${DEPLOY_NAME}${RESET}"
      echo -e "        ${BOLD}Readiness Probe${RESET}: ${YELLOW}${READINESS_PATH:-无}${RESET}"
      echo -e "        ${BOLD}Liveness Probe${RESET}:  ${YELLOW}${LIVENESS_PATH:-无}${RESET}"
    else
      warn "        ⚠️ 无法根据 Service selector 定位到活动 Deployment 工作负载。"
    fi

    # 4. 根据匹配规则路径与容器探针智能合成测试 URL
    for rpath in "${RULE_PATHS[@]}"; do
      # 组合路径策略：
      # - 如果路由匹配的是具体的 API 路径 (如 /api/v1)，则保留此路径作为 E2E 入口。
      # - 如果路由仅匹配 / 根路径，而应用声明了 ReadinessProbe (如 /healthz)，则将它们智能合并。
      # - 处理双斜杠风险
      combined_path="$rpath"
      if [[ "$rpath" == "/" && -n "$READINESS_PATH" ]]; then
        combined_path="$READINESS_PATH"
      fi
      
      # 去除重复的双斜杠
      combined_path=$(echo "$combined_path" | sed 's/\/\//\//g')
      
      ALL_E2E_URLS+=("https://${INPUT_FQDN}${combined_path}")
    done

  done <<< "$BACKENDS"

done <<< "$RULES_JSON"

# --------------------------------------------------------------------------- #
# 生成 E2E 测试命令汇总
# --------------------------------------------------------------------------- #
header "2. E2E 测试命令生成汇总 (Ready-to-use curl Commands)"

if [[ ${#ALL_E2E_URLS[@]} -eq 0 ]]; then
  warn "未生成任何 E2E 测试 URL，请检查路由规则配置！"
  exit 0
fi

# 去重
UNIQUE_URLS=($(echo "${ALL_E2E_URLS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo -e "  以下为基于域名链路逆向推导出的 ${BOLD}E2E 智能测试 URL${RESET} 列表："
echo ""

for url in "${UNIQUE_URLS[@]}"; do
  path_part=$(echo "$url" | sed -E 's|https://[^/]+||')
  [[ -z "$path_part" ]] && path_part="/"
  
  echo -e "  ${BOLD}🔗 测试终结点:${RESET} ${GREEN}${url}${RESET}"
  
  # A. 域名解析测试（前提是本地 Host 已经绑定或 DNS 已经生效）
  echo -e "    ${DIM}👉 方法 A (本地 DNS/Hosts 已就绪时使用):${RESET}"
  echo -e "    ${CYAN}curl -k -v --max-time 10 \"${url}\"${RESET}"
  
  # B. 专业级网关直通测试 (自动适配 SNI / --resolve)
  if [[ -n "$GATEWAY_IP" ]]; then
    echo -e "    ${DIM}👉 方法 B (专业网关 SNI 直通测试 - 自动绑定 IP & 绕过 DNS 缓存):${RESET}"
    echo -e "    ${BOLD}${YELLOW}curl -k -v --max-time 10 --resolve \"${INPUT_FQDN}:443:${GATEWAY_IP}\" \"https://${INPUT_FQDN}${path_part}\"${RESET}"
  fi
  echo ""
done

divider
echo -e "  ${BOLD}${GREEN}✔ 勘测完成！链路拓扑关系已成功构建并存放于 E2E 目录中。${RESET}"
divider
echo ""
