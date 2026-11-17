#!/usr/bin/env bash
# refer-lb-create.sh — 从现有 MIG 关联的 LB 链路中提取配置，生成 POC 创建命令
#
# 工作流：
#   1. 输入 MIG 名称 → 反查 backend service → URL map → target proxy → forwarding rule
#   2. 让用户交互选择一条链路作为参考
#   3. 提取所有关键参数
#   4. 按正确顺序输出一套带 POC 前缀的 gcloud create 命令
#
# 依赖：gcloud, jq
#
# 用法：
#   bash refer-lb-create.sh <mig-pattern> [options]
#
# Options:
#   --project <project-id>    GCP project id
#   --region <region>         过滤 region
#   --prefix <name>           POC 资源名前缀（默认: poc）
#   --output <file>           将生成的命令写入文件（默认: 输出到终端）
#   --dry-run                 仅发现和展示，不生成创建命令
#   --lb-scheme <scheme>      过滤 load balancing scheme
#   -h, --help                帮助
#
# 示例：
#   bash refer-lb-create.sh my-mig --project my-proj --prefix lex-poc
#   bash refer-lb-create.sh api --project my-proj --region us-central1 --output poc-cmds.sh

set -euo pipefail

# ─── 颜色 ───────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

log()  { printf '%b%s%b\n' "$C_BLUE"   "$*" "$C_RESET"; }
ok()   { printf '%b%s%b\n' "$C_GREEN"  "$*" "$C_RESET"; }
warn() { printf '%b%s%b\n' "$C_YELLOW" "$*" "$C_RESET"; }
err()  { printf '%b%s%b\n' "$C_RED"    "$*" "$C_RESET" >&2; }
die()  { err "$*"; exit 1; }

# ─── 工具函数 ────────────────────────────────────────────────
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "ERROR: missing required command: $1"
}

name_from_ref() {
  local ref="${1:-}"
  ref="${ref%/}"
  echo "${ref##*/}"
}

region_from_ref() {
  local ref="${1:-}"
  if [[ "$ref" == *"/regions/"* ]]; then
    echo "$ref" | sed -E 's|.*/regions/([^/]+).*|\1|'
  fi
}

matches_regex() {
  local value="${1:-}" pattern="${2:-}"
  [[ -z "$pattern" ]] && return 0
  [[ "$value" =~ $pattern ]]
}

usage() {
  sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
}

# ─── 参数解析 ────────────────────────────────────────────────
PROJECT=""
REGION=""
MIG_PATTERN=""
POC_PREFIX="poc"
OUTPUT_FILE=""
DRY_RUN="false"
LB_SCHEME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)         PROJECT="$2"; shift 2 ;;
    --region)          REGION="$2"; shift 2 ;;
    --prefix)          POC_PREFIX="$2"; shift 2 ;;
    --output)          OUTPUT_FILE="$2"; shift 2 ;;
    --dry-run)         DRY_RUN="true"; shift ;;
    --lb-scheme)       LB_SCHEME="$2"; shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    -*)                die "Unknown option: $1" ;;
    *)
      if [[ -z "$MIG_PATTERN" ]]; then
        MIG_PATTERN="$1"
      else
        die "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -z "$MIG_PATTERN" ]] && { usage >&2; exit 1; }

require_cmd gcloud
require_cmd jq

GCLOUD_BASE=(gcloud)
[[ -n "$PROJECT" ]] && GCLOUD_BASE+=(--project "$PROJECT")

run_gcloud_json() {
  "${GCLOUD_BASE[@]}" "$@" --format=json 2>/dev/null
}

# ─── 阶段 1：批量拉取所有资源 ────────────────────────────────
log "━━━ Step 1: 拉取项目资源 ━━━"
log "  project: ${PROJECT:-"(gcloud default)"}"
log "  mig pattern: ${MIG_PATTERN}"
[[ -n "$REGION" ]] && log "  region: ${REGION}"
echo

log "  拉取 MIGs..."
MIGS_JSON="$(run_gcloud_json compute instance-groups managed list)"

log "  拉取 Backend Services..."
BACKENDS_JSON="$(run_gcloud_json compute backend-services list)"

log "  拉取 Health Checks..."
HEALTH_CHECKS_JSON="$(run_gcloud_json compute health-checks list)"

log "  拉取 URL Maps..."
URL_MAPS_LIST_JSON="$(run_gcloud_json compute url-maps list)"

log "  拉取 Target Proxies..."
TARGET_HTTP_PROXIES_JSON="$(run_gcloud_json compute target-http-proxies list)"
TARGET_HTTPS_PROXIES_JSON="$(run_gcloud_json compute target-https-proxies list)"

log "  拉取 Forwarding Rules..."
FORWARDING_RULES_JSON="$(run_gcloud_json compute forwarding-rules list)"

ok "  资源拉取完毕。"
echo

