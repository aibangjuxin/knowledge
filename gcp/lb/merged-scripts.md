# Shell Scripts Collection

Generated on: 2026-03-25 09:19:25
Directory: /Users/lex/git/knowledge/gcp/lb

## `lb-poc-gen.sh`

```bash
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
# 所有 JSON 中间结果存入临时文件，避免 bash <<< 对大 JSON 截断/损坏
FOUND_MIG_FILE="$TMP_DIR/found_mig.json"
FOUND_BACKEND_FILE="$TMP_DIR/found_backend.json"
FOUND_URL_MAP_FILE="$TMP_DIR/found_url_map.json"
FOUND_PROXY_FILE="$TMP_DIR/found_proxy.json"
FOUND_FR_FILE="$TMP_DIR/found_fr.json"
FOUND_HC_FILE="$TMP_DIR/found_hc.json"
# 初始化为空 JSON 对象
for f in "$FOUND_MIG_FILE" "$FOUND_BACKEND_FILE" "$FOUND_URL_MAP_FILE" "$FOUND_PROXY_FILE" "$FOUND_FR_FILE" "$FOUND_HC_FILE"; do
  echo '{}' > "$f"
done

# ── 2.1 找 MIG ──
echo "$MIGS_JSON" | jq -c '.[]' > "$TMP_DIR/migs.jsonl"
while IFS= read -r mig; do
  echo "$mig" > "$TMP_DIR/_tmp_mig.json"
  mig_name="$(jq -r '.name' < "$TMP_DIR/_tmp_mig.json")"
  [[ "$mig_name" =~ $MIG_PATTERN ]] || continue

  zone_ref="$(jq -r '.zone // empty' < "$TMP_DIR/_tmp_mig.json")"
  region_ref="$(jq -r '.region // empty' < "$TMP_DIR/_tmp_mig.json")"
  zone_name="$(name_from_ref "$zone_ref")"
  region_name="$(name_from_ref "$region_ref")"
  zone_region="${zone_name%-*}"

  [[ -n "$ZONE"   && "$zone_name" != "$ZONE"                                        ]] && continue
  [[ -n "$REGION" && "$REGION" != "$region_name" && "$REGION" != "$zone_region"     ]] && continue

  FOUND_MIG="$mig_name"
  cp "$TMP_DIR/_tmp_mig.json" "$FOUND_MIG_FILE"
  info "找到 MIG: ${BOLD}$mig_name${NC} (zone: $zone_name)"
  break
done < "$TMP_DIR/migs.jsonl"

if [[ -z "$FOUND_MIG" ]]; then
  error "未找到匹配 pattern='$MIG_PATTERN' 的 MIG"
  exit 1
fi

INSTANCE_GROUP="$(jq -r '.instanceGroup // .selfLink' < "$FOUND_MIG_FILE")"

# ── 2.2 找 Backend Service ──
FOUND_BACKEND="false"
echo "$BACKENDS_JSON" | jq -c '.[]' > "$TMP_DIR/backends.jsonl"
while IFS= read -r bs; do
  echo "$bs" > "$TMP_DIR/_tmp_bs.json"
  bs_name="$(jq -r '.name' < "$TMP_DIR/_tmp_bs.json")"
  found="$(jq -r --arg ig "$INSTANCE_GROUP" \
    '.backends // [] | map(select(.group == $ig or (.group | split("/")[-1]) == ($ig | split("/")[-1]))) | length' \
    < "$TMP_DIR/_tmp_bs.json")"
  [[ "$found" -gt 0 ]] || continue

  FOUND_BACKEND="true"
  cp "$TMP_DIR/_tmp_bs.json" "$FOUND_BACKEND_FILE"
  info "找到 Backend Service: ${BOLD}$bs_name${NC} (scheme: $(jq -r '.loadBalancingScheme' < "$TMP_DIR/_tmp_bs.json"))"
  break
done < "$TMP_DIR/backends.jsonl"

if [[ "$FOUND_BACKEND" != "true" ]]; then
  warn "未找到引用该 MIG 的 Backend Service，将只生成 Health Check + Backend Service 命令"
fi

BS_SELF_LINK="$(jq -r '.selfLink // empty' < "$FOUND_BACKEND_FILE")"
BS_NAME="$(jq -r '.name // empty'          < "$FOUND_BACKEND_FILE")"

# ── 2.3 找 Health Check ──
if [[ "$FOUND_BACKEND" == "true" ]]; then
  first_hc_ref="$(jq -r '.healthChecks[0] // empty' < "$FOUND_BACKEND_FILE")"
  first_hc_name="$(name_from_ref "$first_hc_ref")"
  if [[ -n "$first_hc_name" ]]; then
    hc_result="$(echo "$HC_JSON" | jq -c --arg n "$first_hc_name" '.[] | select(.name==$n)' | head -1)"
    if [[ -n "$hc_result" ]]; then
      echo "$hc_result" > "$FOUND_HC_FILE"
      info "找到 Health Check: ${BOLD}$first_hc_name${NC}"
    fi
  fi
fi

# ── 2.4 找 URL Map ──
FOUND_URL_MAP="false"
if [[ "$FOUND_BACKEND" == "true" ]]; then
  while IFS= read -r um; do
    [[ -z "$um" ]] && continue
    echo "$um" > "$TMP_DIR/_tmp_um.json"
    um_name="$(jq -r '.name' < "$TMP_DIR/_tmp_um.json")"
    has_bs="$(jq -r --arg bs_name "$BS_NAME" '
      [
        .defaultService,
        (.pathMatchers[]?.defaultService // empty),
        (.pathMatchers[]?.pathRules[]?.service // empty),
        (.pathMatchers[]?.routeRules[]?.routeAction?.weightedBackendServices[]?.backendService // empty)
      ] | flatten | map(select(. != null) | split("/")[-1]) | any(. == $bs_name)
    ' < "$TMP_DIR/_tmp_um.json")"
    [[ "$has_bs" == "true" ]] || continue
    FOUND_URL_MAP="true"
    cp "$TMP_DIR/_tmp_um.json" "$FOUND_URL_MAP_FILE"
    info "找到 URL Map: ${BOLD}$um_name${NC}"
    break
  done < "$URL_MAPS_DETAIL_FILE"
fi

UM_NAME="$(jq -r '.name // empty' < "$FOUND_URL_MAP_FILE")"
UM_SELF_LINK="$(jq -r '.selfLink // empty' < "$FOUND_URL_MAP_FILE")"

# ── 2.5 找 Target Proxy ──
FOUND_PROXY="false"
if [[ "$FOUND_URL_MAP" == "true" ]]; then
  while IFS= read -r proxy; do
    [[ -z "$proxy" ]] && continue
    echo "$proxy" > "$TMP_DIR/_tmp_proxy.json"
    proxy_um="$(jq -r '.urlMap // empty' < "$TMP_DIR/_tmp_proxy.json")"
    proxy_um_name="$(name_from_ref "$proxy_um")"
    [[ "$proxy_um_name" == "$UM_NAME" || "$proxy_um" == "$UM_SELF_LINK" ]] || continue
    FOUND_PROXY="true"
    cp "$TMP_DIR/_tmp_proxy.json" "$FOUND_PROXY_FILE"
    info "找到 Target Proxy: ${BOLD}$(jq -r '.name' < "$TMP_DIR/_tmp_proxy.json")${NC} (kind: $(jq -r '.proxyKind' < "$TMP_DIR/_tmp_proxy.json"))"
    break
  done < "$PROXIES_FILE"
fi

PROXY_NAME="$(jq -r '.name // empty'     < "$FOUND_PROXY_FILE")"
PROXY_SL="$(jq -r '.selfLink // empty'   < "$FOUND_PROXY_FILE")"
PROXY_KIND="$(jq -r '.proxyKind // empty' < "$FOUND_PROXY_FILE")"

# ── 2.6 找 Forwarding Rule ──
FOUND_FR="false"
if [[ "$FOUND_PROXY" == "true" ]]; then
  echo "$FR_JSON" | jq -c '.[]' > "$TMP_DIR/frs.jsonl"
  while IFS= read -r fr; do
    echo "$fr" > "$TMP_DIR/_tmp_fr.json"
    fr_target="$(jq -r '.target // empty' < "$TMP_DIR/_tmp_fr.json")"
    fr_target_name="$(name_from_ref "$fr_target")"
    [[ "$fr_target_name" == "$PROXY_NAME" || "$fr_target" == "$PROXY_SL" ]] || continue
    FOUND_FR="true"
    cp "$TMP_DIR/_tmp_fr.json" "$FOUND_FR_FILE"
    info "找到 Forwarding Rule: ${BOLD}$(jq -r '.name' < "$TMP_DIR/_tmp_fr.json")${NC}"
    break
  done < "$TMP_DIR/frs.jsonl"
fi

# ─────────────────────────────────────────────
# 阶段三：提取参数，构建 POC 资源名
# ─────────────────────────────────────────────
section "阶段三：提取参数"

MIG_ZONE="$(jq -r '.zone // empty | split("/")[-1]' < "$FOUND_MIG_FILE")"
MIG_REGION_RAW="$(jq -r '.region // empty | split("/")[-1]' < "$FOUND_MIG_FILE")"
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
if [[ "$(jq -r '.name // empty' < "$FOUND_HC_FILE")" != "" ]]; then
  HC_TYPE="$(jq -r '.type // "HTTP"' < "$FOUND_HC_FILE" | tr '[:upper:]' '[:lower:]')"
  # 安全的提取方式：遍历所有可能的 health check 类型
  HC_PORT="$(jq -r '
    .httpHealthCheck.port //
    .httpsHealthCheck.port //
    .tcpHealthCheck.port //
    .grpcHealthCheck.port //
    .port // 80' < "$FOUND_HC_FILE")"
  HC_PATH="$(jq -r '.httpHealthCheck.requestPath // .httpsHealthCheck.requestPath // "/"' < "$FOUND_HC_FILE")"
  HC_INTERVAL="$(jq -r '.checkIntervalSec // 10' < "$FOUND_HC_FILE")"
  HC_TIMEOUT="$(jq -r '.timeoutSec // 5'  < "$FOUND_HC_FILE")"
  HC_HEALTHY="$(jq -r '.healthyThreshold // 2'   < "$FOUND_HC_FILE")"
  HC_UNHEALTHY="$(jq -r '.unhealthyThreshold // 2' < "$FOUND_HC_FILE")"
else
  warn "未找到参考 Health Check，使用默认 HTTP:80/ 参数"
  HC_TYPE="http"; HC_PORT=80; HC_PATH="/"; HC_INTERVAL=10; HC_TIMEOUT=5; HC_HEALTHY=2; HC_UNHEALTHY=2
fi

# ── 提取 Backend Service 参数 ──
if [[ "$FOUND_BACKEND" == "true" ]]; then
  BS_PROTOCOL="$(jq -r '.protocol // "HTTP"' < "$FOUND_BACKEND_FILE")"
  BS_SCHEME="$(jq -r '.loadBalancingScheme // "EXTERNAL"' < "$FOUND_BACKEND_FILE")"
  BS_TIMEOUT="$(jq -r '.timeoutSec // 30' < "$FOUND_BACKEND_FILE")"
  BS_SESSION="$(jq -r '.sessionAffinity // "NONE"' < "$FOUND_BACKEND_FILE")"
  BS_BALANCING="$(jq -r '.backends[0].balancingMode // "UTILIZATION"' < "$FOUND_BACKEND_FILE")"
  BS_NAMED_PORT="$(jq -r '.portName // "http"' < "$FOUND_BACKEND_FILE")"
  BS_REGION_REF="$(jq -r '.region // empty | split("/")[-1]' < "$FOUND_BACKEND_FILE")"
else
  BS_PROTOCOL="HTTP"; BS_SCHEME="EXTERNAL"; BS_TIMEOUT=30; BS_SESSION="NONE"
  BS_BALANCING="UTILIZATION"; BS_NAMED_PORT="http"; BS_REGION_REF=""
fi

# ── 提取 Forwarding Rule 参数 ──
if [[ "$FOUND_FR" == "true" ]]; then
  FR_SCHEME="$(jq -r '.loadBalancingScheme // "EXTERNAL"' < "$FOUND_FR_FILE")"
  FR_PORTS="$(jq -r '
    if (.ports // empty) != null and (.ports | length) > 0
    then (.ports | join(","))
    else (.portRange // "80")
    end' < "$FOUND_FR_FILE")"
  FR_PROTOCOL="$(jq -r '.IPProtocol // "TCP"' < "$FOUND_FR_FILE")"
  FR_REGION_REF="$(jq -r '.region // empty | split("/")[-1]' < "$FOUND_FR_FILE")"
  FR_NETWORK="$(jq -r '.network // empty | split("/")[-1]' < "$FOUND_FR_FILE")"
  FR_SUBNET="$(jq -r '.subnetwork // empty | split("/")[-1]' < "$FOUND_FR_FILE")"
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
  ref_certs="$(jq -r '.sslCertificates // [] | map(split("/")[-1]) | join(",")' < "$FOUND_PROXY_FILE")"
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
```

