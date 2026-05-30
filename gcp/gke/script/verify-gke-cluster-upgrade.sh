#!/usr/bin/env bash
# =============================================================================
# verify-gke-cluster-upgrade.sh — GKE 集群升级记录验证脚本
#
# 用途: 查询 GKE 集群的升级操作历史，展示版本变化记录
#       (从 A 版本升级到 B 版本的时间点)
#
# 用法: ./verify-gke-cluster-upgrade.sh [OPTIONS]
#
# 依赖: gcloud, jq (可选)
# =============================================================================

set -uo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
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
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
divider() { echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"; }

# --------------------------------------------------------------------------- #
# 默认配置
# --------------------------------------------------------------------------- #
PROJECT_ID=""
CLUSTER_NAME=""
LOCATION=""
DAYS=90
SHOW_ALL_OPS=false
OUTPUT_FORMAT="table"
VERBOSE=false

# --------------------------------------------------------------------------- #
# 帮助信息
# --------------------------------------------------------------------------- #
usage() {
cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") [OPTIONS]

${BOLD}描述:${RESET}
  验证 GKE 集群的升级历史记录，展示每个集群在各时间点的版本变化
  (例如: 从 1.28.3-gke.100 升级到 1.29.1-gke.1589001)

${BOLD}Options:${RESET}
  -p, --project   PROJECT_ID   指定 GCP 项目 ID（默认: 当前激活的项目）
  -c, --cluster   CLUSTER_NAME 指定集群名称（默认: 轮询项目下所有集群）
  -l, --location  LOCATION     指定区域/可用区（默认: 所有区域）
  -d, --days      DAYS         查看最近 N 天的记录（默认: 90）
  -a, --all                    显示所有操作类型（非仅升级操作）
  -f, --format    FORMAT       输出格式: table(默认) / json / csv
  -v, --verbose                详细模式
  -h, --help                   显示此帮助信息

${BOLD}示例:${RESET}
  $(basename "$0") --project my-project --cluster my-cluster --days 30
  $(basename "$0") -p my-project -c my-cluster -l us-central1 -d 30 -v

EOF
exit 0
}

# --------------------------------------------------------------------------- #
# 参数解析
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)   PROJECT_ID="$2";     shift 2 ;;
    -c|--cluster)   CLUSTER_NAME="$2";   shift 2 ;;
    -l|--location)  LOCATION="$2";       shift 2 ;;
    -d|--days)      DAYS="$2";           shift 2 ;;
    -a|--all)       SHOW_ALL_OPS=true;   shift   ;;
    -f|--format)    OUTPUT_FORMAT="$2";  shift 2 ;;
    -v|--verbose)   VERBOSE=true;        shift   ;;
    -h|--help)      usage ;;
    *)  error "未知参数: $1"; echo ""; usage ;;
  esac
done

PROJECT_ID="${PROJECT_ID:-${GKE_PROJECT:-}}"
CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER:-}}"
LOCATION="${LOCATION:-${GKE_LOCATION:-}}"

# --------------------------------------------------------------------------- #
# 前置检查
# --------------------------------------------------------------------------- #
check_dependencies() {
  if ! command -v gcloud &>/dev/null; then
    error "缺少必要的依赖工具: gcloud"
    exit 1
  fi

  if command -v jq &>/dev/null; then
    JQ_AVAILABLE=true
  else
    warn "未检测到 jq，将使用内置解析（建议安装 jq 以获得更好体验）"
    JQ_AVAILABLE=false
  fi

  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
    error "未登录 gcloud，请先执行: gcloud auth login"
    exit 1
  fi
}

# --------------------------------------------------------------------------- #
# 获取 Project ID
# --------------------------------------------------------------------------- #
resolve_project() {
  if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
      error "未找到激活的 GCP 项目，请通过以下方式之一指定:"
      error "  1. gcloud config set project <PROJECT_ID>"
      error "  2. 使用 --project 参数"
      exit 1
    fi
    info "使用当前激活项目: ${BOLD}${PROJECT_ID}${RESET}"
  else
    info "使用指定项目: ${BOLD}${PROJECT_ID}${RESET}"
  fi
}

# --------------------------------------------------------------------------- #
# 判断 loc 是 zone 还是 region
# --------------------------------------------------------------------------- #
is_zone() {
  [[ "$1" =~ ^[a-z]+-[a-z]+\d+-[a-z]$ ]]
}

# --------------------------------------------------------------------------- #
# 构建 gcloud location flag
# --------------------------------------------------------------------------- #
resolve_loc_flag() {
  local loc="${1:-}"
  if [[ -z "$loc" ]]; then
    echo "--region=-"
  elif is_zone "$loc"; then
    echo "--zone=$loc"
  else
    echo "--region=$loc"
  fi
}