# ─── 准备临时目录和 URL Map 详情 ─────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 获取 URL Map 完整详情（list 没有 pathMatchers 等）
>"$TMP_DIR/url_maps_full.jsonl"
echo "$URL_MAPS_LIST_JSON" | jq -c '.[]' | while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  name="$(jq -r '.name' <<<"$item")"
  region_ref="$(jq -r '.region // empty' <<<"$item")"
  if [[ -n "$region_ref" ]]; then
    rn="$(name_from_ref "$region_ref")"
    run_gcloud_json compute url-maps describe "$name" --region "$rn" | jq -c '.' >> "$TMP_DIR/url_maps_full.jsonl"
  else
    run_gcloud_json compute url-maps describe "$name" | jq -c '.' >> "$TMP_DIR/url_maps_full.jsonl"
  fi
done

# 合并所有 proxy
>"$TMP_DIR/proxies.jsonl"
echo "$TARGET_HTTP_PROXIES_JSON"  | jq -c '.[] | .proxyKind="http"'  >> "$TMP_DIR/proxies.jsonl"
echo "$TARGET_HTTPS_PROXIES_JSON" | jq -c '.[] | .proxyKind="https"' >> "$TMP_DIR/proxies.jsonl"

# ─── 阶段 2：发现 MIG → LB 链路 ─────────────────────────────
log "━━━ Step 2: 发现 LB 链路 ━━━"
echo

# 存储发现结果
CHAIN_IDX=0
>"$TMP_DIR/chains.jsonl"