## `refer-lb-create.sh`

```bash
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

```

## `lb-poc-from-mig.sh`

```bash
#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  lb-poc-from-mig.sh <mig-pattern> [options]

Options:
  --project <project-id>              GCP project id
  --region <region>                   Filter MIG/LB resources by region
  --zone <zone>                       Filter MIGs by zone
  --backend-pattern <regex>           Filter backend service names
  --url-map-pattern <regex>           Filter URL map names
  --forwarding-rule-pattern <regex>   Filter forwarding rule names
  --lb-scheme <scheme>                Filter backend service load balancing scheme
  --include-empty                     Show MIGs even if no related LB resources are found
  --suggest-names                     Print starter names for a POC clone
  -h, --help                          Show this help

Examples:
  lb-poc-from-mig.sh my-mig --project my-project
  lb-poc-from-mig.sh api --project my-project --region us-central1
  lb-poc-from-mig.sh api --project my-project --backend-pattern web --suggest-names

Dependencies:
  - gcloud
  - jq
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

name_from_ref() {
  local ref="${1:-}"
  ref="${ref%/}"
  echo "${ref##*/}"
}

matches_regex() {
  local value="${1:-}"
  local pattern="${2:-}"
  if [[ -z "$pattern" ]]; then
    return 0
  fi
  [[ "$value" =~ $pattern ]]
}

resource_scope() {
  local json="$1"
  local region
  region="$(jq -r '.region // empty' <<<"$json")"
  if [[ -n "$region" ]]; then
    echo "regional:$(name_from_ref "$region")"
  else
    echo "global"
  fi
}

suggest_name() {
  local mig="$1"
  local base
  base="$(echo "$mig" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  base="${base:0:35}"
  base="${base%-}"
  echo "$base"
}

PROJECT=""
REGION=""
ZONE=""
BACKEND_PATTERN=""
URL_MAP_PATTERN=""
FORWARDING_RULE_PATTERN=""
LB_SCHEME=""
INCLUDE_EMPTY="false"
SUGGEST_NAMES="false"
MIG_PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --zone)
      ZONE="$2"
      shift 2
      ;;
    --backend-pattern)
      BACKEND_PATTERN="$2"
      shift 2
      ;;
    --url-map-pattern)
      URL_MAP_PATTERN="$2"
      shift 2
      ;;
    --forwarding-rule-pattern)
      FORWARDING_RULE_PATTERN="$2"
      shift 2
      ;;
    --lb-scheme)
      LB_SCHEME="$2"
      shift 2
      ;;
    --include-empty)
      INCLUDE_EMPTY="true"
      shift
      ;;
    --suggest-names)
      SUGGEST_NAMES="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$MIG_PATTERN" ]]; then
        MIG_PATTERN="$1"
      else
        echo "ERROR: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$MIG_PATTERN" ]]; then
  usage >&2
  exit 1
fi

require_cmd gcloud
require_cmd jq

GCLOUD_BASE=(gcloud)
if [[ -n "$PROJECT" ]]; then
  GCLOUD_BASE+=(--project "$PROJECT")
fi

run_gcloud_json() {
  "${GCLOUD_BASE[@]}" "$@" --format=json
}

MIGS_JSON="$(run_gcloud_json compute instance-groups managed list)"
BACKENDS_JSON="$(run_gcloud_json compute backend-services list)"
URL_MAPS_LIST_JSON="$(run_gcloud_json compute url-maps list)"
FORWARDING_RULES_JSON="$(run_gcloud_json compute forwarding-rules list)"
TARGET_HTTP_PROXIES_JSON="$(run_gcloud_json compute target-http-proxies list)"
TARGET_HTTPS_PROXIES_JSON="$(run_gcloud_json compute target-https-proxies list)"
TARGET_TCP_PROXIES_JSON="$(run_gcloud_json compute target-tcp-proxies list)"
TARGET_SSL_PROXIES_JSON="$(run_gcloud_json compute target-ssl-proxies list)"
TARGET_GRPC_PROXIES_JSON="$(run_gcloud_json compute target-grpc-proxies list 2>/dev/null || echo '[]')"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "$URL_MAPS_LIST_JSON" | jq -c '.[]' > "$TMP_DIR/url_maps_list.jsonl"
>"$TMP_DIR/url_maps_full.jsonl"

while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  name="$(jq -r '.name' <<<"$item")"
  region_ref="$(jq -r '.region // empty' <<<"$item")"
  if [[ -n "$region_ref" ]]; then
    region_name="$(name_from_ref "$region_ref")"
    run_gcloud_json compute url-maps describe "$name" --region "$region_name" | jq -c '.' >> "$TMP_DIR/url_maps_full.jsonl"
  else
    run_gcloud_json compute url-maps describe "$name" | jq -c '.' >> "$TMP_DIR/url_maps_full.jsonl"
  fi
done < "$TMP_DIR/url_maps_list.jsonl"

PROXIES_JSON="$TMP_DIR/proxies.jsonl"
>"$PROXIES_JSON"
echo "$TARGET_HTTP_PROXIES_JSON"  | jq -c '.[] | .proxyKind="http"'  >> "$PROXIES_JSON"
echo "$TARGET_HTTPS_PROXIES_JSON" | jq -c '.[] | .proxyKind="https"' >> "$PROXIES_JSON"
echo "$TARGET_TCP_PROXIES_JSON"   | jq -c '.[] | .proxyKind="tcp"'   >> "$PROXIES_JSON"
echo "$TARGET_SSL_PROXIES_JSON"   | jq -c '.[] | .proxyKind="ssl"'   >> "$PROXIES_JSON"
echo "$TARGET_GRPC_PROXIES_JSON"  | jq -c '.[] | .proxyKind="grpc"'  >> "$PROXIES_JSON"

echo "# Load Balancer Discovery From MIG"
echo
echo "- project: ${PROJECT:-"(gcloud default)"}"
echo "- mig filter: ${MIG_PATTERN}"
[[ -n "$REGION" ]] && echo "- region filter: ${REGION}"
[[ -n "$ZONE" ]] && echo "- zone filter: ${ZONE}"
[[ -n "$LB_SCHEME" ]] && echo "- lb scheme filter: ${LB_SCHEME}"
echo

MATCHED_COUNT=0

echo "$MIGS_JSON" | jq -c '.[]' | while IFS= read -r mig; do
  mig_name="$(jq -r '.name' <<<"$mig")"
  zone_ref="$(jq -r '.zone // empty' <<<"$mig")"
  region_ref="$(jq -r '.region // empty' <<<"$mig")"
  zone_name="$(name_from_ref "$zone_ref")"
  region_name="$(name_from_ref "$region_ref")"
  zone_region="${zone_name%-*}"

  matches_regex "$mig_name" "$MIG_PATTERN" || continue
  [[ -n "$ZONE" && "$zone_name" != "$ZONE" ]] && continue
  if [[ -n "$REGION" && "$REGION" != "$region_name" && "$REGION" != "$zone_region" ]]; then
    continue
  fi

  instance_group="$(jq -r '.instanceGroup // empty' <<<"$mig")"
  named_ports="$(jq -r '.namedPorts // [] | map("\(.name):\(.port)") | join(", ")' <<<"$mig")"

  backend_hits_file="$TMP_DIR/backend_hits_${mig_name}.jsonl"
  >"$backend_hits_file"

  echo "$BACKENDS_JSON" | jq -c '.[]' | while IFS= read -r backend; do
    backend_name="$(jq -r '.name' <<<"$backend")"
    backend_scheme="$(jq -r '.loadBalancingScheme // "UNKNOWN"' <<<"$backend")"
    backend_region_ref="$(jq -r '.region // empty' <<<"$backend")"
    backend_region_name="$(name_from_ref "$backend_region_ref")"

    matches_regex "$backend_name" "$BACKEND_PATTERN" || continue
    [[ -n "$LB_SCHEME" && "$backend_scheme" != "$LB_SCHEME" ]] && continue
    [[ -n "$REGION" && -n "$backend_region_name" && "$backend_region_name" != "$REGION" ]] && continue

    found_group="$(jq -r --arg ig "$instance_group" '.backends // [] | map(select(.group == $ig)) | length' <<<"$backend")"
    [[ "$found_group" -gt 0 ]] || continue

    echo "$backend" >> "$backend_hits_file"
  done

  if [[ ! -s "$backend_hits_file" && "$INCLUDE_EMPTY" != "true" ]]; then
    continue
  fi

  MATCHED_COUNT=$((MATCHED_COUNT + 1))
  echo "## MIG: ${mig_name}"
  echo
  echo "- zone: ${zone_name:-"-"}"
  echo "- region: ${region_name:-"-"}"
  echo "- instanceGroup: $(name_from_ref "$instance_group")"
  echo "- namedPorts: ${named_ports:-"-"}"
  echo

  if [[ ! -s "$backend_hits_file" ]]; then
    echo "_No related backend services found._"
    echo
  else
    while IFS= read -r backend; do
      backend_name="$(jq -r '.name' <<<"$backend")"
      backend_scope="$(resource_scope "$backend")"
      backend_scheme="$(jq -r '.loadBalancingScheme // "UNKNOWN"' <<<"$backend")"
      backend_protocol="$(jq -r '.protocol // "UNKNOWN"' <<<"$backend")"
      health_checks="$(jq -r '.healthChecks // [] | map(split("/")[-1]) | join(", ")' <<<"$backend")"
      session_affinity="$(jq -r '.sessionAffinity // "-"' <<<"$backend")"
      timeout_sec="$(jq -r '.timeoutSec // "-"' <<<"$backend")"

      echo "  - Backend Service: ${backend_name}"
      echo "    scope: ${backend_scope}"
      echo "    scheme: ${backend_scheme}"
      echo "    protocol: ${backend_protocol}"
      echo "    healthChecks: ${health_checks:-"-"}"
      echo "    sessionAffinity: ${session_affinity}"
      echo "    timeoutSec: ${timeout_sec}"

      backend_self_link="$(jq -r '.selfLink // empty' <<<"$backend")"

      while IFS= read -r url_map; do
        [[ -z "$url_map" ]] && continue
        url_map_name="$(jq -r '.name' <<<"$url_map")"
        matches_regex "$url_map_name" "$URL_MAP_PATTERN" || continue

        url_map_has_backend="$(
          jq -r \
            --arg bs "$backend_self_link" \
            --arg bs_name "$backend_name" \
            '
            [
              .defaultService,
              (.pathMatchers[]?.defaultService),
              (.pathMatchers[]?.pathRules[]?.service),
              (.pathMatchers[]?.routeRules[]?.service),
              (.hostRules[]?.pathMatcher)
            ]
            | flatten
            | map(select(. != null))
            | map(tostring)
            | map(split("/")[-1])
            | any(. == $bs_name)
            ' <<<"$url_map"
        )"

        [[ "$url_map_has_backend" == "true" ]] || continue

        echo "    - URL Map: ${url_map_name} ($(resource_scope "$url_map"))"
        default_service="$(jq -r '.defaultService // empty | split("/")[-1]' <<<"$url_map")"
        [[ -n "$default_service" ]] && echo "      defaultService: ${default_service}"

        url_map_self_link="$(jq -r '.selfLink // empty' <<<"$url_map")"

        while IFS= read -r proxy; do
          [[ -z "$proxy" ]] && continue
          proxy_url_map="$(jq -r '.urlMap // empty' <<<"$proxy")"
          [[ -n "$proxy_url_map" ]] || continue
          if [[ "$proxy_url_map" != "$url_map_self_link" && "$(name_from_ref "$proxy_url_map")" != "$url_map_name" ]]; then
            continue
          fi

          proxy_name="$(jq -r '.name' <<<"$proxy")"
          proxy_kind="$(jq -r '.proxyKind' <<<"$proxy")"
          echo "      - Target ${proxy_kind^^} Proxy: ${proxy_name} ($(resource_scope "$proxy"))"
          echo "        urlMap: ${url_map_name}"
          certs="$(jq -r '.sslCertificates // [] | map(split("/")[-1]) | join(", ")' <<<"$proxy")"
          [[ -n "$certs" ]] && echo "        sslCertificates: ${certs}"

          proxy_self_link="$(jq -r '.selfLink // empty' <<<"$proxy")"
          echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
            rule_name="$(jq -r '.name' <<<"$rule")"
            matches_regex "$rule_name" "$FORWARDING_RULE_PATTERN" || continue
            rule_target="$(jq -r '.target // empty' <<<"$rule")"
            [[ -n "$rule_target" ]] || continue
            if [[ "$rule_target" != "$proxy_self_link" && "$(name_from_ref "$rule_target")" != "$proxy_name" ]]; then
              continue
            fi
            rule_scope="$(resource_scope "$rule")"
            rule_scheme="$(jq -r '.loadBalancingScheme // "-"' <<<"$rule")"
            rule_ip="$(jq -r '.IPAddress // "-"' <<<"$rule")"
            rule_ports="$(jq -r 'if (.ports // empty) != empty then (.ports | join(",")) else (.portRange // "-") end' <<<"$rule")"
            echo "        - Forwarding Rule: ${rule_name} (${rule_scope})"
            echo "          scheme: ${rule_scheme}"
            echo "          ip: ${rule_ip}"
            echo "          ports: ${rule_ports}"
            echo "          target: ${proxy_name}"
          done
        done < "$PROXIES_JSON"
      done < "$TMP_DIR/url_maps_full.jsonl"

      echo "$PROXIES_JSON" | while IFS= read -r proxy; do
        [[ -z "$proxy" ]] && continue
        service_ref="$(jq -r '.service // empty' <<<"$proxy")"
        [[ -n "$service_ref" ]] || continue
        if [[ "$service_ref" != "$backend_self_link" && "$(name_from_ref "$service_ref")" != "$backend_name" ]]; then
          continue
        fi

        proxy_name="$(jq -r '.name' <<<"$proxy")"
        proxy_kind="$(jq -r '.proxyKind' <<<"$proxy")"
        echo "    - Direct backend-attached proxy: ${proxy_name} (${proxy_kind^^})"

        proxy_self_link="$(jq -r '.selfLink // empty' <<<"$proxy")"
        echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
          rule_name="$(jq -r '.name' <<<"$rule")"
          matches_regex "$rule_name" "$FORWARDING_RULE_PATTERN" || continue
          rule_target="$(jq -r '.target // empty' <<<"$rule")"
          [[ -n "$rule_target" ]] || continue
          if [[ "$rule_target" != "$proxy_self_link" && "$(name_from_ref "$rule_target")" != "$proxy_name" ]]; then
            continue
          fi
          echo "      - Forwarding Rule: ${rule_name} ($(resource_scope "$rule"))"
        done
      done

      echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
        rule_name="$(jq -r '.name' <<<"$rule")"
        matches_regex "$rule_name" "$FORWARDING_RULE_PATTERN" || continue
        bs_ref="$(jq -r '.backendService // empty' <<<"$rule")"
        [[ -n "$bs_ref" ]] || continue
        if [[ "$bs_ref" != "$backend_self_link" && "$(name_from_ref "$bs_ref")" != "$backend_name" ]]; then
          continue
        fi
        echo "    - Direct backend-attached forwarding rule: ${rule_name} ($(resource_scope "$rule"))"
      done
    done < "$backend_hits_file"
  fi

  if [[ "$SUGGEST_NAMES" == "true" ]]; then
    base="$(suggest_name "$mig_name")"
    echo
    echo "### POC Name Suggestions"
    echo
    echo "- health_check: ${base}-poc-hc"
    echo "- backend_service: ${base}-poc-bs"
    echo "- url_map: ${base}-poc-um"
    echo "- target_proxy: ${base}-poc-proxy"
    echo "- forwarding_rule: ${base}-poc-fr"
  fi
  echo
done

echo "## Notes"
echo
echo "- MIG 只能帮你反推出已绑定它的 backend service 和上游 LB 依赖链。"
echo "- 如果 MIG 还没有被任何 backend service 使用，这个脚本拿不到完整 LB 信息。"
echo "- 如果一个 MIG 被多个 backend service / LB 复用，这个脚本会全部列出来，便于你筛选适合 POC 的那一条。"
echo "- 做 POC 前仍然需要确认依赖是否可共享，例如 health check、named port、firewall、证书、静态 IP、proxy-only subnet。"

```