# --------------------------------------------------------------------------- #
# 从集群名推断其 location（从集群列表中查找）
# --------------------------------------------------------------------------- #
infer_cluster_location() {
  local cluster="$1"
  local line
  line=$(gcloud container clusters list \
    --project="$PROJECT_ID" \
    --format="value(name,location)" 2>/dev/null | grep "^${cluster}" || true)
  echo "$line" | awk '{print $2}'
}

# --------------------------------------------------------------------------- #
# 获取集群列表（返回 "name<tab>location" 两列）
# --------------------------------------------------------------------------- #
get_clusters() {
  local loc_flag
  loc_flag=$(resolve_loc_flag "$LOCATION")

  if [[ -n "$CLUSTER_NAME" ]]; then
    local loc_flag
    loc_flag=$(resolve_loc_flag "$(infer_cluster_location "$CLUSTER_NAME")")
    if ! gcloud container clusters describe "$CLUSTER_NAME" \
        $loc_flag --project="$PROJECT_ID" --format="value(name)" &>/dev/null; then
      error "集群 '$CLUSTER_NAME' 不存在或无权限访问"
      exit 1
    fi
    echo -e "${CLUSTER_NAME}\t$(infer_cluster_location "$CLUSTER_NAME")"
  else
    gcloud container clusters list $loc_flag --project="$PROJECT_ID" \
      --format="value(name,location)" 2>/dev/null
  fi
}

# --------------------------------------------------------------------------- #
# 获取集群当前信息（JSON）
# --------------------------------------------------------------------------- #
get_cluster_info() {
  local cluster="$1"
  local loc="$2"
  local loc_flag
  loc_flag=$(resolve_loc_flag "$loc")

  gcloud container clusters describe "$cluster" \
    $loc_flag --project="$PROJECT_ID" \
    --format="json(currentMasterVersion,currentNodeVersion,location,status,releaseChannel)" \
    2>/dev/null
}

# --------------------------------------------------------------------------- #
# 计算时间过滤器
# --------------------------------------------------------------------------- #
get_time_filter() {
  if date --version &>/dev/null 2>&1; then
    date -d "-${DAYS} days" -u +"%Y-%m-%dT%H:%M:%SZ"
  else
    date -u -v-"${DAYS}"d +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

# --------------------------------------------------------------------------- #
# 获取操作记录
# --------------------------------------------------------------------------- #
get_operations() {
  local cluster="$1"
  local loc="$2"
  local loc_flag
  loc_flag=$(resolve_loc_flag "$loc")

  local op_filter=""
  if [[ "$SHOW_ALL_OPS" != "true" ]]; then
    op_filter="operationType=UPGRADE_MASTER OR operationType=UPGRADE_NODES OR operationType=AUTO_UPGRADE_NODES OR operationType=AUTO_REPAIR_NODES"
  fi

  local filter="targetLink~clusters/${cluster}"
  if [[ -n "$op_filter" ]]; then
    filter="${filter} AND (${op_filter})"
  fi

  gcloud container operations list \
    $loc_flag --project="$PROJECT_ID" \
    --filter="$filter" \
    --format="json(name,operationType,status,startTime,endTime,statusMessage,detail,targetLink)" \
    2>/dev/null
}

# --------------------------------------------------------------------------- #
# 辅助函数
# --------------------------------------------------------------------------- #
format_time() {
  local ts="${1:-}"
  [[ -z "$ts" ]] && echo "N/A" && return
  echo "$ts" | sed 's/\.[0-9]*Z/Z/'
}

calc_duration() {
  local start="${1:-}" end="${2:-}"
  [[ -z "$start" || -z "$end" ]] && echo "N/A" && return

  start=$(echo "$start" | sed 's/\.[0-9]*Z/Z/')
  end=$(echo "$end" | sed 's/\.[0-9]*Z/Z/')

  local start_epoch end_epoch diff
  if date --version &>/dev/null 2>&1; then
    start_epoch=$(date -d "$start" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -d "$end" +%s 2>/dev/null || echo "0")
  else
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end" +%s 2>/dev/null || echo "0")
  fi

  diff=$(( end_epoch - start_epoch ))
  [[ $diff -lt 0 ]] && echo "N/A" && return
  [[ $diff -lt 60 ]] && echo "${diff}s" && return
  [[ $diff -lt 3600 ]] && echo "$(( diff / 60 ))m $(( diff % 60 ))s" && return
  echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m"
}

colorize_status() {
  local status="$1"
  case "$status" in
    DONE)                       echo -e "${GREEN}${status}${RESET}" ;;
    RUNNING)                     echo -e "${YELLOW}${status}${RESET}" ;;
    ABORTING)                    echo -e "${RED}${status}${RESET}" ;;
    FAILED|OPERATION_FAILED)     echo -e "${RED}${status}${RESET}" ;;
    *)                           echo -e "${DIM}${status}${RESET}" ;;
  esac
}