echo "$MIGS_JSON" | jq -c '.[]' | while IFS= read -r mig; do
  mig_name="$(jq -r '.name' <<<"$mig")"
  zone_ref="$(jq -r '.zone // empty' <<<"$mig")"
  region_ref="$(jq -r '.region // empty' <<<"$mig")"
  zone_name="$(name_from_ref "$zone_ref")"
  region_name="$(name_from_ref "$region_ref")"
  zone_region="${zone_name%-*}"

  matches_regex "$mig_name" "$MIG_PATTERN" || continue
  if [[ -n "$REGION" && "$REGION" != "$region_name" && "$REGION" != "$zone_region" ]]; then
    continue
  fi

  instance_group="$(jq -r '.instanceGroup // empty' <<<"$mig")"
  named_ports="$(jq -r '.namedPorts // [] | map("\(.name):\(.port)") | join(", ")' <<<"$mig")"

  # 找引用了这个 MIG 的 backend services
  echo "$BACKENDS_JSON" | jq -c '.[]' | while IFS= read -r backend; do
    backend_name="$(jq -r '.name' <<<"$backend")"
    backend_scheme="$(jq -r '.loadBalancingScheme // "UNKNOWN"' <<<"$backend")"
    backend_region_ref="$(jq -r '.region // empty' <<<"$backend")"
    backend_region_name="$(name_from_ref "$backend_region_ref")"
    backend_protocol="$(jq -r '.protocol // "HTTP"' <<<"$backend")"
    backend_port_name="$(jq -r '.portName // empty' <<<"$backend")"
    backend_timeout="$(jq -r '.timeoutSec // 30' <<<"$backend")"
    backend_self_link="$(jq -r '.selfLink // empty' <<<"$backend")"
    health_checks_raw="$(jq -r '.healthChecks // [] | join(",")' <<<"$backend")"
    session_affinity="$(jq -r '.sessionAffinity // "NONE"' <<<"$backend")"
    balancing_mode="$(jq -r '.backends[0].balancingMode // "UTILIZATION"' <<<"$backend")"

    [[ -n "$LB_SCHEME" && "$backend_scheme" != "$LB_SCHEME" ]] && continue

    found_group="$(jq -r --arg ig "$instance_group" '.backends // [] | map(select(.group == $ig)) | length' <<<"$backend")"
    [[ "$found_group" -gt 0 ]] || continue

    # 找 health check 详情
    hc_name=""
    hc_protocol=""
    hc_port=""
    hc_request_path=""
    hc_check_interval=""
    hc_timeout=""
    if [[ -n "$health_checks_raw" ]]; then
      hc_name="$(name_from_ref "${health_checks_raw%%,*}")"
      # 从已拉取的 health check 列表中查找
      hc_json="$(echo "$HEALTH_CHECKS_JSON" | jq -c --arg name "$hc_name" '.[] | select(.name == $name)' | head -1)"
      if [[ -n "$hc_json" ]]; then
        hc_protocol="$(jq -r 'if .httpHealthCheck then "HTTP" elif .httpsHealthCheck then "HTTPS" elif .tcpHealthCheck then "TCP" elif .http2HealthCheck then "HTTP2" else "HTTP" end' <<<"$hc_json")"
        case "$hc_protocol" in
          HTTP)  hc_port="$(jq -r '.httpHealthCheck.port // 80' <<<"$hc_json")";  hc_request_path="$(jq -r '.httpHealthCheck.requestPath // "/"' <<<"$hc_json")" ;;
          HTTPS) hc_port="$(jq -r '.httpsHealthCheck.port // 443' <<<"$hc_json")"; hc_request_path="$(jq -r '.httpsHealthCheck.requestPath // "/"' <<<"$hc_json")" ;;
          HTTP2) hc_port="$(jq -r '.http2HealthCheck.port // 443' <<<"$hc_json")"; hc_request_path="$(jq -r '.http2HealthCheck.requestPath // "/"' <<<"$hc_json")" ;;
          TCP)   hc_port="$(jq -r '.tcpHealthCheck.port // 80' <<<"$hc_json")";    hc_request_path="" ;;
        esac
        hc_check_interval="$(jq -r '.checkIntervalSec // 10' <<<"$hc_json")"
        hc_timeout="$(jq -r '.timeoutSec // 5' <<<"$hc_json")"
      fi
    fi

    # 找 URL Map
    while IFS= read -r url_map; do
      [[ -z "$url_map" ]] && continue
      url_map_name="$(jq -r '.name' <<<"$url_map")"
      url_map_self_link="$(jq -r '.selfLink // empty' <<<"$url_map")"
      url_map_region_ref="$(jq -r '.region // empty' <<<"$url_map")"
      url_map_region="$(name_from_ref "$url_map_region_ref")"

      # 检查这个 url map 是否引用了当前 backend service
      url_map_has_backend="$(
        jq -r \
          --arg bs_name "$backend_name" \
          '
          [
            .defaultService,
            (.pathMatchers[]?.defaultService),
            (.pathMatchers[]?.pathRules[]?.service),
            (.pathMatchers[]?.routeRules[]?.service)
          ]
          | flatten
          | map(select(. != null))
          | map(tostring)
          | map(split("/")[-1])
          | any(. == $bs_name)
          ' <<<"$url_map"
      )"
      [[ "$url_map_has_backend" == "true" ]] || continue

      # 找 target proxy
      while IFS= read -r proxy; do
        [[ -z "$proxy" ]] && continue
        proxy_url_map="$(jq -r '.urlMap // empty' <<<"$proxy")"
        [[ -n "$proxy_url_map" ]] || continue
        if [[ "$proxy_url_map" != "$url_map_self_link" && "$(name_from_ref "$proxy_url_map")" != "$url_map_name" ]]; then
          continue
        fi

        proxy_name="$(jq -r '.name' <<<"$proxy")"
        proxy_kind="$(jq -r '.proxyKind' <<<"$proxy")"
        proxy_self_link="$(jq -r '.selfLink // empty' <<<"$proxy")"
        proxy_region_ref="$(jq -r '.region // empty' <<<"$proxy")"
        proxy_region="$(name_from_ref "$proxy_region_ref")"
        ssl_certs="$(jq -r '.sslCertificates // [] | map(split("/")[-1]) | join(",")' <<<"$proxy")"

        # 找 forwarding rule
        echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
          rule_name="$(jq -r '.name' <<<"$rule")"
          rule_target="$(jq -r '.target // empty' <<<"$rule")"
          [[ -n "$rule_target" ]] || continue
          if [[ "$rule_target" != "$proxy_self_link" && "$(name_from_ref "$rule_target")" != "$proxy_name" ]]; then
            continue
          fi

          rule_scheme="$(jq -r '.loadBalancingScheme // "-"' <<<"$rule")"
          rule_ip="$(jq -r '.IPAddress // "-"' <<<"$rule")"
          rule_ports="$(jq -r 'if (.ports // empty) != empty then (.ports | join(",")) else (.portRange // "-") end' <<<"$rule")"
          rule_network="$(jq -r '.network // empty' <<<"$rule")"
          rule_network_name="$(name_from_ref "$rule_network")"
          rule_subnetwork="$(jq -r '.subnetwork // empty' <<<"$rule")"
          rule_subnetwork_name="$(name_from_ref "$rule_subnetwork")"
          rule_region_ref="$(jq -r '.region // empty' <<<"$rule")"
          rule_region="$(name_from_ref "$rule_region_ref")"
          rule_ip_version="$(jq -r '.ipVersion // empty' <<<"$rule")"

          # 完整链路已找到，输出为一条 JSON 记录
          CHAIN_IDX=$((CHAIN_IDX + 1))
          jq -n \
            --arg idx "$CHAIN_IDX" \
            --arg mig_name "$mig_name" \
            --arg zone "$zone_name" \
            --arg mig_region "${region_name:-$zone_region}" \
            --arg named_ports "$named_ports" \
            --arg instance_group "$(name_from_ref "$instance_group")" \
            --arg bs_name "$backend_name" \
            --arg bs_scheme "$backend_scheme" \
            --arg bs_protocol "$backend_protocol" \
            --arg bs_port_name "$backend_port_name" \
            --arg bs_timeout "$backend_timeout" \
            --arg bs_session_affinity "$session_affinity" \
            --arg bs_balancing_mode "$balancing_mode" \
            --arg bs_region "$backend_region_name" \
            --arg hc_name "$hc_name" \
            --arg hc_protocol "$hc_protocol" \
            --arg hc_port "$hc_port" \
            --arg hc_request_path "$hc_request_path" \
            --arg hc_check_interval "$hc_check_interval" \
            --arg hc_timeout "$hc_timeout" \
            --arg um_name "$url_map_name" \
            --arg um_region "$url_map_region" \
            --arg proxy_name "$proxy_name" \
            --arg proxy_kind "$proxy_kind" \
            --arg proxy_region "$proxy_region" \
            --arg ssl_certs "$ssl_certs" \
            --arg fr_name "$rule_name" \
            --arg fr_scheme "$rule_scheme" \
            --arg fr_ip "$rule_ip" \
            --arg fr_ports "$rule_ports" \
            --arg fr_region "$rule_region" \
            --arg fr_network "$rule_network_name" \
            --arg fr_subnetwork "$rule_subnetwork_name" \
            --arg fr_ip_version "$rule_ip_version" \
            '{
              idx: ($idx | tonumber),
              mig: $mig_name, zone: $zone, mig_region: $mig_region,
              named_ports: $named_ports, instance_group: $instance_group,
              bs: { name: $bs_name, scheme: $bs_scheme, protocol: $bs_protocol,
                    port_name: $bs_port_name, timeout: $bs_timeout,
                    session_affinity: $bs_session_affinity, balancing_mode: $bs_balancing_mode,
                    region: $bs_region },
              hc: { name: $hc_name, protocol: $hc_protocol, port: $hc_port,
                    request_path: $hc_request_path, check_interval: $hc_check_interval,
                    timeout: $hc_timeout },
              um: { name: $um_name, region: $um_region },
              proxy: { name: $proxy_name, kind: $proxy_kind, region: $proxy_region,
                       ssl_certs: $ssl_certs },
              fr: { name: $fr_name, scheme: $fr_scheme, ip: $fr_ip, ports: $fr_ports,
                    region: $fr_region, network: $fr_network, subnetwork: $fr_subnetwork,
                    ip_version: $fr_ip_version }
            }' >> "$TMP_DIR/chains.jsonl"
        done
      done < "$TMP_DIR/proxies.jsonl"
    done < "$TMP_DIR/url_maps_full.jsonl"
  done
