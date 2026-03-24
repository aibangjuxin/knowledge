#!/usr/bin/env bash
# =============================================================================
# lb-poc-gen.sh — 从已有 MIG 探索 LB 依赖链，并生成 POC 创建命令
# =============================================================================
# 核心目标：
#   1. 输入一个 MIG 名称（或 pattern）
#   2. 自动探索：MIG → Backend Service → URL Map → Target Proxy → Forwarding Rule
#   3. 读取每个资源的关键参数
#   4. 生成一套可直接执行的 gcloud 命令，用于复刻一套 POC LB（共享同一 MIG）
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────
# 颜色输出
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"; }
step()    { echo -e "${GREEN}▶${NC} $*"; }

# ─────────────────────────────────────────────
# 用法说明
# ─────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage:
  lb-poc-gen.sh <mig-name-or-pattern> [options]

Options:
  --project <project-id>       GCP project ID
  --region  <region>           过滤 MIG / LB 所在 region
  --zone    <zone>             过滤 MIG 所在 zone
  --poc-prefix <prefix>        POC 资源名称前缀（默认：poc）
  --poc-region <region>        POC 资源创建 region（默认跟参考 LB 一致）
  --output-file <file>         把生成的命令写入文件（默认：stdout）
  --dry-run                    只打印命令，不执行
  --execute                    实际执行生成的创建命令（需要手动确认）
  -h, --help                   显示帮助

Examples:
  # 探索 + 生成命令（不执行）
  lb-poc-gen.sh my-api-mig --project my-proj --dry-run

  # 生成命令并写入文件
  lb-poc-gen.sh my-api-mig --project my-proj --poc-prefix poc-v2 --output-file poc-cmds.sh

  # 探索 + 交互确认后执行
  lb-poc-gen.sh my-api-mig --project my-proj --poc-prefix poc-v2 --execute

Dependencies: gcloud, jq
EOF
}

# ─────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { error "缺少依赖命令: $1"; exit 1; }
}

name_from_ref() {
  local ref="${1:-}"; ref="${ref%/}"; echo "${ref##*/}"
}

resource_scope() {
  local json="$1"
  local region; region="$(jq -r '.region // empty' <<<"$json")"
  if [[ -n "$region" ]]; then echo "regional:$(name_from_ref "$region")"
  else echo "global"; fi
}

safe_name() {
  # 把任意字符串转成合法 GCP 资源名（小写字母、数字、连字符，最长 63 字符）
  local s; s="$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  echo "${s:0:63}"
}

# ─────────────────────────────────────────────
# 参数解析
# ─────────────────────────────────────────────
PROJECT=""
REGION=""
ZONE=""
POC_PREFIX="poc"
POC_REGION=""
OUTPUT_FILE=""
DRY_RUN="false"
EXECUTE="false"
MIG_PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)      PROJECT="$2";      shift 2 ;;
    --region)       REGION="$2";       shift 2 ;;
    --zone)         ZONE="$2";         shift 2 ;;
    --poc-prefix)   POC_PREFIX="$2";   shift 2 ;;
    --poc-region)   POC_REGION="$2";   shift 2 ;;
    --output-file)  OUTPUT_FILE="$2";  shift 2 ;;
    --dry-run)      DRY_RUN="true";    shift ;;
    --execute)      EXECUTE="true";    shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)             error "未知参数: $1"; usage >&2; exit 1 ;;
    *)
      if [[ -z "$MIG_PATTERN" ]]; then MIG_PATTERN="$1"
      else error "多余的参数: $1"; usage >&2; exit 1; fi
      shift ;;
  esac
done

[[ -z "$MIG_PATTERN" ]] && { error "必须指定 MIG 名称或 pattern"; usage >&2; exit 1; }

require_cmd gcloud
require_cmd jq

# ─────────────────────────────────────────────
# gcloud 基础命令
# ─────────────────────────────────────────────
GCLOUD_BASE=(gcloud)
[[ -n "$PROJECT" ]] && GCLOUD_BASE+=(--project "$PROJECT")

run_gcloud() { "${GCLOUD_BASE[@]}" "$@" --format=json 2>/dev/null; }

# ─────────────────────────────────────────────
# 阶段一：拉取所有相关资源
# ─────────────────────────────────────────────
section "阶段一：拉取 GCP 资源数据"

