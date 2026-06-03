#!/usr/bin/env bash
# =============================================================================
# k8s-gateway-fqdn-minimax.sh — K8s Gateway FQDN 链路深度探索 & E2E URL 构建器
#
# 用途: 给定一个 Ingress 域名 (FQDN)，自动穿透 K8s Gateway API 核心链路:
#       HTTPRoute ──► ParentRef(Gateway/ListenerSet)
#                    ──► BackendRef(Service, 支持跨 NS) ──► DestinationRule
#                    ──► Service ──► Deployment ──► Probes (readiness/liveness/startup)
#       并生成精准的、可直接用于 E2E 测试的 curl 验证命令(自动适配 listener
#       协议、SNI --resolve、PathPrefix/Exact/Regex 路径合并)。
#
# 用法: ./k8s-gateway-fqdn-minimax.sh <FQDN> [TENANT_NAMESPACE] [--validate]
#
# 设计融合:
#   - 主架构借鉴 k8s-gateway-fqdn-gemini.sh(纯 jq 流水线、跨 NS 扫描、配色)
#   - Listener 协议/端口检测借鉴 k8s-gateway-fqdn-chatgpt.sh(自动 http/https)
#   - Probe 全枚举借鉴 chatgpt (readiness / liveness / startup, 跨 container)
#   - 路径合并逻辑借鉴 chatgpt join_prefix_probe (PathPrefix/Exact/Regex)
#   - Cross-namespace backendRef 借鉴 chatgpt
#   - 可选 --validate curl 验证借鉴 chatgpt + claude
#   - 修复昨日版 fqdn.sh 的 `kubectl apply` 误用、HTTPRoutes 拼写错
#   - 修复 claude.sh 的 hardcoded /health、`((idx++)) || true` 不可靠循环
#   - 修复 chatgpt.sh 的 TENANT_NS / --validate 参数冲突(改为标准 --flag)
#
# 依赖: kubectl, jq, curl
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
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[✔]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}# $*${RESET}"; }
divider() { echo -e "${DIM}$(printf '═%.0s' {1..88})${RESET}"; }
subdiv()  { echo -e "${DIM}$(printf '─%.0s' {1..88})${RESET}"; }

# --------------------------------------------------------------------------- #
# 默认配置(支持环境变量覆盖)
# --------------------------------------------------------------------------- #
GATEWAY_NS="${GATEWAY_NS:-abjx-gw-int}"
GATEWAY_NAME="${GATEWAY_NAME:-abjx-gw-int}"
DEFAULT_SCHEME="${DEFAULT_SCHEME:-https}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

# --------------------------------------------------------------------------- #
# 参数解析(标准 --flag 风格, 修复 chatgpt.sh 的 TENANT_NS/--validate 冲突)
# --------------------------------------------------------------------------- #
usage() {
  echo -e "$(cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") <FQDN> [TENANT_NAMESPACE] [--validate|-v] [--help|-h]

${BOLD}参数说明:${RESET}
  <FQDN>              目标 Ingress 域名 (例如: api.team1-int.uk.aibang.local)
  [TENANT_NAMESPACE]  租户命名空间(可选；省略时先尝试从 FQDN 第 2 段推断, 失败则全集群扫)
  --validate, -v      可选: 实际执行 curl 验证生成的 E2E URL

${BOLD}环境变量覆盖:${RESET}
  GATEWAY_NS          Gateway 所在 namespace(默认: ${GATEWAY_NS})
  GATEWAY_NAME        Gateway 资源名(默认: ${GATEWAY_NAME})
  DEFAULT_SCHEME      listener 协议无法判断时使用的 URL scheme(默认: ${DEFAULT_SCHEME})
  CURL_TIMEOUT        验证时的 curl 超时秒数(默认: ${CURL_TIMEOUT})

${BOLD}使用示例:${RESET}
  $(basename "$0") api.team1-int.uk.aibang.local
  $(basename "$0") app.team2.example.com team2
  $(basename "$0") api.team1-int.uk.aibang.local team1-int --validate

${BOLD}链路勘测范围:${RESET}
  HTTPRoute → ParentRef(Gateway / ListenerSet) → Listener 协议/端口
           → BackendRef(Service, 支持跨 NS) → DestinationRule
           → Service (ClusterIP, selector, port mapping)
           → Deployment (跨 container 枚举 readiness/liveness/startup probe)
           → 生成 E2E URL + 多种 curl 验证命令 (SNI / IP 直连 / DNS 依赖)

EOF
)"
  exit 1
}

INPUT_FQDN=""
TENANT_NS=""
VALIDATE="false"

# 第一遍扫描: 收集 FQDN 与 TENANT_NS(前两个非 flag 参数)
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --validate|-v) VALIDATE="true" ;;
    --help|-h)     usage ;;
    --*)           err "未知 flag: $arg"; exit 1 ;;
    *)             POSITIONAL+=("$arg") ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 ]] && INPUT_FQDN="${POSITIONAL[0]}"