done

# ─── 阶段 3：展示发现结果并让用户选择 ────────────────────────
TOTAL_CHAINS="$(wc -l < "$TMP_DIR/chains.jsonl" | tr -d ' ')"

if [[ "$TOTAL_CHAINS" -eq 0 ]]; then
  warn "未发现任何从 MIG '$MIG_PATTERN' 出发的完整 LB 链路。"
  warn "可能原因："
  warn "  - MIG 没有被任何 backend service 引用"
  warn "  - backend service 没有被 URL map 引用"
  warn "  - 链路中某个环节缺失（比如没有 forwarding rule）"
  exit 0
fi

echo
ok "发现 ${TOTAL_CHAINS} 条完整 LB 链路："
echo

idx=0
while IFS= read -r chain; do
  [[ -z "$chain" ]] && continue
  idx=$((idx + 1))
  mig="$(jq -r '.mig' <<<"$chain")"
  bs="$(jq -r '.bs.name' <<<"$chain")"
  bs_scheme="$(jq -r '.bs.scheme' <<<"$chain")"
  um="$(jq -r '.um.name' <<<"$chain")"
  proxy="$(jq -r '.proxy.name' <<<"$chain")"
  proxy_kind="$(jq -r '.proxy.kind' <<<"$chain")"
  fr="$(jq -r '.fr.name' <<<"$chain")"
  fr_ip="$(jq -r '.fr.ip' <<<"$chain")"
  fr_ports="$(jq -r '.fr.ports' <<<"$chain")"

  printf "  ${C_CYAN}[%d]${C_RESET} MIG: ${C_BOLD}%s${C_RESET}\n" "$idx" "$mig"
  printf "      BS: %s  (scheme: %s)\n" "$bs" "$bs_scheme"
  printf "      UM: %s → Proxy: %s (%s) → FR: %s (%s:%s)\n" "$um" "$proxy" "$proxy_kind" "$fr" "$fr_ip" "$fr_ports"
  echo
done < "$TMP_DIR/chains.jsonl"

if [[ "$DRY_RUN" == "true" ]]; then
  ok "dry-run 模式，仅展示发现结果。"
  exit 0
fi

# ─── 用户选择 ────────────────────────────────────────────────
SELECTED=1
if [[ "$TOTAL_CHAINS" -gt 1 ]]; then
  printf "${C_YELLOW}请选择一条链路作为参考 [1-%d] (默认 1): ${C_RESET}" "$TOTAL_CHAINS"
  read -r user_choice
  if [[ -n "$user_choice" && "$user_choice" =~ ^[0-9]+$ ]]; then
    SELECTED="$user_choice"
  fi