info "拉取 MIG 列表..."
MIGS_JSON="$(run_gcloud compute instance-groups managed list)"

info "拉取 Backend Services..."
BACKENDS_JSON="$(run_gcloud compute backend-services list)"

info "拉取 Health Checks..."
HC_JSON="$(run_gcloud compute health-checks list 2>/dev/null || echo '[]')"
HC_HTTP_JSON="$(run_gcloud compute http-health-checks list 2>/dev/null || echo '[]')"
HC_HTTPS_JSON="$(run_gcloud compute https-health-checks list 2>/dev/null || echo '[]')"

info "拉取 URL Maps..."
URL_MAPS_JSON="$(run_gcloud compute url-maps list)"

info "拉取 Target Proxies..."
TP_HTTP_JSON="$(run_gcloud  compute target-http-proxies list  2>/dev/null || echo '[]')"
TP_HTTPS_JSON="$(run_gcloud compute target-https-proxies list 2>/dev/null || echo '[]')"
TP_TCP_JSON="$(run_gcloud   compute target-tcp-proxies list   2>/dev/null || echo '[]')"
TP_SSL_JSON="$(run_gcloud   compute target-ssl-proxies list   2>/dev/null || echo '[]')"
TP_GRPC_JSON="$(run_gcloud  compute target-grpc-proxies list  2>/dev/null || echo '[]')"

info "拉取 Forwarding Rules..."
FR_JSON="$(run_gcloud compute forwarding-rules list)"

success "资源数据拉取完成"

# 临时目录
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 合并所有 proxies
PROXIES_FILE="$TMP_DIR/proxies.jsonl"
>"$PROXIES_FILE"
echo "$TP_HTTP_JSON"  | jq -c '.[] | .proxyKind="http"'  >> "$PROXIES_FILE"
echo "$TP_HTTPS_JSON" | jq -c '.[] | .proxyKind="https"' >> "$PROXIES_FILE"
echo "$TP_TCP_JSON"   | jq -c '.[] | .proxyKind="tcp"'   >> "$PROXIES_FILE"
echo "$TP_SSL_JSON"   | jq -c '.[] | .proxyKind="ssl"'   >> "$PROXIES_FILE"
echo "$TP_GRPC_JSON"  | jq -c '.[] | .proxyKind="grpc"'  >> "$PROXIES_FILE"

# URL Maps 详情（含 pathMatchers）
URL_MAPS_DETAIL_FILE="$TMP_DIR/url_maps_detail.jsonl"
>"$URL_MAPS_DETAIL_FILE"
echo "$URL_MAPS_JSON" | jq -c '.[]' | while IFS= read -r um; do
  um_name="$(jq -r '.name' <<<"$um")"
  region_ref="$(jq -r '.region // empty' <<<"$um")"
  if [[ -n "$region_ref" ]]; then
    region_n="$(name_from_ref "$region_ref")"
    run_gcloud compute url-maps describe "$um_name" --region "$region_n" | jq -c '.' >> "$URL_MAPS_DETAIL_FILE" 2>/dev/null || true
  else
    run_gcloud compute url-maps describe "$um_name" | jq -c '.' >> "$URL_MAPS_DETAIL_FILE" 2>/dev/null || true
  fi
done

# ─────────────────────────────────────────────
# 阶段二：匹配 MIG，探索 LB 链路
# ─────────────────────────────────────────────
section "阶段二：探索 LB 链路"

FOUND_MIG=""
FOUND_MIG_JSON=""
FOUND_BACKEND_JSON=""
FOUND_URL_MAP_JSON=""
FOUND_PROXY_JSON=""
FOUND_FR_JSON=""
FOUND_HC_JSON=""

# ── 2.1 找 MIG ──
while IFS= read -r mig; do
  mig_name="$(jq -r '.name' <<<"$mig")"
  [[ "$mig_name" =~ $MIG_PATTERN ]] || continue

  zone_ref="$(jq -r '.zone // empty' <<<"$mig")"
  region_ref="$(jq -r '.region // empty' <<<"$mig")"
  zone_name="$(name_from_ref "$zone_ref")"
  region_name="$(name_from_ref "$region_ref")"
  zone_region="${zone_name%-*}"

  [[ -n "$ZONE"   && "$zone_name" != "$ZONE"                                        ]] && continue
  [[ -n "$REGION" && "$REGION" != "$region_name" && "$REGION" != "$zone_region"     ]] && continue

  FOUND_MIG="$mig_name"
  FOUND_MIG_JSON="$mig"
  info "找到 MIG: ${BOLD}$mig_name${NC} (zone: $zone_name)"
  break