[[ ${#POSITIONAL[@]} -ge 2 ]] && TENANT_NS="${POSITIONAL[1]}"
[[ ${#POSITIONAL[@]} -gt 2 ]] && { err "多余的位置参数: ${POSITIONAL[*]:2}"; usage; }

[[ -z "$INPUT_FQDN" ]] && usage

# --------------------------------------------------------------------------- #
# 依赖检查
# --------------------------------------------------------------------------- #
for cmd in kubectl jq curl; do
  if ! command -v "$cmd" &>/dev/null; then
    err "本脚本依赖 '$cmd' 命令, 请先安装。"
    exit 1
  fi
done

# --------------------------------------------------------------------------- #
# 工具函数
# --------------------------------------------------------------------------- #
# 安全地读取 JSON(失败返回空 items)
kj() { kubectl "$@" -o json 2>/dev/null || echo '{"items":[]}'; }

# 规范化路径(去除重复 /,确保以 / 开头)
norm_path() {
  local p="${1:-/}"
  [[ -z "$p" ]] && p="/"
  [[ "${p:0:1}" != "/" ]] && p="/$p"
  printf '%s' "$p" | sed -E 's#/+#/#g'
}

# 合并路由 path 与 probe path(借鉴 chatgpt join_prefix_probe, 并增强)
join_path() {
  local match_type="$1" route_path="$2" probe_path="$3"
  route_path="$(norm_path "$route_path")"
  probe_path="$(norm_path "$probe_path")"

  case "$match_type" in
    Exact)
      printf '%s' "$route_path"
      ;;
    PathPrefix|"")
      if [[ "$route_path" == "/" ]]; then
        printf '%s' "$probe_path"
      elif [[ "$probe_path" == "$route_path" || "$probe_path" == "${route_path}/"* ]]; then
        printf '%s' "$probe_path"
      else
        printf '%s/%s' "${route_path%/}" "${probe_path#/}" | sed -E 's#/+#/#g'
      fi
      ;;
    RegularExpression|ImplementationSpecific)
      # 拼接时保留 probe 路径的前导 '/', 再把多余 '/' 折叠为单个
      printf '%s%s' "$route_path" "$probe_path" | sed -E 's#/+#/#g'
      ;;
    *)
      printf '%s' "$route_path"
      ;;
  esac
}

# URL authority builder: 仅在非默认端口时附加 :port
url_authority() {
  local scheme="$1" port="$2"
  if [[ "$scheme" == "https" && "$port" == "443" ]] \
     || [[ "$scheme" == "http" && "$port" == "80" ]] \
     || [[ -z "$port" ]]; then
    printf '%s' "$INPUT_FQDN"
  else
    printf '%s:%s' "$INPUT_FQDN" "$port"
  fi
}

# 对单个 URL 执行 curl 验证并打印结果(避免在 pipe 子 shell 中使用 case)
do_validate_one() {
  local url="$1" port="$2" gw_ip="$3"
  local -a args=(-k -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT")
  if [[ -n "$gw_ip" ]]; then
    args+=(--resolve "${INPUT_FQDN}:${port}:${gw_ip}")
  fi
  local code
  code="$(curl "${args[@]}" "$url" 2>/dev/null || echo "000")"

  case "$code" in
    200|201|202|204) printf "    %sHTTP %s%s  %s\n" "$GREEN" "$code" "$RESET" "$url" ;;
    301|302|307|308) printf "    %sHTTP %s%s  %s (redirect)\n" "$YELLOW" "$code" "$RESET" "$url" ;;
    401|403)         printf "    %sHTTP %s%s  %s (auth-required, 链路通)\n" "$YELLOW" "$code" "$RESET" "$url" ;;
    404)             printf "    %sHTTP %s%s  %s (404 — 后端路由不匹配!)\n" "$RED" "$code" "$RESET" "$url" ;;
    000)             printf "    %sCONN-FAIL%s  %s (网络不可达)\n" "$RED" "$RESET" "$url" ;;
    *)               printf "    %sHTTP %s%s  %s\n" "$RED" "$code" "$RESET" "$url" ;;
  esac
}

# --------------------------------------------------------------------------- #
# 横幅
# --------------------------------------------------------------------------- #
echo ""
divider
echo -e "  ${BOLD}${MAGENTA}🛰️  K8s Gateway FQDN 链路深度勘测工具 (MiniMax 增强版)${RESET}"
echo -e "  目标域名:      ${BOLD}${GREEN}${INPUT_FQDN}${RESET}"
echo -e "  租户命名空间:  ${BOLD}${TENANT_NS:-<auto>}${RESET}"
echo -e "  Gateway:       ${BOLD}${GATEWAY_NS}/${GATEWAY_NAME}${RESET}"
echo -e "  验证模式:      ${BOLD}${VALIDATE}${RESET}"
divider