fi

if [[ "$SELECTED" -lt 1 || "$SELECTED" -gt "$TOTAL_CHAINS" ]]; then
  die "无效选择: $SELECTED"
fi

CHAIN="$(sed -n "${SELECTED}p" "$TMP_DIR/chains.jsonl")"
ok "已选择链路 #${SELECTED}"
echo

# ─── 阶段 4：从选中链路提取参数 ──────────────────────────────
log "━━━ Step 3: 提取参考配置 ━━━"
echo

REF_MIG="$(jq -r '.mig' <<<"$CHAIN")"
REF_IG="$(jq -r '.instance_group' <<<"$CHAIN")"
REF_MIG_REGION="$(jq -r '.mig_region' <<<"$CHAIN")"
REF_ZONE="$(jq -r '.zone' <<<"$CHAIN")"
REF_NAMED_PORTS="$(jq -r '.named_ports' <<<"$CHAIN")"

REF_HC_NAME="$(jq -r '.hc.name' <<<"$CHAIN")"
REF_HC_PROTOCOL="$(jq -r '.hc.protocol' <<<"$CHAIN")"
REF_HC_PORT="$(jq -r '.hc.port' <<<"$CHAIN")"
REF_HC_PATH="$(jq -r '.hc.request_path' <<<"$CHAIN")"
REF_HC_INTERVAL="$(jq -r '.hc.check_interval' <<<"$CHAIN")"
REF_HC_TIMEOUT="$(jq -r '.hc.timeout' <<<"$CHAIN")"

REF_BS_NAME="$(jq -r '.bs.name' <<<"$CHAIN")"
REF_BS_SCHEME="$(jq -r '.bs.scheme' <<<"$CHAIN")"
REF_BS_PROTOCOL="$(jq -r '.bs.protocol' <<<"$CHAIN")"
REF_BS_PORT_NAME="$(jq -r '.bs.port_name' <<<"$CHAIN")"
REF_BS_TIMEOUT="$(jq -r '.bs.timeout' <<<"$CHAIN")"
REF_BS_SESSION_AFFINITY="$(jq -r '.bs.session_affinity' <<<"$CHAIN")"
REF_BS_BALANCING_MODE="$(jq -r '.bs.balancing_mode' <<<"$CHAIN")"
REF_BS_REGION="$(jq -r '.bs.region' <<<"$CHAIN")"

REF_UM_NAME="$(jq -r '.um.name' <<<"$CHAIN")"
REF_UM_REGION="$(jq -r '.um.region' <<<"$CHAIN")"

REF_PROXY_NAME="$(jq -r '.proxy.name' <<<"$CHAIN")"
REF_PROXY_KIND="$(jq -r '.proxy.kind' <<<"$CHAIN")"
REF_PROXY_REGION="$(jq -r '.proxy.region' <<<"$CHAIN")"
REF_SSL_CERTS="$(jq -r '.proxy.ssl_certs' <<<"$CHAIN")"

REF_FR_NAME="$(jq -r '.fr.name' <<<"$CHAIN")"
REF_FR_SCHEME="$(jq -r '.fr.scheme' <<<"$CHAIN")"
REF_FR_IP="$(jq -r '.fr.ip' <<<"$CHAIN")"
REF_FR_PORTS="$(jq -r '.fr.ports' <<<"$CHAIN")"
REF_FR_REGION="$(jq -r '.fr.region' <<<"$CHAIN")"
REF_FR_NETWORK="$(jq -r '.fr.network' <<<"$CHAIN")"
REF_FR_SUBNETWORK="$(jq -r '.fr.subnetwork' <<<"$CHAIN")"

# 确定是 global 还是 regional
IS_REGIONAL="false"
if [[ -n "$REF_BS_REGION" || -n "$REF_UM_REGION" || -n "$REF_FR_REGION" ]]; then
  IS_REGIONAL="true"
fi
# 确定用哪个 region
EFFECTIVE_REGION="${REF_FR_REGION:-${REF_BS_REGION:-${REF_UM_REGION:-$REF_MIG_REGION}}}"

# POC 资源命名
POC_HC="${POC_PREFIX}-hc"
POC_BS="${POC_PREFIX}-bs"
POC_UM="${POC_PREFIX}-um"
POC_PROXY="${POC_PREFIX}-proxy"
POC_FR="${POC_PREFIX}-fr"

