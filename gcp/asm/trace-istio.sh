#!/usr/bin/env bash
# =============================================================================
# trace-istio.sh — Istio 全链路资产追踪脚本
# 用途: 从 URL 反向追踪 Gateway -> VirtualService -> DestinationRule -> Service -> Pods
# 依赖: kubectl, jq, bash >= 4.0
# 用法: ./trace-istio.sh --url https://api.example.com/v1/health
#       ./trace-istio.sh --url https://api.example.com/v1/health --namespace istio-system
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
MAGENTA='\033[0;35m'; WHITE='\033[1;37m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${WHITE}  $*${RESET}"; \
            echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; }
row()     { printf "  ${CYAN}%-28s${RESET} %s\n" "$1" "$2"; }

# --------------------------------------------------------------------------- #
# 参数解析
# --------------------------------------------------------------------------- #
TARGET_URL=""
HINT_NS=""          # 可选：缩小搜索范围
OUTPUT_JSON=false   # --json 输出原始 JSON

usage() {
  cat <<EOF
用法: $(basename "$0") --url <URL> [--namespace <ns>] [--json]

  --url         目标 URL，例如 https://api.example.com/v1/health
  --namespace   可选，指定 Gateway 所在 Namespace，加速搜索
  --json        同时输出原始 JSON 数据到 ./trace-output.json
  -h, --help    显示帮助

示例:
  $(basename "$0") --url https://api.example.com/v1/health
  $(basename "$0") --url https://api.example.com/v1/health --namespace istio-system --json
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)       TARGET_URL="$2"; shift 2 ;;
    --namespace) HINT_NS="$2";    shift 2 ;;
    --json)      OUTPUT_JSON=true; shift ;;
    -h|--help)   usage ;;
    *) error "未知参数: $1"; usage ;;
  esac
done

[[ -z "$TARGET_URL" ]] && { error "--url 参数必填"; usage; }

# --------------------------------------------------------------------------- #
# URL 拆解
# --------------------------------------------------------------------------- #
# 去掉 schema，提取 host 和 path
_no_schema="${TARGET_URL#*://}"
INPUT_HOST="${_no_schema%%/*}"
INPUT_PATH="/${_no_schema#*/}"
# 如果没有路径，默认 /
[[ "$INPUT_PATH" == "/$INPUT_HOST" || "$INPUT_PATH" == "/" ]] && INPUT_PATH="/"

# --------------------------------------------------------------------------- #
# 依赖检查
# --------------------------------------------------------------------------- #
for cmd in kubectl jq; do
  command -v "$cmd" &>/dev/null || { error "缺少依赖: $cmd"; exit 1; }
done

# --------------------------------------------------------------------------- #
# 全局 JSON 结果对象（用于 --json 输出）
# --------------------------------------------------------------------------- #
RESULT_JSON='{}'

append_json() {
  local key="$1" val="$2"
  RESULT_JSON=$(echo "$RESULT_JSON" | jq --argjson v "$val" ". + {\"$key\": \$v}")
}

# =============================================================================
# STEP 0: 打印追踪目标
# =============================================================================
section "🚀 Istio 全链路追踪"
row "目标 URL"   "$TARGET_URL"
row "解析 Host"  "$INPUT_HOST"
row "解析 Path"  "$INPUT_PATH"
[[ -n "$HINT_NS" ]] && row "Hint NS" "$HINT_NS"
echo ""

# =============================================================================
# STEP 1: 定位 Gateway
# =============================================================================
section "📍 STEP 1 — 定位 Gateway"

info "拉取所有 Gateway 资源..."
GW_NS_FLAG="${HINT_NS:+-n $HINT_NS}"
ALL_GW_JSON=$(kubectl get gateway ${GW_NS_FLAG:--A} -o json 2>/dev/null || echo '{"items":[]}')

GW_COUNT=$(echo "$ALL_GW_JSON" | jq '.items | length')
info "共发现 ${GW_COUNT} 个 Gateway"