# --------------------------------------------------------------------------- #
# 智能 tenant namespace 推断(从 FQDN 第 2 段)— 借鉴昨日 fqdn.sh 的启发
# --------------------------------------------------------------------------- #
if [[ -z "$TENANT_NS" ]]; then
  CANDIDATE_NS="$(echo "$INPUT_FQDN" | awk -F. '{print $2}')"
  if [[ -n "$CANDIDATE_NS" ]]; then
    if kj get namespace "$CANDIDATE_NS" 2>/dev/null | grep -q "\"name\":\"$CANDIDATE_NS\""; then
      TENANT_NS="$CANDIDATE_NS"
      info "从 FQDN 第 2 段智能推断 tenant namespace: ${BOLD}${TENANT_NS}${RESET}"
    else
      info "FQDN 第 2 段 '$CANDIDATE_NS' 不是有效 namespace, 将进行全集群 HTTPRoute 扫描。"
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# Step 1: 智能 FQDN 路由检索(跨 NS, 支持 exact + 通配符)
# --------------------------------------------------------------------------- #
header "Step 1 / 6 — HTTPRoute 智能发现"

info "扫描绑定域名 ${INPUT_FQDN} 的 HTTPRoute${TENANT_NS:+ (限定 NS: $TENANT_NS)}..."

if [[ -n "$TENANT_NS" ]]; then
  ROUTES_JSON="$(kj get httproute -n "$TENANT_NS")"
else
  ROUTES_JSON="$(kj get httproute -A)"
fi