log "参考链路摘要："
echo "  REF MIG:              $REF_MIG"
echo "  REF Instance Group:   $REF_IG"
echo "  REF Health Check:     $REF_HC_NAME ($REF_HC_PROTOCOL:$REF_HC_PORT $REF_HC_PATH)"
echo "  REF Backend Service:  $REF_BS_NAME (scheme=$REF_BS_SCHEME, proto=$REF_BS_PROTOCOL)"
echo "  REF URL Map:          $REF_UM_NAME"
echo "  REF Target Proxy:     $REF_PROXY_NAME ($REF_PROXY_KIND)"
echo "  REF Forwarding Rule:  $REF_FR_NAME (ip=$REF_FR_IP ports=$REF_FR_PORTS)"
echo "  Scope:                $(if [[ "$IS_REGIONAL" == "true" ]]; then echo "regional ($EFFECTIVE_REGION)"; else echo "global"; fi)"
echo
log "POC 资源命名："
echo "  HC:   $POC_HC"
echo "  BS:   $POC_BS"
echo "  UM:   $POC_UM"
echo "  Proxy: $POC_PROXY"
echo "  FR:   $POC_FR"
echo

# ─── 阶段 5：生成 gcloud 创建命令 ────────────────────────────
log "━━━ Step 4: 生成 POC 创建命令 ━━━"
echo

REGION_FLAG=""
if [[ "$IS_REGIONAL" == "true" && -n "$EFFECTIVE_REGION" ]]; then
  REGION_FLAG="--region $EFFECTIVE_REGION"
fi

PROJECT_FLAG=""
[[ -n "$PROJECT" ]] && PROJECT_FLAG="--project $PROJECT"