# 匹配逻辑：精确 host 匹配，或 * 通配
MATCHED_GW=$(echo "$ALL_GW_JSON" | jq --arg host "$INPUT_HOST" '
  [ .items[] |
    . as $gw |
    (.metadata.namespace) as $ns |
    (.metadata.name) as $name |
    (.spec.selector // {}) as $sel |
    [ .spec.servers[]?.hosts[]? |
      select(. == $host or . == "*" or
             (startswith("*.") and ($host | endswith(ltrimstr("*", .))))
      )
    ] |
    if length > 0 then {
      name: $name,
      namespace: $ns,
      selector: $sel,
      matched_host: .[0],
      is_wildcard: (.[0] == "*")
    } else empty end
  ] | sort_by(.is_wildcard)  # 精确匹配排前面
')

GW_MATCH_COUNT=$(echo "$MATCHED_GW" | jq 'length')

if [[ "$GW_MATCH_COUNT" -eq 0 ]]; then
  error "未找到匹配 host='$INPUT_HOST' 的 Gateway（含通配符 *）"
  exit 1
fi

echo "$MATCHED_GW" | jq -r '.[] | "  \(if .is_wildcard then "⚠ [通配符]" else "✓ [精确]" end) \(.namespace)/\(.name)  matched_host=\(.matched_host)  selector=\(.selector | to_entries | map("\(.key)=\(.value)") | join(","))"'

# 取第一个（精确优先）
SELECTED_GW=$(echo "$MATCHED_GW" | jq '.[0]')
GW_NAME=$(echo "$SELECTED_GW" | jq -r '.name')
GW_NS=$(echo "$SELECTED_GW" | jq -r '.namespace')
GW_SELECTOR=$(echo "$SELECTED_GW" | jq -r '.selector | to_entries | map("\(.key)=\(.value)") | join(",")')

echo ""
success "使用 Gateway: ${GW_NS}/${GW_NAME}  (selector: ${GW_SELECTOR})"

# 查找 IngressGateway Pod
info "查找 IngressGateway Pod (selector: ${GW_SELECTOR})..."
IGW_PODS=$(kubectl get pods -A -l "$GW_SELECTOR" \
  --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP" 2>/dev/null || true)

if [[ -n "$IGW_PODS" ]]; then
  echo -e "\n  ${BOLD}IngressGateway Pods:${RESET}"
  echo "$IGW_PODS" | while read -r line; do echo "    $line"; done
else
  warn "未找到对应的 IngressGateway Pod，selector 可能不在默认 Namespace"
fi

append_json "gateway" "$SELECTED_GW"

# =============================================================================
# STEP 2: 关联 VirtualService
# =============================================================================
section "🔀 STEP 2 — 关联 VirtualService"

info "拉取所有 VirtualService..."
ALL_VS_JSON=$(kubectl get virtualservice -A -o json 2>/dev/null || echo '{"items":[]}')

VS_COUNT=$(echo "$ALL_VS_JSON" | jq '.items | length')
info "共发现 ${VS_COUNT} 个 VirtualService"

# VS 匹配逻辑：gateways 字段包含 GW_NAME 或 GW_NS/GW_NAME
MATCHED_VS=$(echo "$ALL_VS_JSON" | jq --arg gwname "$GW_NAME" --arg gwns "$GW_NS" --arg host "$INPUT_HOST" --arg path "$INPUT_PATH" '
  [ .items[] |
    . as $vs |
    (.metadata.namespace) as $vsns |
    select(
      .spec.gateways // [] |
      any(
        . == $gwname or
        . == "\($gwns)/\($gwname)" or
        . == "mesh"
      )
    ) |
    # 同时检查 vs.spec.hosts 是否匹配
    select(
      .spec.hosts // [] |
      any(. == $host or . == "*")
    ) |
    {
      name: .metadata.name,
      namespace: $vsns,
      gateways: (.spec.gateways // []),
      hosts: (.spec.hosts // []),
      http_routes: [ (.spec.http // [])[] |
        . as $http |
        {
          match_uris: [ (.match // [])[]?.uri | to_entries[] | "\(.key)=\(.value)" ],
          route_destinations: [ (.route // [])[] | {
            host: .destination.host,
            subset: .destination.subset,
            port: .destination.port.number,
            weight: .weight
          }],
          headers: (.headers // null),
          retries: (.retries // null),
          timeout: (.timeout // null)
        }
      ]
    }
  ]
')

VS_MATCH_COUNT=$(echo "$MATCHED_VS" | jq 'length')
if [[ "$VS_MATCH_COUNT" -eq 0 ]]; then
  error "未找到关联 Gateway '${GW_NS}/${GW_NAME}' 且 host 匹配的 VirtualService"
  exit 1
fi

info "找到 ${VS_MATCH_COUNT} 个候选 VirtualService"

# Path 过滤：匹配 INPUT_PATH 前缀
PATH_MATCHED_VS=$(echo "$MATCHED_VS" | jq --arg path "$INPUT_PATH" '
  [ .[] |
    . as $vs |
    (.http_routes | map(
      select(
        .match_uris == [] or
        (.match_uris | any(
          (startswith("prefix=") and ($path | startswith(ltrimstr("prefix=", .)))) or
          (startswith("exact=") and (ltrimstr("exact=", .) == $path)) or
          (startswith("regex=") )
        ))
      )
    )) as $matched_routes |
    if ($matched_routes | length) > 0 then
      $vs + {matched_routes: $matched_routes}
    else empty end
  ]
')

PATH_MATCH_COUNT=$(echo "$PATH_MATCHED_VS" | jq 'length')
if [[ "$PATH_MATCH_COUNT" -eq 0 ]]; then
  warn "路径 '${INPUT_PATH}' 无精确匹配，回退显示所有关联 VirtualService"
  PATH_MATCHED_VS="$MATCHED_VS"
  PATH_MATCHED_VS=$(echo "$MATCHED_VS" | jq '[.[] | . + {matched_routes: .http_routes}]')
fi

echo "$PATH_MATCHED_VS" | jq -r '.[] | "  ✓ \(.namespace)/\(.name)  hosts=\(.hosts | join(","))"'

append_json "virtualservices" "$PATH_MATCHED_VS"

# =============================================================================
# STEP 3: 提取 Destinations & DestinationRule
# =============================================================================
section "🎯 STEP 3 — 提取 Destination & DestinationRule"

info "拉取所有 DestinationRule..."
ALL_DR_JSON=$(kubectl get destinationrule -A -o json 2>/dev/null || echo '{"items":[]}')

# 从匹配的 VS 中提取所有 destination host
ALL_DEST_JSON=$(echo "$PATH_MATCHED_VS" | jq '
  [ .[] |
    .namespace as $vsns |
    .matched_routes[]?.route_destinations[]? |
    {
      raw_host: .host,
      subset: .subset,
      port: .port,
      weight: .weight,
      vs_namespace: $vsns
    }
  ] | unique_by(.raw_host + (.subset // ""))
')

DEST_COUNT=$(echo "$ALL_DEST_JSON" | jq 'length')
info "发现 ${DEST_COUNT} 个 Destination"

# 为每个 destination 补全 FQDN 并关联 DR
ENRICHED_DEST=$(echo "$ALL_DEST_JSON" | jq --argjson drs "$ALL_DR_JSON" '
  [ .[] |
    . as $dest |
    ($dest.raw_host) as $rh |
    ($dest.vs_namespace) as $vsns |
    # 补全 FQDN
    (if ($rh | contains(".svc.cluster.local")) then $rh
     elif ($rh | contains(".")) then $rh
     else "\($rh).\($vsns).svc.cluster.local" end) as $fqdn |
    # 短名称（用于 Service 查找）
    ($rh | split(".")[0]) as $svcname |
    # 关联 DestinationRule
    ([ $drs.items[] |
       select(
         .spec.host == $rh or
         .spec.host == $fqdn or
         (.spec.host | split(".")[0]) == $svcname
       ) |
       {
         name: .metadata.name,
         namespace: .metadata.namespace,
         host: .spec.host,
         subsets: (.spec.subsets // []),
         trafficPolicy: (.spec.trafficPolicy // null)
       }
    ]) as $matched_drs |
    $dest + {
      fqdn: $fqdn,
      svc_name: $svcname,
      destination_rules: $matched_drs
    }
  ]
')

echo "$ENRICHED_DEST" | jq -r '.[] | 
  "  ✓ host=\(.raw_host)  subset=\(.subset // "-")  port=\(.port // "-")  weight=\(.weight // 100)",
  "    FQDN: \(.fqdn)",
  (if (.destination_rules | length) > 0 then
    "    DestinationRule: \(.destination_rules | map("\(.namespace)/\(.name)") | join(", "))"
  else
    "    DestinationRule: (无)"
  end)'

append_json "destinations" "$ENRICHED_DEST"

# =============================================================================
# STEP 4: 映射 Kubernetes Service & Pods
# ================================================================================
section "⚙️  STEP 4 — Kubernetes Service & Endpoints & Pods"

SVC_DETAIL_LIST='[]'

while IFS= read -r dest_item; do
  SVC_NAME=$(echo "$dest_item" | jq -r '.svc_name')
  SVC_NS=$(echo "$dest_item" | jq -r '.vs_namespace')
  SUBSET=$(echo "$dest_item" | jq -r '.subset // ""')

  info "查找 Service: ${SVC_NS}/${SVC_NAME}"

  SVC_JSON=$(kubectl get service "$SVC_NAME" -n "$SVC_NS" -o json 2>/dev/null || echo 'null')

  if [[ "$SVC_JSON" == "null" ]]; then
    warn "Service '${SVC_NS}/${SVC_NAME}' 不存在，尝试跨 Namespace 搜索..."
    SVC_JSON=$(kubectl get service "$SVC_NAME" -A -o json 2>/dev/null | jq '.items[0] // null')
    [[ "$SVC_JSON" == "null" ]] && { warn "Service '$SVC_NAME' 未找到，跳过"; continue; }
    SVC_NS=$(echo "$SVC_JSON" | jq -r '.metadata.namespace')
    info "在 Namespace '$SVC_NS' 找到 Service"
  fi

  SVC_LABELS=$(echo "$SVC_JSON" | jq -r '.metadata.labels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
  SVC_SELECTOR=$(echo "$SVC_JSON" | jq -r '.spec.selector // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
  SVC_CLUSTERIP=$(echo "$SVC_JSON" | jq -r '.spec.clusterIP // "-"')
  SVC_TYPE=$(echo "$SVC_JSON" | jq -r '.spec.type // "-"')
  SVC_PORTS=$(echo "$SVC_JSON" | jq -r '.spec.ports // [] | map("\(.port)/\(.protocol // "TCP") -> \(.targetPort)") | join(", ")')

  echo -e "\n  ${BOLD}Service: ${SVC_NS}/${SVC_NAME}${RESET}"
  row "  Type"       "$SVC_TYPE"
  row "  ClusterIP"  "$SVC_CLUSTERIP"
  row "  Ports"      "$SVC_PORTS"
  row "  Selector"   "${SVC_SELECTOR:-'(无 selector)'}"
  row "  Labels"     "${SVC_LABELS}"

  # Endpoints
  EP_JSON=$(kubectl get endpoints "$SVC_NAME" -n "$SVC_NS" -o json 2>/dev/null || echo 'null')
  EP_ADDRS=$(echo "$EP_JSON" | jq -r '
    [ .subsets[]?.addresses[]? | "\(.ip):\(.targetRef.name // "?")" ] | join(", ")
  ' 2>/dev/null || echo "-")
  row "  Endpoints"  "${EP_ADDRS:-'(无就绪 Endpoint)'}"

  # Pods
  POD_INFO=""
  if [[ -n "$SVC_SELECTOR" ]]; then
    POD_JSON=$(kubectl get pods -n "$SVC_NS" -l "$SVC_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
    POD_COUNT=$(echo "$POD_JSON" | jq '.items | length')
    row "  Pod 数量"   "$POD_COUNT"

    if [[ "$POD_COUNT" -gt 0 ]]; then
      echo -e "\n  ${BOLD}  Pod 列表:${RESET}"
      POD_INFO=$(echo "$POD_JSON" | jq -r '
        .items[] |
        "    \(.metadata.name)  IP=\(.status.podIP // "-")  Node=\(.spec.nodeName // "-")  Phase=\(.status.phase // "-")  Ready=\(
          [.status.containerStatuses[]?.ready] | all | if . then "✓" else "✗" end
        )  Version=\(.metadata.labels["version"] // .metadata.labels["app.kubernetes.io/version"] // "-")"
      ')
      echo "$POD_INFO"
    fi

    # Subset 版本验证
    if [[ -n "$SUBSET" && "$SUBSET" != "null" ]]; then
      echo ""
      info "验证 Subset='${SUBSET}' 的 Pod 匹配..."
      DR_SUBSET_LABELS=$(echo "$dest_item" | jq -r --arg sub "$SUBSET" '
        .destination_rules[0].subsets // [] |
        map(select(.name == $sub)) |
        .[0].labels // {} |
        to_entries | map("\(.key)=\(.value)") | join(",")
      ')
      if [[ -n "$DR_SUBSET_LABELS" ]]; then
        SUBSET_PODS=$(kubectl get pods -n "$SVC_NS" -l "${SVC_SELECTOR},${DR_SUBSET_LABELS}" --no-headers \
          -o custom-columns="NAME:.metadata.name,IP:.status.podIP,PHASE:.status.phase" 2>/dev/null | wc -l | tr -d ' ')
        row "  Subset Pods" "${SUBSET_PODS} 个 (labels: ${DR_SUBSET_LABELS})"
      else
        warn "Subset '${SUBSET}' 在 DestinationRule 中未定义 labels"
      fi
    fi
  else
    warn "Service 无 selector（可能是 ExternalName 或 Headless）"
  fi

  # 组装 SVC detail JSON
  SVC_DETAIL=$(jq -n \
    --arg name "$SVC_NAME" \
    --arg ns "$SVC_NS" \
    --arg clusterip "$SVC_CLUSTERIP" \
    --arg type "$SVC_TYPE" \
    --arg ports "$SVC_PORTS" \
    --arg selector "$SVC_SELECTOR" \
    --arg endpoints "$EP_ADDRS" \
    --arg podinfo "$POD_INFO" \
    '{name: $name, namespace: $ns, clusterIP: $clusterip, type: $type, ports: $ports, selector: $selector, endpoints: $endpoints, pods: $podinfo}')

  SVC_DETAIL_LIST=$(echo "$SVC_DETAIL_LIST" | jq --argjson s "$SVC_DETAIL" '. + [$s]')

done < <(echo "$ENRICHED_DEST" | jq -c '.[]')

append_json "services" "$SVC_DETAIL_LIST"

# =============================================================================
# STEP 5: 汇总 Mapping 表
# ================================================================================
section "📊 STEP 5 — 全链路 Mapping 汇总"

echo -e "${BOLD}"
echo "  ${cyan}%-18s${RESET} %-35s %-25s${RESET}"
printf "  %-18s %-35s %-25s\n" "层级" "资源 (Namespace/Name)" "关键信息"
echo -e "${RESET}${BLUE}  ──────────────────────────────────────────────────────────────────────────────${RESET}"

printf "  ${GREEN}%-18s${RESET} %-35s %-25s\n" \
  "[1] Gateway" \
  "${GW_NS}/${GW_NAME}" \
  "selector: ${GW_SELECTOR}"

echo "$PATH_MATCHED_VS" | jq -r '.[] | "\(.namespace)/\(.name)|\(.hosts | join(","))"' | while IFS='|' read -r vsref vshosts; do
  printf "  ${YELLOW}%-18s${RESET} %-35s %-25s\n" "[2] VirtualService" "$vsref" "hosts: $vshosts"
done

echo "$ENRICHED_DEST" | jq -r '.[] | "\(.raw_host)|\(.subset // "-")|\(.port // "-")|\(.weight // 100)|\(.destination_rules | map(.namespace + "/" + .name) | join(",") | if . == "" then "(无DR)" else . end)"' | \
while IFS='|' read -r h sub port wt dr; do
  printf "  ${MAGENTA}%-18s${RESET} %-35s %-25s\n" "[3] Destination" "host: $h  subset: $sub" "port: $port  weight: ${wt}%"
  [[ "$dr" != "(无DR)" ]] && printf "  ${MAGENTA}%-18s${RESET} %-35s\n" "  DestinationRule" "$dr"
done

echo "$SVC_DETAIL_LIST" | jq -r '.[] | "\(.namespace)/\(.name)|\(.clusterIP)|\(.ports)|\(.endpoints)"' | while IFS='|' read -r sref cip ports ep; do
  printf "  ${CYAN}%-18s${RESET} %-35s %-25s\n" "[4] Service" "$sref" "ClusterIP: $cip"
  printf "  ${CYAN}%-18s${RESET} %-35s\n" "    Ports" "$ports"
  printf "  ${CYAN}%-18s${RESET} %-35s\n" "    Endpoints" "${ep:-'(无)'}"
done

echo -e "${BLUE}  ──────────────────────────────────────────────────────────────────────────────${RESET}"
echo ""
success "链路追踪完成！"

# == =================================================================================
# JSON 输出
# =================================================================================
if [[ "$OUTPUT_JSON" == true ]]; then
  OUT_FILE="./trace-output-$(date +%Y%m%d%H%M%S).json"
  FINAL_JSON=$(jq -n \
    --arg url "$TARGET_URL" \
    --arg host "$INPUT_HOST" \
    --arg path "$INPUT_PATH" \
    --argjson result "$RESULT_JSON" \
    '{ traced_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")), input: {url: $url, host: $host, path: $path}, chain: $result }')
  echo "$FINAL_JSON" > "$OUT_FILE"
  success "JSON 结果已写入: $OUT_FILE"
fi