# 用 jq 做严格匹配(借鉴 chatgpt 的 host_match, 修复 gemini 不去尾点的问题)
MATCHED_ROUTES="$(jq -r --arg fqdn "${INPUT_FQDN%.}" '
  def norm: rtrimstr(".");
  def host_match($fqdn; $host):
    ($host | norm) as $h |
    if $h == $fqdn then true
    elif ($h | startswith("*.")) then
      ($h | ltrimstr("*.")) as $suffix |
      (($fqdn | endswith("." + $suffix)) and (($fqdn | split(".") | length) == ($h | split(".") | length)))
    else false
    end;

  .items[]?
  | select(any(.spec.hostnames[]? // []; host_match($fqdn; .)))
  | [.metadata.namespace, .metadata.name, ((.spec.hostnames // []) | join(","))]
  | @tsv
' <<<"$ROUTES_JSON")"

if [[ -z "$MATCHED_ROUTES" ]]; then
  err "未发现任何 HTTPRoute 绑定域名: ${INPUT_FQDN}"
  warn "集群中现有 HTTPRoute 列表(供参考):"
  jq -r '.items[]? | [.metadata.namespace, .metadata.name, ((.spec.hostnames // ["<empty>"]) | join(","))] | @tsv' <<<"$ROUTES_JSON" \
    | awk -F'\t' '{printf "    %-30s %-40s hostnames=%s\n", $1, $2, $3}' >&2
  exit 1
fi

ROUTE_COUNT="$(printf '%s\n' "$MATCHED_ROUTES" | wc -l | tr -d ' ')"
ok "匹配到 ${BOLD}${ROUTE_COUNT}${RESET} 个 HTTPRoute"
printf '%s\n' "$MATCHED_ROUTES" | awk -F'\t' '{printf "    • %s/%s\n      hostnames: %s\n", $1, $2, $3}'

# --------------------------------------------------------------------------- #
# 收集器
# --------------------------------------------------------------------------- #
declare -a ALL_E2E_URLS=()        # 完整 URL(供汇总)
declare -a ALL_CURL_COMMANDS=()   # 完整 curl 命令
declare -a ALL_VALIDATION=()      # 用于 --validate: URL<TAB>port<TAB>gw_ip

# --------------------------------------------------------------------------- #
# Step 2 ~ 6: 逐个 HTTPRoute 深入链路
# --------------------------------------------------------------------------- #
while IFS=$'\t' read -r ROUTE_NS ROUTE_NAME ROUTE_HOSTNAMES; do
  [[ -z "$ROUTE_NS" || -z "$ROUTE_NAME" ]] && continue

  header "HTTPRoute: ${BOLD}${ROUTE_NS}/${ROUTE_NAME}${RESET}"
  ROUTE_JSON="$(kj get httproute "$ROUTE_NAME" -n "$ROUTE_NS")"
  [[ -z "$ROUTE_JSON" ]] && { warn "无法读取 HTTPRoute, 跳过"; continue; }

  # 2.1 显示 hostnames
  subdiv
  echo -e "  ${BOLD}Hostnames:${RESET}"
  jq -r '.spec.hostnames[]? // empty' <<<"$ROUTE_JSON" | sed 's/^/    - /'

  # 2.2 显示 ParentRefs(支持 Gateway 与 ListenerSet)
  echo ""
  echo -e "  ${BOLD}ParentRefs (Gateway / ListenerSet):${RESET}"

  URL_SCHEME="$DEFAULT_SCHEME"
  URL_PORT="443"
  GATEWAY_IP=""

  PARENTS_JSON="$(jq -c '.spec.parentRefs[]? // empty' <<<"$ROUTE_JSON")"
  if [[ -z "$PARENTS_JSON" ]]; then
    warn "    HTTPRoute 无 spec.parentRefs (可能未被任何 Gateway 接管)"
  fi

  while IFS= read -r parent; do
    [[ -z "$parent" ]] && continue
    P_KIND="$(jq -r '.kind // "Gateway"' <<<"$parent")"
    P_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$parent")"
    P_NAME="$(jq -r '.name' <<<"$parent")"
    P_SECTION="$(jq -r '.sectionName // ""' <<<"$parent")"

    printf "    • %s ${CYAN}%s/%s${RESET}" "$P_KIND" "$P_NS" "$P_NAME"
    [[ -n "$P_SECTION" ]] && printf " sectionName=%s" "$P_SECTION"
    echo ""

    if [[ "$P_KIND" == "Gateway" ]]; then
      GW_JSON="$(kj get gateway "$P_NAME" -n "$P_NS")"
      if [[ -z "$GW_JSON" ]]; then
        warn "      Gateway ${P_NS}/${P_NAME} 无法读取"
        continue
      fi

      # 提取 Gateway status IP(优先 status.addresses)
      THIS_IP="$(jq -r '.status.addresses[]? | select(.type == "IP" or .type == "Hostname" or .type == null) | .value' <<<"$GW_JSON" | head -n 1)"
      [[ -z "$GATEWAY_IP" && -n "$THIS_IP" ]] && GATEWAY_IP="$THIS_IP"

      # 显示 listener 详情
      LISTENER_DETAIL="$(jq -r --arg section "$P_SECTION" '
        .spec.listeners[]?
        | select($section == "" or .name == $section)
        | "      listener=" + (.name // "?")
          + "  protocol=" + (.protocol // "?")
          + "  port=" + ((.port // "?") | tostring)
          + "  tlsMode=" + (.tls.mode // "-")
          + "  certRefs=" + ((.tls.certificateRefs // []) | length | tostring)
      ' <<<"$GW_JSON")"
      [[ -n "$LISTENER_DETAIL" ]] && echo "$LISTENER_DETAIL"

      # 协议/端口检测(取第一个匹配的 listener)
      L_PROTOCOL="$(jq -r --arg section "$P_SECTION" '
        ([.spec.listeners[]?
          | select($section == "" or .name == $section)]
         | .[0].protocol // empty)
      ' <<<"$GW_JSON")"
      L_PORT="$(jq -r --arg section "$P_SECTION" '
        ([.spec.listeners[]?
          | select($section == "" or .name == $section)]
         | .[0].port // empty)
      ' <<<"$GW_JSON")"

      case "$L_PROTOCOL" in
        HTTPS|TLS)  URL_SCHEME="https" ;;
        HTTP)       URL_SCHEME="http" ;;
        *)          ;;
      esac
      [[ -n "$L_PORT" && "$L_PORT" != "0" ]] && URL_PORT="$L_PORT"
    elif [[ "$P_KIND" == "ListenerSet" ]]; then
      LS_JSON="$(kj get listenerset "$P_NAME" -n "$P_NS")"
      if [[ -n "$LS_JSON" ]]; then
        jq -r --arg section "$P_SECTION" '
          .spec.listeners[]?
          | select($section == "" or .name == $section)
          | "      listener=" + (.name // "?")
            + "  protocol=" + (.protocol // "?")
            + "  port=" + ((.port // "?") | tostring)
            + "  (ListenerSet)"
        ' <<<"$LS_JSON"
      fi
    fi
  done <<<"$PARENTS_JSON"

  # 兜底: 如果 parentRefs 没拿到 IP, 去 LoadBalancer Service 里找
  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kj get svc -n "$GATEWAY_NS" \
      | jq -r '.items[]? | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // empty' \
      | head -n 1)"
  fi
  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kj get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" \
      | jq -r '.status.addresses[0].value // empty')"
  fi

  echo ""
  echo -e "  ${BOLD}检测结果:${RESET}"
  echo -e "    • listener scheme: ${CYAN}${URL_SCHEME}${RESET}"
  echo -e "    • listener port:   ${CYAN}${URL_PORT}${RESET}"
  echo -e "    • gateway IP:      ${CYAN}${GATEWAY_IP:-<未找到>}${RESET}"

  # 2.3 显示 HTTPRoute status.parents(绑定状态)
  echo ""
  echo -e "  ${BOLD}Route Binding Status (status.parents):${RESET}"
  PARENT_STATUS="$(jq -r '
    .status.parents[]? |
    "    • " + (.parentRef.namespace // "<same-ns>") + "/" + .parentRef.name
    + "/" + (.parentRef.sectionName // "<all>")
    + "  →  " + ([.conditions[]? | .type + "=" + .status] | join(", "))
  ' <<<"$ROUTE_JSON")"
  if [[ -n "$PARENT_STATUS" ]]; then
    echo "$PARENT_STATUS"
  else
    warn "    (无 status.parents — 路由可能尚未被 Gateway 接受)"
  fi

  # ------------------------------------------------------------------------- #
  # Step 3: 遍历 rules
  # ------------------------------------------------------------------------- #
  header "Step 3 / 6 — Rules / Matches / Backends"
  RULES_COUNT="$(jq '.spec.rules | length // 0' <<<"$ROUTE_JSON")"
  [[ "$RULES_COUNT" == "0" ]] && { warn "HTTPRoute 无 rules, 跳过"; continue; }

  for ((rule_idx=0; rule_idx<RULES_COUNT; rule_idx++)); do
    RULE_JSON="$(jq -c ".spec.rules[$rule_idx]" <<<"$ROUTE_JSON")"
    RULE_NAME="$(jq -r '.name // ""' <<<"$RULE_JSON")"

    subdiv
    echo -e "  ${BOLD}⚡ Rule[$rule_idx]${RULE_NAME:+ (name=$RULE_NAME)}${RESET}"

    # 3.1 matches — 输出 TSV: type<TAB>path<TAB>headers<TAB>queryParams<TAB>methods
    MATCH_LINES="$(jq -r '
      if ((.matches // []) | length) == 0 then
        "PathPrefix\t/\t<no-headers>\t<no-qs>\tANY"
      else
        .matches[] |
        [
          (.path.type // "PathPrefix"),
          (.path.value // "/"),
          ([(.headers // [])[] | .name + "=" + (.value // "*")]
            | if length == 0 then "<no-headers>" else join(",") end),
          ([(.queryParams // [])[] | .name + "=" + (.value // "*")]
            | if length == 0 then "<no-qs>" else join(",") end),
          ([(.method // "ANY") | tostring] | if length == 0 then "ANY" else join(",") end)
        ] | @tsv
      end
    ' <<<"$RULE_JSON")"

    echo -e "  ${BOLD}Matches:${RESET}"
    echo "$MATCH_LINES" | awk -F'\t' '{
      printf "    • type=%-15s path=%-20s headers=%-25s query=%-15s method=%s\n", $1, $2, $3, $4, $5
    }'

    # 3.2 timeouts
    REQ_T="$(jq -r '.timeouts.request // empty' <<<"$RULE_JSON")"
    BK_T="$(jq -r '.timeouts.backendRequest // .timeouts.backendTimeout // empty' <<<"$RULE_JSON")"
    if [[ -n "$REQ_T" || -n "$BK_T" ]]; then
      echo -e "  ${BOLD}Timeouts:${RESET} request=${REQ_T:-<default>} backend=${BK_T:-<default>}"
    fi

    # 3.3 遍历 backendRefs
    BACKENDS="$(jq -c '.backendRefs[]? // empty' <<<"$RULE_JSON")"
    if [[ -z "$BACKENDS" ]]; then
      warn "  Rule[$rule_idx] 无 backendRefs"
      continue
    fi

    while IFS= read -r backend; do
      [[ -z "$backend" ]] && continue

      B_KIND="$(jq -r '.kind // "Service"' <<<"$backend")"
      B_NAME="$(jq -r '.name' <<<"$backend")"
      B_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$backend")"
      B_PORT="$(jq -r '.port // ""' <<<"$backend")"
      B_WEIGHT="$(jq -r '.weight // 1' <<<"$backend")"

      echo ""
      echo -e "    ${BOLD}→ BackendRef: ${B_KIND} ${B_NS}/${B_NAME}:${B_PORT} (weight=${B_WEIGHT})${RESET}"

      if [[ "$B_KIND" != "Service" ]]; then
        warn "      backend kind='$B_KIND' (非 Service), 跳过 Service/Deployment 链路探测"
        continue
      fi

      # --------------------------------------------------------------------- #
      # Step 4: DestinationRule(支持多种 host 形式)
      # --------------------------------------------------------------------- #
      DR_JSON="$(kj get destinationrule -n "$B_NS")"
      [[ -z "$DR_JSON" || "$DR_JSON" == "null" ]] && DR_JSON='{"items":[]}'
      MATCHED_DR="$(jq -r --arg svc "$B_NAME" --arg ns "$B_NS" '
        .items[]?
        | select(
            .spec.host == $svc
            or .spec.host == ($svc + "." + $ns)
            or .spec.host == ($svc + "." + $ns + ".svc")
            or .spec.host == ($svc + "." + $ns + ".svc.cluster.local")
          )
        | [
            .metadata.name,
            .spec.host,
            (.spec.trafficPolicy.connectionPool.tcp.connectTimeout // ""),
            (.spec.trafficPolicy.connectionPool.http.idleTimeout // ""),
            ((.spec.trafficPolicy.outlierDetection.consecutive5xxErrors // "" | tostring)),
            ((.spec.trafficPolicy.outlierDetection.baseEjectionTime // "" | tostring))
          ]
        | @tsv
      ' <<<"$DR_JSON")"

      if [[ -n "$MATCHED_DR" ]]; then
        IFS=$'\t' read -r DR_NAME DR_HOST DR_CONN DR_IDLE DR_OE5X DR_OEJT <<<"$MATCHED_DR"
        echo -e "      ${BOLD}DestinationRule:${RESET} ${MAGENTA}${B_NS}/${DR_NAME}${RESET} (host=${DR_HOST})"
        echo -e "        • connectTimeout: ${DR_CONN:-<default>}"
        echo -e "        • idleTimeout:    ${DR_IDLE:-<default>}"
        echo -e "        • outlierDet:     consecutive5xx=${DR_OE5X:-<default>} baseEjectionTime=${DR_OEJT:-<default>}"
      else
        echo -e "      ${BOLD}DestinationRule:${RESET} ${DIM}<none>${RESET}"
      fi

      # --------------------------------------------------------------------- #
      # Step 5: Service
      # --------------------------------------------------------------------- #
      SVC_JSON="$(kj get svc "$B_NAME" -n "$B_NS")"
      if [[ -z "$SVC_JSON" ]]; then
        err "      Service ${B_NS}/${B_NAME} 未找到, 跳过"
        continue
      fi

      SVC_TYPE="$(jq -r '.spec.type // "ClusterIP"' <<<"$SVC_JSON")"
      SVC_CLUSTER_IP="$(jq -r '.spec.clusterIP // "<pending>"' <<<"$SVC_JSON")"
      SVC_SELECTOR="$(jq -r '.spec.selector // {} | to_entries | map(.key + "=" + .value) | join(",")' <<<"$SVC_JSON")"
      SVC_APIGW="$(jq -r '.metadata.annotations["apigateway.net/v1alpha1"] // "<none>"' <<<"$SVC_JSON")"

      SVC_PORT_INFO="$(jq -r --argjson port "${B_PORT:-0}" '
        ((.spec.ports // [])[] | select((.port // 0) == $port))
        // (.spec.ports // [])[0]
        | "port=" + ((.port // "") | tostring)
          + " → targetPort=" + ((.targetPort // "") | tostring)
          + " protocol=" + (.protocol // "TCP")
          + " appProtocol=" + (.appProtocol // "<none>")
      ' <<<"$SVC_JSON")"

      echo -e "      ${BOLD}Service:${RESET} type=${SVC_TYPE} clusterIP=${SVC_CLUSTER_IP} apigateway=${SVC_APIGW}"
      echo -e "        • selector: ${SVC_SELECTOR:-<none>}"
      echo -e "        • ${SVC_PORT_INFO}"

      # --------------------------------------------------------------------- #
      # Step 6: Deployment + Probes(跨 container, 全 probe 类型)
      # --------------------------------------------------------------------- #
      DEPLOY_NAME=""
      if [[ -n "$SVC_SELECTOR" ]]; then
        # Method A: 通过 selector 直接匹配 deploy (借鉴 gemini)
        DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -l "$SVC_SELECTOR" \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      fi
      if [[ -z "$DEPLOY_NAME" ]]; then
        # Method B: 通过 Pod ownerReferences 溯源
        if [[ -n "$SVC_SELECTOR" ]]; then
          POD_JSON="$(kj get pods -n "$B_NS" -l "$SVC_SELECTOR")"
          [[ -z "$POD_JSON" || "$POD_JSON" == "null" ]] && POD_JSON='{"items":[]}'
          RS_NAME="$(jq -r '.items[0].metadata.ownerReferences[]? | select(.kind == "ReplicaSet") | .name' <<<"$POD_JSON" | head -n 1 || true)"
          if [[ -n "$RS_NAME" ]]; then
            DEPLOY_NAME="$(kj get rs "$RS_NAME" -n "$B_NS" \
              | jq -r '.metadata.ownerReferences[]? | select(.kind == "Deployment") | .name' | head -n 1 || true)"
          fi
        fi
      fi
      if [[ -z "$DEPLOY_NAME" ]]; then
        # Method C: 通过 Deployment spec.selector 匹配 SVC selector (借鉴 gemini)
        DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -o json 2>/dev/null \
          | jq -r --arg sel "$SVC_SELECTOR" '
              .items[]?
              | select((.spec.selector.matchLabels // {}) | to_entries | map(.key + "=" + .value) | join(",") == $sel)
              | .metadata.name
            ' | head -n 1 || true)"
      fi

      # 不再用 "$B_NAME" 兜底 (这是 claude.sh 的坑, 容易张冠李戴)
      if [[ -n "$DEPLOY_NAME" ]]; then
        DEPLOY_JSON="$(kj get deploy "$DEPLOY_NAME" -n "$B_NS")"
        READY="$(jq -r '.status.readyReplicas // 0' <<<"$DEPLOY_JSON")"
        DESIRED="$(jq -r '.spec.replicas // 0' <<<"$DEPLOY_JSON")"
        echo -e "      ${BOLD}Deployment:${RESET} ${GREEN}${B_NS}/${DEPLOY_NAME}${RESET} ready=${READY}/${DESIRED}"

        # 跨 container 枚举所有 HTTP probe(借鉴 chatgpt)
        PROBES_JSON="$(jq -r '
          .spec.template.spec.containers[]? |
          .name as $c |
          [
            ["readiness", .readinessProbe.httpGet.path // "", (.readinessProbe.httpGet.port // "" | tostring), (.readinessProbe.httpGet.scheme // "HTTP")],
            ["liveness",  .livenessProbe.httpGet.path  // "", (.livenessProbe.httpGet.port  // "" | tostring), (.livenessProbe.httpGet.scheme  // "HTTP")],
            ["startup",   .startupProbe.httpGet.path   // "", (.startupProbe.httpGet.port   // "" | tostring), (.startupProbe.httpGet.scheme   // "HTTP")]
          ][] |
          select(.[1] != null and .[1] != "") |
          [$c, .[0], .[1], .[2], .[3]] | @tsv
        ' <<<"$DEPLOY_JSON")"

        if [[ -n "$PROBES_JSON" ]]; then
          echo -e "        ${BOLD}HTTP Probes:${RESET}"
          echo "$PROBES_JSON" | awk -F'\t' '{
            printf "          • container=%-20s %-10s path=%-20s port=%-5s scheme=%s\n", $1, $2, $3, $4, $5
          }'
        else
          warn "        (无 readiness/liveness/startup HTTP probe)"
        fi
      else
        warn "      Deployment 未定位到 (selector 匹配失败且无 Pod 可溯源)"
        DEPLOY_JSON=""
        PROBES_JSON=""
      fi

      # --------------------------------------------------------------------- #
      # Step 7: 生成 E2E URL + curl 命令
      # --------------------------------------------------------------------- #
      echo ""
      echo -e "    ${BOLD}🔗 E2E URLs (rule[$rule_idx] / ${B_NAME}:${B_PORT})${RESET}"

      # 构造 probe path 列表(若 Deployment 不存在, 用 /health 兜底但不静默)
      declare -A SEEN_PROBE=()
      declare -a PROBE_PATHS=()
      if [[ -n "${PROBES_JSON:-}" ]]; then
        while IFS=$'\t' read -r _pc _pt pp _rest; do
          [[ -z "$pp" ]] && continue
          if [[ -z "${SEEN_PROBE[$pp]:-}" ]]; then
            SEEN_PROBE[$pp]=1
            PROBE_PATHS+=("$pp")
          fi
        done <<<"$PROBES_JSON"
      fi
      [[ ${#PROBE_PATHS[@]} -eq 0 ]] && PROBE_PATHS=("/health")

      AUTHORITY="$(url_authority "$URL_SCHEME" "$URL_PORT")"
      ROUTE_GENERATED=0
      while IFS=$'\t' read -r MATCH_TYPE MATCH_PATH _HEADERS _QP _METHOD; do
        [[ -z "$MATCH_TYPE" ]] && continue
        for PROBE_PATH in "${PROBE_PATHS[@]}"; do
          [[ -z "$PROBE_PATH" ]] && continue
          FINAL_PATH="$(join_path "$MATCH_TYPE" "$MATCH_PATH" "$PROBE_PATH")"
          FULL_URL="${URL_SCHEME}://${AUTHORITY}${FINAL_PATH}"
          ALL_E2E_URLS+=("$FULL_URL")

          # 方法 A: 本地 DNS/Hosts 已就绪
          echo -e "      ${DIM}方法 A (本地 DNS/Hosts 就绪):${RESET}"
          echo -e "        ${CYAN}curl -k -v --max-time ${CURL_TIMEOUT} \"${FULL_URL}\"${RESET}"

          # 方法 B: SNI --resolve 绕过 DNS
          if [[ -n "$GATEWAY_IP" ]]; then
            echo -e "      ${DIM}方法 B (SNI --resolve 绕过 DNS, 强制走 Gateway):${RESET}"
            RESOLVE_HOST="${INPUT_FQDN}:${URL_PORT}:${GATEWAY_IP}"
            CURL_CMD="curl -k -v --max-time ${CURL_TIMEOUT} --resolve \"${RESOLVE_HOST}\" \"${FULL_URL}\""
            echo -e "        ${BOLD}${YELLOW}${CURL_CMD}${RESET}"
            ALL_CURL_COMMANDS+=("$CURL_CMD")
            ALL_VALIDATION+=("${FULL_URL}"$'\t'"${URL_PORT}"$'\t'"${GATEWAY_IP}")
          else
            ALL_CURL_COMMANDS+=("curl -k -v --max-time ${CURL_TIMEOUT} \"${FULL_URL}\"")
            ALL_VALIDATION+=("${FULL_URL}"$'\t'"${URL_PORT}"$'\t'"")
          fi

          # 方法 C: IP 直连 + Host 头(内网调试用)
          if [[ -n "$GATEWAY_IP" ]]; then
            echo -e "      ${DIM}方法 C (IP 直连 + Host 头, 内网/跨网段调试):${RESET}"
            echo -e "        ${CYAN}curl -k -v --max-time ${CURL_TIMEOUT} -H \"Host: ${INPUT_FQDN}\" \"${URL_SCHEME}://${GATEWAY_IP}${FINAL_PATH}\"${RESET}"
          fi
          echo ""
          ROUTE_GENERATED=$((ROUTE_GENERATED + 1))
        done
      done <<<"$MATCH_LINES"

      if [[ $ROUTE_GENERATED -eq 0 ]]; then
        warn "      (未生成任何 URL — 可能是 match 解析失败)"
      else
        ok "      本 backend 生成 ${BOLD}${ROUTE_GENERATED}${RESET} 个 E2E URL"
      fi

    done <<<"$BACKENDS"
  done  # end for rule_idx

done <<<"$MATCHED_ROUTES"

# --------------------------------------------------------------------------- #
# Step 8: 汇总 + 唯一化
# --------------------------------------------------------------------------- #
header "Step 8 / 6 — E2E 汇总 (去重 & 排序)"

if [[ ${#ALL_E2E_URLS[@]} -eq 0 ]]; then
  err "未生成任何 E2E URL, 请检查上述链路配置"
  exit 1
fi

UNIQUE_URLS=($(printf '%s\n' "${ALL_E2E_URLS[@]}" | awk 'NF && !seen[$0]++'))
UNIQUE_CURLS=($(printf '%s\n' "${ALL_CURL_COMMANDS[@]}" | awk 'NF && !seen[$0]++'))

echo -e "  ${BOLD}全部唯一 URL 列表 (${#UNIQUE_URLS[@]}):${RESET}"
printf '    %s\n' "${UNIQUE_URLS[@]}"

echo ""
echo -e "  ${BOLD}全部 curl 命令 (${#UNIQUE_CURLS[@]}):${RESET}"
printf '    %s\n' "${UNIQUE_CURLS[@]}"

# --------------------------------------------------------------------------- #
# Step 9 (可选): 实际执行 curl 验证
# --------------------------------------------------------------------------- #
if [[ "$VALIDATE" == "true" ]]; then
  header "Step 9 / 6 — 实际 curl 验证"
  warn "即将对生成的 URL 执行实际 HTTP 请求 (--max-time=${CURL_TIMEOUT}s)..."

  # 去重 ALL_VALIDATION
  UNIQUE_VAL=($(printf '%s\n' "${ALL_VALIDATION[@]}" | awk 'NF && !seen[$0]++'))

  PASS=0; WARN_C=0; FAIL_C=0
  for line in "${UNIQUE_VAL[@]}"; do
    IFS=$'\t' read -r url port gw_ip <<<"$line"
    [[ -z "$url" ]] && continue

    # 重新跑一次拿 code 以便计数(简单起见, 直接靠函数内的颜色区分)
    # 这里用临时数组收集行, 然后统计
    OUT="$(do_validate_one "$url" "$port" "$gw_ip")"
    echo "$OUT"

    # 通过 ANSI 颜色粗略统计(简化)
    if   [[ "$OUT" == *"${GREEN}HTTP 2"* ]]; then ((PASS+=1));
    elif [[ "$OUT" == *"${YELLOW}HTTP"* || "$OUT" == *"${YELLOW}CONN"* ]]; then ((WARN_C+=1));
    else ((FAIL_C+=1)); fi
  done

  echo ""
  echo -e "  ${BOLD}验证汇总:${RESET} ${GREEN}PASS=${PASS}${RESET}  ${YELLOW}WARN=${WARN_C}${RESET}  ${RED}FAIL=${FAIL_C}${RESET}"
fi

# --------------------------------------------------------------------------- #
# 结束
# --------------------------------------------------------------------------- #
divider
success "链路勘测完成！共 ${BOLD}${#UNIQUE_URLS[@]}${RESET} 个唯一 E2E URL, ${BOLD}${#UNIQUE_CURLS[@]}${RESET} 个 curl 命令"
echo -e "  ${DIM}提示: 复制 curl 命令即可在终端执行 SNI 绕过 DNS 的 E2E 验证。${RESET}"
divider
echo ""