generate_commands() {
  cat <<HEADER
#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# POC Load Balancer 创建命令
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')
# 参考 MIG: $REF_MIG
# 参考链路: $REF_BS_NAME → $REF_UM_NAME → $REF_PROXY_NAME → $REF_FR_NAME
# 资源前缀: $POC_PREFIX
# Scope:    $(if [[ "$IS_REGIONAL" == "true" ]]; then echo "regional ($EFFECTIVE_REGION)"; else echo "global"; fi)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

HEADER

  # Step 1: Health Check
  echo "# ─── Step 1: 创建 Health Check ─────────────────────────────"
  echo "# 参考: $REF_HC_NAME (${REF_HC_PROTOCOL}:${REF_HC_PORT}${REF_HC_PATH:+ $REF_HC_PATH})"
  echo ""

  hc_type_flag=""
  hc_extra=""
  case "${REF_HC_PROTOCOL^^}" in
    HTTP)
      hc_type_flag="--protocol=HTTP --port=${REF_HC_PORT}"
      [[ -n "$REF_HC_PATH" && "$REF_HC_PATH" != "-" ]] && hc_extra="--request-path=${REF_HC_PATH}"
      ;;
    HTTPS)
      hc_type_flag="--protocol=HTTPS --port=${REF_HC_PORT}"
      [[ -n "$REF_HC_PATH" && "$REF_HC_PATH" != "-" ]] && hc_extra="--request-path=${REF_HC_PATH}"
      ;;
    HTTP2)
      hc_type_flag="--protocol=HTTP2 --port=${REF_HC_PORT}"
      [[ -n "$REF_HC_PATH" && "$REF_HC_PATH" != "-" ]] && hc_extra="--request-path=${REF_HC_PATH}"
      ;;
    TCP)
      hc_type_flag="--protocol=TCP --port=${REF_HC_PORT}"
      ;;
    *)
      hc_type_flag="--protocol=HTTP --port=${REF_HC_PORT:-80}"
      hc_extra="--request-path=/"
      ;;
  esac

  printf 'gcloud compute health-checks create %s \\\n' "$POC_HC"
  printf '  %s \\\n' "$hc_type_flag"
  [[ -n "$hc_extra" ]] && printf '  %s \\\n' "$hc_extra"
  [[ -n "$REF_HC_INTERVAL" && "$REF_HC_INTERVAL" != "-" ]] && printf '  --check-interval=%ss \\\n' "$REF_HC_INTERVAL"
  [[ -n "$REF_HC_TIMEOUT" && "$REF_HC_TIMEOUT" != "-" ]] && printf '  --timeout=%ss \\\n' "$REF_HC_TIMEOUT"
  [[ -n "$REGION_FLAG" ]] && printf '  %s \\\n' "$REGION_FLAG"
  [[ -n "$PROJECT_FLAG" ]] && printf '  %s \\\n' "$PROJECT_FLAG"
  printf '  --description="POC health check, ref: %s"\n' "$REF_HC_NAME"
  echo ""

  # Step 2: Backend Service
  echo "# ─── Step 2: 创建 Backend Service ──────────────────────────"
  echo "# 参考: $REF_BS_NAME (scheme=$REF_BS_SCHEME, proto=$REF_BS_PROTOCOL)"
  echo ""

  if [[ "$IS_REGIONAL" == "true" ]]; then
    bs_cmd="gcloud compute backend-services create $POC_BS"
  else
    bs_cmd="gcloud compute backend-services create $POC_BS --global"
  fi

  printf '%s \\\n' "$bs_cmd"
  printf '  --load-balancing-scheme=%s \\\n' "$REF_BS_SCHEME"
  printf '  --protocol=%s \\\n' "$REF_BS_PROTOCOL"
  printf '  --health-checks=%s \\\n' "$POC_HC"
  [[ -n "$REF_BS_PORT_NAME" && "$REF_BS_PORT_NAME" != "-" ]] && printf '  --port-name=%s \\\n' "$REF_BS_PORT_NAME"
  [[ -n "$REF_BS_TIMEOUT" && "$REF_BS_TIMEOUT" != "-" ]] && printf '  --timeout=%s \\\n' "$REF_BS_TIMEOUT"
  [[ -n "$REF_BS_SESSION_AFFINITY" && "$REF_BS_SESSION_AFFINITY" != "NONE" ]] && printf '  --session-affinity=%s \\\n' "$REF_BS_SESSION_AFFINITY"
  if [[ "$IS_REGIONAL" == "true" ]]; then
    printf '  --region=%s \\\n' "$EFFECTIVE_REGION"
    printf '  --health-checks-region=%s \\\n' "$EFFECTIVE_REGION"
  else
    printf '  --global-health-checks \\\n'
  fi
  [[ -n "$PROJECT_FLAG" ]] && printf '  %s \\\n' "$PROJECT_FLAG"
  printf '  --description="POC backend service, ref: %s"\n' "$REF_BS_NAME"
  echo ""

  # Step 2.5: Add backend (共享同一个 MIG)
  echo "# ─── Step 2.5: 添加 Backend（共享 MIG）─────────────────────"
  echo "# 共享: $REF_MIG (instance-group: $REF_IG)"
  echo ""

  if [[ "$IS_REGIONAL" == "true" ]]; then
    printf 'gcloud compute backend-services add-backend %s \\\n' "$POC_BS"
    printf '  --instance-group=%s \\\n' "$REF_IG"
    printf '  --instance-group-zone=%s \\\n' "$REF_ZONE"
    printf '  --balancing-mode=%s \\\n' "$REF_BS_BALANCING_MODE"
    printf '  --region=%s \\\n' "$EFFECTIVE_REGION"
    [[ -n "$PROJECT_FLAG" ]] && printf '  %s\n' "$PROJECT_FLAG"
  else
    printf 'gcloud compute backend-services add-backend %s \\\n' "$POC_BS"
    printf '  --instance-group=%s \\\n' "$REF_IG"
    printf '  --instance-group-zone=%s \\\n' "$REF_ZONE"
    printf '  --balancing-mode=%s \\\n' "$REF_BS_BALANCING_MODE"
    printf '  --global \\\n'
    [[ -n "$PROJECT_FLAG" ]] && printf '  %s\n' "$PROJECT_FLAG"
  fi
  echo ""

  # Step 3: URL Map
  echo "# ─── Step 3: 创建 URL Map ──────────────────────────────────"
  echo "# 参考: $REF_UM_NAME"
  echo ""

  if [[ "$IS_REGIONAL" == "true" ]]; then
    printf 'gcloud compute url-maps create %s \\\n' "$POC_UM"
    printf '  --default-service=%s \\\n' "$POC_BS"
    printf '  --region=%s \\\n' "$EFFECTIVE_REGION"
  else
    printf 'gcloud compute url-maps create %s \\\n' "$POC_UM"
    printf '  --default-service=%s \\\n' "$POC_BS"
    printf '  --global \\\n'
  fi
  [[ -n "$PROJECT_FLAG" ]] && printf '  %s \\\n' "$PROJECT_FLAG"
  printf '  --description="POC url map, ref: %s"\n' "$REF_UM_NAME"
  echo ""

  # Step 4: Target Proxy
  echo "# ─── Step 4: 创建 Target Proxy ─────────────────────────────"
  echo "# 参考: $REF_PROXY_NAME ($REF_PROXY_KIND)"
  echo ""

  case "${REF_PROXY_KIND}" in
    https)
      if [[ "$IS_REGIONAL" == "true" ]]; then
        printf 'gcloud compute target-https-proxies create %s \\\n' "$POC_PROXY"
        printf '  --url-map=%s \\\n' "$POC_UM"
        printf '  --region=%s \\\n' "$EFFECTIVE_REGION"
      else
        printf 'gcloud compute target-https-proxies create %s \\\n' "$POC_PROXY"
        printf '  --url-map=%s \\\n' "$POC_UM"
        printf '  --global \\\n'
      fi
      if [[ -n "$REF_SSL_CERTS" && "$REF_SSL_CERTS" != "-" ]]; then
        echo "  # ⚠️  原链路使用的 SSL 证书: $REF_SSL_CERTS"
        echo "  # 你需要指定自己的证书或复用已有证书："
        printf '  --ssl-certificates=%s \\\n' "$REF_SSL_CERTS"
      else
        echo "  # ⚠️  需要指定 SSL 证书！"
        printf '  --ssl-certificates=YOUR_CERT_NAME \\\n'
      fi
      ;;
    http)
      if [[ "$IS_REGIONAL" == "true" ]]; then
        printf 'gcloud compute target-http-proxies create %s \\\n' "$POC_PROXY"
        printf '  --url-map=%s \\\n' "$POC_UM"
        printf '  --region=%s \\\n' "$EFFECTIVE_REGION"
      else
        printf 'gcloud compute target-http-proxies create %s \\\n' "$POC_PROXY"
        printf '  --url-map=%s \\\n' "$POC_UM"
        printf '  --global \\\n'
      fi
      ;;
  esac
  [[ -n "$PROJECT_FLAG" ]] && printf '  %s\n' "$PROJECT_FLAG"
  echo ""

  # Step 5: Forwarding Rule
  echo "# ─── Step 5: 创建 Forwarding Rule ──────────────────────────"
  echo "# 参考: $REF_FR_NAME (scheme=$REF_FR_SCHEME, ip=$REF_FR_IP, ports=$REF_FR_PORTS)"
  echo ""

  printf 'gcloud compute forwarding-rules create %s \\\n' "$POC_FR"
  printf '  --load-balancing-scheme=%s \\\n' "$REF_FR_SCHEME"
  printf '  --target-%s-proxy=%s \\\n' "$REF_PROXY_KIND" "$POC_PROXY"

  if [[ "$REF_FR_PORTS" == *"-"* || "$REF_FR_PORTS" == *","* || "$REF_FR_PORTS" =~ ^[0-9]+$ ]]; then
    # 判断是 port-range 还是 ports
    if [[ "$REF_FR_PORTS" == *"-"* ]]; then
      printf '  --ports=%s \\\n' "$REF_FR_PORTS"
    else
      printf '  --ports=%s \\\n' "$REF_FR_PORTS"
    fi
  fi

  if [[ "$IS_REGIONAL" == "true" ]]; then
    printf '  --region=%s \\\n' "$EFFECTIVE_REGION"
    [[ -n "$REF_FR_NETWORK" && "$REF_FR_NETWORK" != "-" ]] && printf '  --network=%s \\\n' "$REF_FR_NETWORK"
    [[ -n "$REF_FR_SUBNETWORK" && "$REF_FR_SUBNETWORK" != "-" ]] && printf '  --subnet=%s \\\n' "$REF_FR_SUBNETWORK"
  else
    printf '  --global \\\n'
    printf '  --global-target-%s-proxy \\\n' "$REF_PROXY_KIND"
  fi
  [[ -n "$REF_FR_IP" && "$REF_FR_IP" != "-" ]] && echo "  # 原链路 IP: $REF_FR_IP (POC 通常用临时 IP，注释掉这行)"
  echo "  # --address=YOUR_STATIC_IP  # 可选：指定静态 IP"
  [[ -n "$PROJECT_FLAG" ]] && printf '  %s \\\n' "$PROJECT_FLAG"
  printf '  --description="POC forwarding rule, ref: %s"\n' "$REF_FR_NAME"
  echo ""

  # 清理命令
  cat <<CLEANUP

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# POC 清理命令（用完后按逆序删除）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Step 5: 删除 Forwarding Rule
# gcloud compute forwarding-rules delete $POC_FR $REGION_FLAG $PROJECT_FLAG --quiet