done < <(echo "$MIGS_JSON" | jq -c '.[]')

if [[ -z "$FOUND_MIG" ]]; then
  error "未找到匹配 pattern='$MIG_PATTERN' 的 MIG"
  exit 1
fi

INSTANCE_GROUP="$(jq -r '.instanceGroup // .selfLink' <<<"$FOUND_MIG_JSON")"

# ── 2.2 找 Backend Service ──
while IFS= read -r bs; do
  bs_name="$(jq -r '.name' <<<"$bs")"
  found="$(jq -r --arg ig "$INSTANCE_GROUP" \
    '.backends // [] | map(select(.group == $ig or (.group | split("/")[-1]) == ($ig | split("/")[-1]))) | length' \
    <<<"$bs")"
  [[ "$found" -gt 0 ]] || continue

  FOUND_BACKEND_JSON="$bs"
  info "找到 Backend Service: ${BOLD}$bs_name${NC} (scheme: $(jq -r '.loadBalancingScheme' <<<"$bs"))"
  break
done < <(echo "$BACKENDS_JSON" | jq -c '.[]')

if [[ -z "$FOUND_BACKEND_JSON" ]]; then
  warn "未找到引用该 MIG 的 Backend Service，将只生成 Health Check + Backend Service 命令"
fi

BS_SELF_LINK="$(jq -r '.selfLink // empty' <<<"${FOUND_BACKEND_JSON:-{}}")"
BS_NAME="$(jq -r '.name // empty'          <<<"${FOUND_BACKEND_JSON:-{}}")"

# ── 2.3 找 Health Check ──
if [[ -n "$FOUND_BACKEND_JSON" ]]; then
  first_hc_ref="$(jq -r '.healthChecks[0] // empty' <<<"$FOUND_BACKEND_JSON")"
  first_hc_name="$(name_from_ref "$first_hc_ref")"
  if [[ -n "$first_hc_name" ]]; then
    FOUND_HC_JSON="$(echo "$HC_JSON" | jq -c --arg n "$first_hc_name" '.[] | select(.name==$n)' | head -1)"
    if [[ -n "$FOUND_HC_JSON" ]]; then
      info "找到 Health Check: ${BOLD}$first_hc_name${NC}"
    fi
  fi
fi