translate_op_type() {
  local op="$1"
  case "$op" in
    UPGRADE_MASTER)        echo "🔧 Master 升级" ;;
    UPGRADE_NODES)         echo "🔧 Node 升级" ;;
    AUTO_UPGRADE_NODES)    echo "🤖 自动升级 Node" ;;
    AUTO_REPAIR_NODES)     echo "🛠  自动修复 Node" ;;
    CREATE_CLUSTER)        echo "🆕 创建集群" ;;
    DELETE_CLUSTER)        echo "🗑  删除集群" ;;
    UPDATE_CLUSTER)        echo "✏️  更新集群" ;;
    SET_MASTER_AUTH)       echo "🔑 设置 Master 认证" ;;
    SET_NODE_POOL_SIZE)    echo "📏 调整节点池大小" ;;
    SET_NETWORK_POLICY)    echo "🔒 设置网络策略" ;;
    SET_LABELS)            echo "🏷  设置标签" ;;
    *)                     echo "$op" ;;
  esac
}

# --------------------------------------------------------------------------- #
# 打印升级摘要
# --------------------------------------------------------------------------- #
print_upgrade_summary() {
  local ops_json="$1"
  local cluster="$2"

  header "🔍 升级版本变化摘要: ${cluster}"

  if [[ "$JQ_AVAILABLE" != "true" ]]; then
    warn "需要 jq 来提取版本变化摘要"
    return
  fi

  local summary
  summary=$(echo "$ops_json" | jq -r '
    [.[] | select(
      .operationType == "UPGRADE_MASTER" or
      .operationType == "UPGRADE_NODES" or
      .operationType == "AUTO_UPGRADE_NODES"
    )] | sort_by(.startTime) | .[] |
    "  \(.startTime[:19] | gsub("T";" "))  [\(.operationType)]  \(.status)  \(.detail // .statusMessage // "(无版本详情)")"
  ' 2>/dev/null || true)

  if [[ -z "$summary" ]]; then
    info "在查询时间范围内未发现升级操作"
    return
  fi

  echo "$summary" | sed \
    -e 's|DONE|\x1b[0;32mDONE\x1b[0m|g' \
    -e 's|RUNNING|\x1b[1;33mRUNNING\x1b[0m|g' \
    -e 's|ABORTING|\x1b[0;31mABORTING\x1b[0m|g' \
    -e 's|FAILED|\x1b[0;31mFAILED\x1b[0m|g'
}

# --------------------------------------------------------------------------- #
# 打印表头
# --------------------------------------------------------------------------- #
print_table_header() {
  printf "\n${BOLD}${MAGENTA}%-22s %-28s %-12s %-10s %-16s${RESET}\n" \
    "开始时间" "操作类型" "状态" "耗时" "详情/版本变化"
  divider
}

# --------------------------------------------------------------------------- #
# 打印详细操作记录（table 格式）
# --------------------------------------------------------------------------- #
print_table() {
  local ops_json="$1"
  local cluster="$2"

  if [[ "$JQ_AVAILABLE" != "true" ]]; then
    warn "未安装 jq，显示原始 JSON 数据"
    echo "$ops_json"
    return
  fi

  print_table_header

  # 读取所有行为数组，每行: startTime<tab>endTime<tab>operationType<tab>status<tab>detail
  local line
  echo "$ops_json" | jq -r '
    sort_by(.startTime) | reverse[] |
    [.startTime, .endTime, .operationType, .status, (.detail // .statusMessage // "")] |
    @tsv
  ' 2>/dev/null | tr -d '\r' | while IFS=$'\t' read -r start_time end_time op_type status detail; do
    [[ -z "$start_time" ]] && continue

    local formatted_start duration op_label status_colored detail_short
    formatted_start=$(format_time "$start_time")
    duration=$(calc_duration "$start_time" "$end_time")
    op_label=$(translate_op_type "$op_type")
    status_colored=$(colorize_status "$status")
    detail_short="${detail:0:60}"
    [[ ${#detail} -gt 60 ]] && detail_short="${detail_short}..."

    printf "%-22s %-30s %-22s %-10s %s\n" \
      "$formatted_start" \
      "$op_label" \
      "$status_colored" \
      "$duration" \
      "$detail_short"

    [[ "$VERBOSE" == "true" && -n "$detail" ]] && \
      echo -e "  ${DIM}详情: ${detail}${RESET}"
  done

  divider
}

# --------------------------------------------------------------------------- #
# 打印 CSV 格式
# --------------------------------------------------------------------------- #
print_csv() {
  local ops_json="$1"
  local cluster="$2"

  if [[ "$JQ_AVAILABLE" != "true" ]]; then
    warn "需要 jq 来输出 CSV"
    return
  fi

  echo "$ops_json" | jq -r --arg cluster "$cluster" '
    sort_by(.startTime) | reverse[] |
    [
      $cluster,
      (.operationType // "UNKNOWN"),
      (.status // "UNKNOWN"),
      (.startTime // ""),
      (.endTime // ""),
      "",
      (.detail // .statusMessage // "" | gsub(","; ";"))
    ] | @csv
  ' 2>/dev/null
}

# --------------------------------------------------------------------------- #
# 处理单个集群
# --------------------------------------------------------------------------- #
process_cluster() {
  local cluster="$1"
  local loc="$2"
  local since_date="$3"

  header "📋 集群: ${cluster}"

  local info_json
  info_json=$(get_cluster_info "$cluster" "$loc")

  if [[ -n "$info_json" && "$info_json" != "null" ]]; then
    local master_ver node_ver location status release_ch
    master_ver=$(echo "$info_json" | jq -r '.currentMasterVersion // "N/A"' 2>/dev/null)
    node_ver=$(echo "$info_json" | jq -r '.currentNodeVersion // "N/A"' 2>/dev/null)
    location=$(echo "$info_json" | jq -r '.location // "N/A"' 2>/dev/null)
    status=$(echo "$info_json" | jq -r '.status // "UNKNOWN"' 2>/dev/null)
    release_ch=$(echo "$info_json" | jq -r '.releaseChannel.channel // "N/A"' 2>/dev/null)

    echo -e "  ${BOLD}当前状态:${RESET}      $(colorize_status "${status}")"
    echo -e "  ${BOLD}位置:${RESET}          ${location}"
    echo -e "  ${BOLD}Release Channel:${RESET} ${GREEN}${release_ch}${RESET}"
    echo -e "  ${BOLD}Master 版本:${RESET}   ${GREEN}${master_ver}${RESET}"
    echo -e "  ${BOLD}Node 版本:${RESET}     ${GREEN}${node_ver}${RESET}"
  fi

  info "正在查询最近 ${DAYS} 天的操作记录（自 ${since_date}）..."
  local ops_json
  ops_json=$(get_operations "$cluster" "$loc" "$since_date")

  if [[ -z "$ops_json" || "$ops_json" == "[]" || "$ops_json" == "null" ]]; then
    warn "未找到相关操作记录"
    return
  fi

  local op_count=0
  [[ "$JQ_AVAILABLE" == "true" ]] && op_count=$(echo "$ops_json" | jq 'length' 2>/dev/null)
  info "找到 ${op_count} 条操作记录"

  case "$OUTPUT_FORMAT" in
    json) echo "$ops_json" ;;
    csv)  print_csv "$ops_json" "$cluster" ;;
    *)   print_upgrade_summary "$ops_json" "$cluster"
         header "📜 详细操作记录: ${cluster}"
         print_table "$ops_json" "$cluster" ;;
  esac
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        GKE 集群升级记录验证工具  v2.1                               ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  check_dependencies
  resolve_project

  info "获取集群列表..."
  local clusters
  clusters=$(get_clusters)

  if [[ -z "$clusters" ]]; then
    warn "项目 '${PROJECT_ID}' 下未找到任何集群"
    [[ -n "$CLUSTER_NAME" ]] && warn "指定的集群 '${CLUSTER_NAME}' 不存在或无权访问"
    exit 0
  fi

  local cluster_count
  cluster_count=$(echo "$clusters" | wc -l | tr -d ' ')
  info "发现 ${cluster_count} 个集群，开始轮询检查..."

  local since_date
  since_date=$(get_time_filter)
  info "查询时间范围: ${since_date} ~ $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "cluster,operation_type,status,start_time,end_time,duration,detail"
  fi

  local idx=0
  while IFS=$'\t' read -r cluster loc; do
    [[ -z "$cluster" ]] && continue
    idx=$(( idx + 1 ))
    echo ""
    echo -e "${DIM}[${idx}/${cluster_count}]${RESET}"

    local since_date
    since_date=$(get_time_filter)

    if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
      local ops_json
      ops_json=$(get_operations "$cluster" "$loc" "$since_date")
      [[ -n "$ops_json" && "$ops_json" != "[]" && "$ops_json" != "null" ]] && \
        [[ "$JQ_AVAILABLE" == "true" ]] && print_csv "$ops_json" "$cluster"
    else
      process_cluster "$cluster" "$loc" "$since_date"
    fi
  done <<< "$clusters"

  echo ""
  success "验证完成！项目: ${PROJECT_ID} | 集群数: ${cluster_count} | 查询范围: 最近 ${DAYS} 天"
  echo ""
}

main "$@"