# Step 4: 删除 Target Proxy
# gcloud compute target-${REF_PROXY_KIND}-proxies delete $POC_PROXY $REGION_FLAG $PROJECT_FLAG --quiet

# Step 3: 删除 URL Map
# gcloud compute url-maps delete $POC_UM $REGION_FLAG $PROJECT_FLAG --quiet

# Step 2: 删除 Backend Service
# gcloud compute backend-services delete $POC_BS $(if [[ "$IS_REGIONAL" == "true" ]]; then echo "$REGION_FLAG"; else echo "--global"; fi) $PROJECT_FLAG --quiet

# Step 1: 删除 Health Check
# gcloud compute health-checks delete $POC_HC $REGION_FLAG $PROJECT_FLAG --quiet
CLEANUP
}

if [[ -n "$OUTPUT_FILE" ]]; then
  generate_commands > "$OUTPUT_FILE"
  chmod +x "$OUTPUT_FILE"
  ok "创建命令已写入: $OUTPUT_FILE"
  echo "  运行: bash $OUTPUT_FILE"
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  generate_commands
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo
ok "完成！请仔细检查以上命令后再执行。"
echo
warn "注意事项："
echo "  1. SSL 证书：如果是 HTTPS proxy，请确认证书名是否正确/可复用"
echo "  2. 静态 IP：POC 默认使用临时 IP，如需固定 IP 请取消注释 --address"
echo "  3. Firewall：确认 MIG 所在网络的防火墙允许 health check 流量"
echo "  4. Proxy-only Subnet：regional LB 需要 proxy-only subnet 已就绪"
echo "  5. Named Ports：确认 MIG 的 named port ($REF_NAMED_PORTS) 与 backend service port-name 匹配"