# ── 2.4 找 URL Map ──
if [[ -n "$FOUND_BACKEND_JSON" ]]; then
  while IFS= read -r um; do
    [[ -z "$um" ]] && continue
    um_name="$(jq -r '.name' <<<"$um")"
    has_bs="$(jq -r --arg bs_name "$BS_NAME" '
      [
        .defaultService,
        (.pathMatchers[]?.defaultService // empty),
        (.pathMatchers[]?.pathRules[]?.service // empty),
        (.pathMatchers[]?.routeRules[]?.routeAction?.weightedBackendServices[]?.backendService // empty)
      ] | flatten | map(select(. != null) | split("/")[-1]) | any(. == $bs_name)
    ' <<<"$um")"
    [[ "$has_bs" == "true" ]] || continue
    FOUND_URL_MAP_JSON="$um"
    info "找到 URL Map: ${BOLD}$um_name${NC}"
    break
  done < "$URL_MAPS_DETAIL_FILE"
fi

UM_NAME="$(jq -r '.name // empty' <<<"${FOUND_URL_MAP_JSON:-{}}")"
UM_SELF_LINK="$(jq -r '.selfLink // empty' <<<"${FOUND_URL_MAP_JSON:-{}}")"

# ── 2.5 找 Target Proxy ──
if [[ -n "$FOUND_URL_MAP_JSON" ]]; then
  while IFS= read -r proxy; do
    [[ -z "$proxy" ]] && continue
    proxy_um="$(jq -r '.urlMap // empty' <<<"$proxy")"
    proxy_um_name="$(name_from_ref "$proxy_um")"
    [[ "$proxy_um_name" == "$UM_NAME" || "$proxy_um" == "$UM_SELF_LINK" ]] || continue
    FOUND_PROXY_JSON="$proxy"
    info "找到 Target Proxy: ${BOLD}$(jq -r '.name' <<<"$proxy")${NC} (kind: $(jq -r '.proxyKind' <<<"$proxy"))"
    break
  done < "$PROXIES_FILE"
fi

PROXY_NAME="$(jq -r '.name // empty'     <<<"${FOUND_PROXY_JSON:-{}}")"
PROXY_SL="$(jq -r '.selfLink // empty'   <<<"${FOUND_PROXY_JSON:-{}}")"
PROXY_KIND="$(jq -r '.proxyKind // empty' <<<"${FOUND_PROXY_JSON:-{}}")"

# ── 2.6 找 Forwarding Rule ──
if [[ -n "$FOUND_PROXY_JSON" ]]; then
  while IFS= read -r fr; do
    fr_target="$(jq -r '.target // empty' <<<"$fr")"
    fr_target_name="$(name_from_ref "$fr_target")"
    [[ "$fr_target_name" == "$PROXY_NAME" || "$fr_target" == "$PROXY_SL" ]] || continue
    FOUND_FR_JSON="$fr"
    info "找到 Forwarding Rule: ${BOLD}$(jq -r '.name' <<<"$fr")${NC}"
    break
  done < <(echo "$FR_JSON" | jq -c '.[]')
fi

# ─────────────────────────────────────────────
# 阶段三：提取参数，构建 POC 资源名
# ─────────────────────────────────────────────
section "阶段三：提取参数"

MIG_ZONE="$(jq -r '.zone // empty | split("/")[-1]' <<<"$FOUND_MIG_JSON")"
MIG_REGION_RAW="$(jq -r '.region // empty | split("/")[-1]' <<<"$FOUND_MIG_JSON")"
# zone-based MIG 时 region 从 zone 推导
if [[ -z "$MIG_REGION_RAW" && -n "$MIG_ZONE" ]]; then
  MIG_REGION_RAW="${MIG_ZONE%-*}"
fi
REF_REGION="${POC_REGION:-$MIG_REGION_RAW}"

# POC 名称
BASE="$(safe_name "${POC_PREFIX}-$(safe_name "$FOUND_MIG")")"
POC_HC_NAME="${BASE}-hc"
POC_BS_NAME="${BASE}-bs"
POC_UM_NAME="${BASE}-um"
POC_PROXY_NAME="${BASE}-proxy"
POC_FR_NAME="${BASE}-fr"

echo ""
echo "  参考 MIG    : $FOUND_MIG"
echo "  参考 Region : $REF_REGION"
echo "  POC Prefix  : $POC_PREFIX"
echo "  POC HC      : $POC_HC_NAME"
echo "  POC BS      : $POC_BS_NAME"
echo "  POC UM      : $POC_UM_NAME"
echo "  POC Proxy   : $POC_PROXY_NAME"
echo "  POC FR      : $POC_FR_NAME"
echo ""

# ── 提取 Health Check 参数 ──
if [[ -n "${FOUND_HC_JSON:-}" ]]; then
  HC_TYPE="$(jq -r '.type // "HTTP"' <<<"$FOUND_HC_JSON" | tr '[:upper:]' '[:lower:]')"
  HC_PORT="$(jq -r '.${HC_TYPE}HealthCheck.port // .port // 80' <<<"$FOUND_HC_JSON" 2>/dev/null || echo 80)"
  # 更安全的提取方式
  HC_PORT="$(jq -r '
    .httpHealthCheck.port //
    .httpsHealthCheck.port //
    .tcpHealthCheck.port //
    .grpcHealthCheck.port //
    .port // 80' <<<"$FOUND_HC_JSON")"
  HC_PATH="$(jq -r '.httpHealthCheck.requestPath // .httpsHealthCheck.requestPath // "/"' <<<"$FOUND_HC_JSON")"
  HC_INTERVAL="$(jq -r '.checkIntervalSec // 10' <<<"$FOUND_HC_JSON")"
  HC_TIMEOUT="$(jq -r '.timeoutSec // 5'  <<<"$FOUND_HC_JSON")"
  HC_HEALTHY="$(jq -r '.healthyThreshold // 2'   <<<"$FOUND_HC_JSON")"
  HC_UNHEALTHY="$(jq -r '.unhealthyThreshold // 2' <<<"$FOUND_HC_JSON")"
else
  warn "未找到参考 Health Check，使用默认 HTTP:80/ 参数"
  HC_TYPE="http"; HC_PORT=80; HC_PATH="/"; HC_INTERVAL=10; HC_TIMEOUT=5; HC_HEALTHY=2; HC_UNHEALTHY=2
fi

# ── 提取 Backend Service 参数 ──
if [[ -n "${FOUND_BACKEND_JSON:-}" ]]; then
  BS_PROTOCOL="$(jq -r '.protocol // "HTTP"' <<<"$FOUND_BACKEND_JSON")"
  BS_SCHEME="$(jq -r '.loadBalancingScheme // "EXTERNAL"' <<<"$FOUND_BACKEND_JSON")"
  BS_TIMEOUT="$(jq -r '.timeoutSec // 30' <<<"$FOUND_BACKEND_JSON")"
  BS_SESSION="$(jq -r '.sessionAffinity // "NONE"' <<<"$FOUND_BACKEND_JSON")"
  BS_BALANCING="$(jq -r '.backends[0].balancingMode // "UTILIZATION"' <<<"$FOUND_BACKEND_JSON")"
  BS_NAMED_PORT="$(jq -r '.portName // "http"' <<<"$FOUND_BACKEND_JSON")"
  BS_REGION_REF="$(jq -r '.region // empty | split("/")[-1]' <<<"$FOUND_BACKEND_JSON")"
else
  BS_PROTOCOL="HTTP"; BS_SCHEME="EXTERNAL"; BS_TIMEOUT=30; BS_SESSION="NONE"
  BS_BALANCING="UTILIZATION"; BS_NAMED_PORT="http"; BS_REGION_REF=""
fi

# ── 提取 Forwarding Rule 参数 ──
if [[ -n "${FOUND_FR_JSON:-}" ]]; then
  FR_SCHEME="$(jq -r '.loadBalancingScheme // "EXTERNAL"' <<<"$FOUND_FR_JSON")"
  FR_PORTS="$(jq -r '
    if (.ports // empty) != null and (.ports | length) > 0
    then (.ports | join(","))
    else (.portRange // "80")
    end' <<<"$FOUND_FR_JSON")"
  FR_PROTOCOL="$(jq -r '.IPProtocol // "TCP"' <<<"$FOUND_FR_JSON")"
  FR_REGION_REF="$(jq -r '.region // empty | split("/")[-1]' <<<"$FOUND_FR_JSON")"
  FR_NETWORK="$(jq -r '.network // empty | split("/")[-1]' <<<"$FOUND_FR_JSON")"
  FR_SUBNET="$(jq -r '.subnetwork // empty | split("/")[-1]' <<<"$FOUND_FR_JSON")"
else
  FR_SCHEME="EXTERNAL"; FR_PORTS="80"; FR_PROTOCOL="TCP"
  FR_REGION_REF=""; FR_NETWORK=""; FR_SUBNET=""
fi

# ── 判断 global vs regional ──
IS_REGIONAL="false"
if [[ "$BS_SCHEME" == "INTERNAL"* || -n "$BS_REGION_REF" || -n "$FR_REGION_REF" ]]; then
  IS_REGIONAL="true"
fi

# ─────────────────────────────────────────────
# 阶段四：生成 gcloud 命令
# ─────────────────────────────────────────────
section "阶段四：生成 POC 创建命令"

PROJECT_FLAG=""; [[ -n "$PROJECT" ]] && PROJECT_FLAG="--project $PROJECT"
REGION_FLAG=""; [[ -n "$REF_REGION" ]] && REGION_FLAG="--region $REF_REGION"

# 根据是否 regional 决定 scope flag
if [[ "$IS_REGIONAL" == "true" ]]; then
  SCOPE_FLAG="$REGION_FLAG"
  BS_SCOPE_FLAG="$REGION_FLAG"
  UM_SCOPE_FLAG="$REGION_FLAG"
  FR_SCOPE_FLAG="$REGION_FLAG"
else
  SCOPE_FLAG="--global"
  BS_SCOPE_FLAG="--global"
  UM_SCOPE_FLAG="--global"
  FR_SCOPE_FLAG=""  # global FR 不加 --global
fi

# ── 命令构建 ──
CMD_SEPARATOR="# ──────────────────────────────────────────"

# Step 1: Health Check
CMD_HC_CHECK="gcloud compute health-checks describe \"$POC_HC_NAME\" $SCOPE_FLAG $PROJECT_FLAG 2>/dev/null && echo 'EXISTS' || echo 'NOT_FOUND'"

CMD_HC_CREATE="gcloud compute health-checks create $HC_TYPE \"$POC_HC_NAME\" \\
  --port=$HC_PORT \\
  --request-path=\"$HC_PATH\" \\
  --check-interval=${HC_INTERVAL}s \\
  --timeout=${HC_TIMEOUT}s \\
  --healthy-threshold=$HC_HEALTHY \\
  --unhealthy-threshold=$HC_UNHEALTHY \\
  $SCOPE_FLAG \\
  $PROJECT_FLAG"

# Step 2: Backend Service
BS_REGION_PART=""
[[ "$IS_REGIONAL" == "true" && -n "$REF_REGION" ]] && BS_REGION_PART="--region $REF_REGION"

CMD_BS_CREATE="gcloud compute backend-services create \"$POC_BS_NAME\" \\
  --protocol=$BS_PROTOCOL \\
  --load-balancing-scheme=$BS_SCHEME \\
  --timeout=${BS_TIMEOUT}s \\
  --session-affinity=$BS_SESSION \\
  --port-name=$BS_NAMED_PORT \\
  --health-checks=\"$POC_HC_NAME\" \\
  $BS_SCOPE_FLAG \\
  $PROJECT_FLAG"

# Step 3: 添加 MIG 到 Backend Service
CMD_BS_ADD_MIG_BASE="gcloud compute backend-services add-backend \"$POC_BS_NAME\" \\
  --instance-group=\"$FOUND_MIG\" \\
  --balancing-mode=$BS_BALANCING \\"
if [[ -n "$MIG_ZONE" ]]; then
  CMD_BS_ADD_MIG="${CMD_BS_ADD_MIG_BASE}
  --instance-group-zone=$MIG_ZONE \\"
else
  CMD_BS_ADD_MIG="${CMD_BS_ADD_MIG_BASE}
  --instance-group-region=$MIG_REGION_RAW \\"
fi
CMD_BS_ADD_MIG="${CMD_BS_ADD_MIG}
  $BS_SCOPE_FLAG \\
  $PROJECT_FLAG"

# Step 4: URL Map
CMD_UM_CREATE="gcloud compute url-maps create \"$POC_UM_NAME\" \\
  --default-service=\"$POC_BS_NAME\" \\
  $UM_SCOPE_FLAG \\
  $PROJECT_FLAG"

# Step 5: Target Proxy
PROXY_KIND_EFFECTIVE="${PROXY_KIND:-http}"
CERTS_FLAG=""
if [[ "$PROXY_KIND_EFFECTIVE" == "https" ]]; then
  ref_certs="$(jq -r '.sslCertificates // [] | map(split("/")[-1]) | join(",")' <<<"${FOUND_PROXY_JSON:-{}}")"
  if [[ -n "$ref_certs" ]]; then
    warn "参考 HTTPS proxy 使用了证书: $ref_certs，POC 需要替换为你自己的证书"
    CERTS_FLAG="--ssl-certificates=<YOUR_CERT_NAME>  # 请替换"
  fi
fi

if [[ "$PROXY_KIND_EFFECTIVE" == "http" ]]; then
  CMD_PROXY_CREATE="gcloud compute target-http-proxies create \"$POC_PROXY_NAME\" \\
  --url-map=\"$POC_UM_NAME\" \\
  $SCOPE_FLAG \\
  $PROJECT_FLAG"
elif [[ "$PROXY_KIND_EFFECTIVE" == "https" ]]; then
  CMD_PROXY_CREATE="gcloud compute target-https-proxies create \"$POC_PROXY_NAME\" \\
  --url-map=\"$POC_UM_NAME\" \\
  $CERTS_FLAG \\
  $SCOPE_FLAG \\
  $PROJECT_FLAG"
elif [[ "$PROXY_KIND_EFFECTIVE" == "tcp" ]]; then
  CMD_PROXY_CREATE="gcloud compute target-tcp-proxies create \"$POC_PROXY_NAME\" \\
  --backend-service=\"$POC_BS_NAME\" \\
  $PROJECT_FLAG"
else
  CMD_PROXY_CREATE="# [!] proxy kind='$PROXY_KIND_EFFECTIVE'，请手动确认创建命令"
fi

# Step 6: Forwarding Rule
if [[ "$IS_REGIONAL" == "true" ]]; then
  FR_NETWORK_FLAG=""; [[ -n "$FR_NETWORK" ]] && FR_NETWORK_FLAG="--network=$FR_NETWORK"
  FR_SUBNET_FLAG=""; [[ -n "$FR_SUBNET"  ]] && FR_SUBNET_FLAG="--subnet=$FR_SUBNET"
  CMD_FR_CREATE="gcloud compute forwarding-rules create \"$POC_FR_NAME\" \\
  --load-balancing-scheme=$FR_SCHEME \\
  --target-$(echo "$PROXY_KIND_EFFECTIVE")-proxy=\"$POC_PROXY_NAME\" \\
  --ports=$FR_PORTS \\
  $FR_SCOPE_FLAG \\
  $FR_NETWORK_FLAG \\
  $FR_SUBNET_FLAG \\
  $PROJECT_FLAG"
else
  # global external
  FR_PORT_FLAG="--ports=$FR_PORTS"
  [[ "$FR_PORTS" == "80"  ]] && FR_PORT_FLAG="--ports=80"
  [[ "$FR_PORTS" == "443" ]] && FR_PORT_FLAG="--ports=443"
  CMD_FR_CREATE="gcloud compute forwarding-rules create \"$POC_FR_NAME\" \\
  --load-balancing-scheme=$FR_SCHEME \\
  --target-$(echo "$PROXY_KIND_EFFECTIVE")-proxy=\"$POC_PROXY_NAME\" \\
  --target-$(echo "$PROXY_KIND_EFFECTIVE")-proxy-region=global \\
  $FR_PORT_FLAG \\
  --ip-protocol=$FR_PROTOCOL \\
  --address=<OPTIONAL_STATIC_IP> \\
  $PROJECT_FLAG"
fi

# Step 7: 描述依赖检查命令
CMD_CHECK_NAMED_PORT="# 确认 MIG 已配置 named port '$BS_NAMED_PORT'
gcloud compute instance-groups set-named-ports \"$FOUND_MIG\" \\
  --named-ports=${BS_NAMED_PORT}:$(echo "$BS_NAMED_PORT" | grep -oP '\d+' | head -1 || echo 80) \\
  --zone=$MIG_ZONE \\
  $PROJECT_FLAG
# （如果已经配置好了就跳过）"

# ─────────────────────────────────────────────
# 阶段五：输出命令
# ─────────────────────────────────────────────
section "阶段五：POC 创建命令"

OUTPUT_CONTENT="$(cat <<CMDBLOCK
#!/usr/bin/env bash
# =============================================================
# POC LB 创建命令 — 自动生成
# 参考 MIG     : $FOUND_MIG
# 参考 BS      : ${BS_NAME:-"(未找到)"}
# 参考 UM      : ${UM_NAME:-"(未找到)"}
# 参考 Proxy   : ${PROXY_NAME:-"(未找到)"}  (kind: $PROXY_KIND_EFFECTIVE)
# LB Scheme    : $BS_SCHEME
# Region       : $REF_REGION
# 生成时间     : $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================
# 使用方法：
#   bash <this-file>              # 执行
#   bash -n <this-file>           # 语法检查
# 注意：请先检查 <OPTIONAL_STATIC_IP>、<YOUR_CERT_NAME> 等占位符
# =============================================================
set -euo pipefail

PROJECT_FLAG="$PROJECT_FLAG"
REGION_FLAG="$REGION_FLAG"

$CMD_SEPARATOR
# STEP 0：前置检查 - Named Port
$CMD_SEPARATOR
echo ">>> STEP 0: 检查 Named Port..."
$CMD_CHECK_NAMED_PORT

$CMD_SEPARATOR
# STEP 1：创建 Health Check
$CMD_SEPARATOR
echo ">>> STEP 1: 创建 Health Check: $POC_HC_NAME"
$CMD_HC_CREATE

$CMD_SEPARATOR
# STEP 2：创建 Backend Service
$CMD_SEPARATOR
echo ">>> STEP 2: 创建 Backend Service: $POC_BS_NAME"
$CMD_BS_CREATE

$CMD_SEPARATOR
# STEP 3：将 MIG 加入 Backend Service
$CMD_SEPARATOR
echo ">>> STEP 3: 添加 MIG 到 Backend Service..."
$CMD_BS_ADD_MIG

$CMD_SEPARATOR
# STEP 4：创建 URL Map
$CMD_SEPARATOR
echo ">>> STEP 4: 创建 URL Map: $POC_UM_NAME"
$CMD_UM_CREATE

$CMD_SEPARATOR
# STEP 5：创建 Target Proxy
$CMD_SEPARATOR
echo ">>> STEP 5: 创建 Target ${PROXY_KIND_EFFECTIVE^^} Proxy: $POC_PROXY_NAME"
$CMD_PROXY_CREATE

$CMD_SEPARATOR
# STEP 6：创建 Forwarding Rule
$CMD_SEPARATOR
echo ">>> STEP 6: 创建 Forwarding Rule: $POC_FR_NAME"
$CMD_FR_CREATE

$CMD_SEPARATOR
# STEP 7：验证
$CMD_SEPARATOR
echo ">>> STEP 7: 验证资源..."
gcloud compute backend-services get-health "$POC_BS_NAME" $BS_SCOPE_FLAG $PROJECT_FLAG || true
gcloud compute forwarding-rules describe "$POC_FR_NAME" $FR_SCOPE_FLAG $PROJECT_FLAG 2>/dev/null | grep -E 'IPAddress|portRange|ports' || true

echo ""
echo "✅  POC LB 资源创建完成！"
echo "   Forwarding Rule IP: \$(gcloud compute forwarding-rules describe $POC_FR_NAME $FR_SCOPE_FLAG $PROJECT_FLAG --format='value(IPAddress)' 2>/dev/null || echo '(请手动查询)')"
CMDBLOCK
)"

# ── 输出到文件或 stdout ──
if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$OUTPUT_CONTENT" > "$OUTPUT_FILE"
  chmod +x "$OUTPUT_FILE"
  success "命令已写入: $OUTPUT_FILE"
  echo ""
  echo "  执行方式:"
  echo "    bash $OUTPUT_FILE"
  echo "    bash -n $OUTPUT_FILE    # 仅语法检查"
else
  echo ""
  echo "$OUTPUT_CONTENT"
fi

# ─────────────────────────────────────────────
# 阶段六：执行模式（--execute）
# ─────────────────────────────────────────────
if [[ "$EXECUTE" == "true" ]]; then
  section "阶段六：执行确认"
  warn "即将执行以上命令，创建以下 POC 资源："
  echo "  HC     : $POC_HC_NAME"
  echo "  BS     : $POC_BS_NAME"
  echo "  UM     : $POC_UM_NAME"
  echo "  Proxy  : $POC_PROXY_NAME"
  echo "  FR     : $POC_FR_NAME"
  echo ""
  read -r -p "确认执行？(输入 yes 继续) : " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    warn "已取消执行"
    exit 0
  fi

  EXEC_FILE="$TMP_DIR/exec.sh"
  echo "$OUTPUT_CONTENT" > "$EXEC_FILE"
  chmod +x "$EXEC_FILE"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] 不实际执行"
    bash -n "$EXEC_FILE" && success "语法检查通过"
  else
    bash "$EXEC_FILE"
  fi
fi

section "完成"
success "脚本执行完毕"
echo ""
echo "  📋 探索结果摘要:"
echo "     MIG              : $FOUND_MIG  (zone: $MIG_ZONE)"
echo "     Backend Service  : ${BS_NAME:-"(未找到)"}"
echo "     URL Map          : ${UM_NAME:-"(未找到)"}"
echo "     Target Proxy     : ${PROXY_NAME:-"(未找到)"}  (${PROXY_KIND_EFFECTIVE})"
echo "     POC 资源前缀     : $BASE"
echo ""
echo "  📌 注意事项:"
echo "     1. Forwarding Rule 的 <OPTIONAL_STATIC_IP> 如不填则自动分配临时 IP"
echo "     2. HTTPS proxy 需提前准备 SSL 证书"
echo "     3. 如 MIG 在 VPC 内，检查 Firewall 是否允许 health check 探测（130.211.0.0/22, 35.191.0.0/16）"
echo "     4. POC 完成后记得清理资源（FR → Proxy → UM → BS → HC 顺序删除）"