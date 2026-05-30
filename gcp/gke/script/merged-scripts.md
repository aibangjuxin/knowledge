# Shell Scripts Collection

Generated on: 2026-05-30 09:09:04
Directory: /Users/lex/git/knowledge/gcp/gke/script

## `gke-upgrade-history.sh`

```bash
#!/usr/bin/env bash
#
# gke-upgrade-history.sh — GKE Cluster Upgrade History Reporter
#
# 用法:
#   ./gke-upgrade-history.sh                          # 自动检测 project + 所有集群
#   ./gke-upgrade-history.sh -p PROJECT               # 指定 project
#   ./gke-upgrade-history.sh -p PROJECT -c CLUSTER    # 指定 project + 单集群
#   ./gke-upgrade-history.sh -p PROJECT -c CLUSTER -l LOCATION
#   ./gke-upgrade-history.sh -d 30                     # 查看最近 30 天（默认 90）
#   ./gke-upgrade-history.sh -f json                  # JSON 输出
#   ./gke-upgrade-history.sh -a                        # 显示所有操作类型（非仅升级）
#
# 环境变量:
#   GKE_PROJECT   GCP 项目 ID
#   GKE_CLUSTER   GKE 集群名称
#   GKE_LOCATION  GKE 区域/可用区
#

set -euo pipefail

# ── 颜色 ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── 默认值 ───────────────────────────────────────────────────────────────────
PROJECT_ID=""
CLUSTER_NAME=""
LOCATION=""
DAYS=90
OUTPUT_FORMAT="table"   # table | json | csv
SHOW_ALL=false
VERBOSE=false
LIMIT=5

# ── 辅助函数 ─────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
divider() { echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"; }

# ── 使用说明 ─────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") [OPTIONS]

${BOLD}描述:${RESET}
  查询 GKE 集群的升级操作历史，展示版本变化记录
  (从 A 版本升级到 B 版本的时间点)

${BOLD}Options:${RESET}
  -p, --project   PROJECT_ID   指定 GCP 项目（默认: 当前激活项目）
  -c, --cluster   CLUSTER_NAME 指定集群名称（默认: 遍历所有集群）
  -l, --location  LOCATION     指定区域/可用区（默认: 所有区域）
  -d, --days      DAYS          查看最近 N 天（默认: 90）
  -n, --limit     N             操作列表条数（默认: 5）
  -a, --all                    显示所有操作类型（非仅升级）
  -f, --format   FORMAT        输出格式: table(默认) | json | csv
  -v, --verbose                详细模式
  -h, --help                   显示此帮助

${BOLD}环境变量:${RESET}
  GKE_PROJECT    GCP 项目 ID
  GKE_CLUSTER    GKE 集群名称
  GKE_LOCATION   GKE 区域/可用区

${BOLD}示例:${RESET}
  $(basename "$0")                                    # 当前项目 + 所有集群
  $(basename "$0") -p my-project                     # 指定项目 + 所有集群
  $(basename "$0") -p my-project -c my-cluster       # 指定项目 + 单集群
  $(basename "$0") -p my-project -c my-cluster -l us-central1
  $(basename "$0") -d 30 -f json                      # 30 天 + JSON 输出

EOF
  exit 0
}

# ── 参数解析 ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)   PROJECT_ID="$2";  shift 2 ;;
    -c|--cluster)   CLUSTER_NAME="$2"; shift 2 ;;
    -l|--location)  LOCATION="$2";    shift 2 ;;
    -d|--days)       DAYS="$2";         shift 2 ;;
    -n|--limit)      LIMIT="$2";        shift 2 ;;
    -a|--all)        SHOW_ALL=true;     shift ;;
    -f|--format)    OUTPUT_FORMAT="$2";shift 2 ;;
    -v|--verbose)    VERBOSE=true;      shift ;;
    -h|--help)       usage ;;
    *)  error "未知参数: $1"; usage ;;
  esac
done

# 环境变量覆盖
PROJECT_ID="${PROJECT_ID:-${GKE_PROJECT:-}}"
CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER:-}}"
LOCATION="${LOCATION:-${GKE_LOCATION:-}}"

# ── 依赖检查 ─────────────────────────────────────────────────────────────────
check_deps() {
  if ! command -v gcloud &>/dev/null; then
    error "缺少 gcloud，请安装 Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    warn "未检测到 jq，将使用内置解析（建议安装: brew install jq）"
    JQ=false
  else
    JQ=true
  fi

  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
    error "未登录 gcloud，请先执行: gcloud auth login"
    exit 1
  fi
}

# ── 解析 project ─────────────────────────────────────────────────────────────
resolve_project() {
  if [[ -n "$PROJECT_ID" ]]; then
    info "使用指定项目: ${BOLD}${PROJECT_ID}${RESET}"
    return
  fi
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    error "未找到激活的 GCP 项目，请通过以下方式指定:"
    error "  1. gcloud config set project <PROJECT_ID>"
    error "  2. 使用 -p 参数或 GKE_PROJECT 环境变量"
    exit 1
  fi
  info "使用当前激活项目: ${BOLD}${PROJECT_ID}${RESET}"
}

# ── 获取集群列表 ─────────────────────────────────────────────────────────────
get_clusters() {
  local loc_flag="--zone=-"
  [[ -n "$LOCATION" ]] && loc_flag="--zone=$LOCATION"

  if [[ -n "$CLUSTER_NAME" ]]; then
    # 验证集群存在
    if ! gcloud container clusters describe "$CLUSTER_NAME" \
        $loc_flag --project="$PROJECT_ID" \
        --format="value(name)" &>/dev/null; then
      error "集群 '$CLUSTER_NAME' 不存在或无权限访问"
      exit 1
    fi
    echo "$CLUSTER_NAME"
  else
    gcloud container clusters list \
      $loc_flag --project="$PROJECT_ID" \
      --format="value(name)" 2>/dev/null
  fi
}

# ── 获取集群当前版本 ─────────────────────────────────────────────────────────
get_cluster_versions() {
  local cluster="$1"
  local loc_flag="--zone=-"
  [[ -n "$LOCATION" ]] && loc_flag="--zone=$LOCATION"

  gcloud container clusters describe "$cluster" \
    $loc_flag --project="$PROJECT_ID" \
    --format="json(currentMasterVersion,currentNodeVersion,location,status)" \
    2>/dev/null
}

# ── 计算时间起点 ─────────────────────────────────────────────────────────────
get_time_filter() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    date -u -v-"${DAYS}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
  else
    # Linux
    date -u -d "-${DAYS} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
  fi
}

# ── 获取操作列表 ─────────────────────────────────────────────────────────────
get_operations() {
  local cluster="$1"
  local since_date="$2"
  local loc_flag="--zone=-"
  [[ -n "$LOCATION" ]] && loc_flag="--zone=$LOCATION"

  # 关键: 使用 targetLink 精确匹配集群
  local filter="targetLink~clusters/${cluster}"
  if [[ "$SHOW_ALL" != "true" ]]; then
    filter="${filter} AND (operationType=UPGRADE_MASTER OR operationType=UPGRADE_NODES OR operationType=AUTO_UPGRADE_NODES OR operationType=UPDATE_CLUSTER)"
  fi

  gcloud container operations list \
    $loc_flag --project="$PROJECT_ID" \
    --filter="$filter" \
    --format="json(name,operationType,status,startTime,endTime,detail,statusMessage,targetLink)" \
    --limit="$LIMIT" 2>/dev/null
}

# ── 时间格式化 ───────────────────────────────────────────────────────────────
format_time() {
  local ts="$1"
  [[ -z "$ts" ]] && echo "N/A" && return
  # 2026-05-16T01:58:55.769Z → 2026-05-16 01:58:55
  echo "${ts:0:10} ${ts:11:8}"
}

# ── 计算耗时 ─────────────────────────────────────────────────────────────────
calc_duration() {
  local start="$1"; local end="$2"
  [[ -z "$start" || -z "$end" ]] && echo "N/A" && return

  local start_e end_e diff
  if [[ "$(uname)" == "Darwin" ]]; then
    start_e=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${start:0:19}Z" +%s 2>/dev/null || echo 0)
    end_e=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${end:0:19}Z" +%s 2>/dev/null || echo 0)
  else
    start_e=$(date -d "${start:0:19}Z" +%s 2>/dev/null || echo 0)
    end_e=$(date -d "${end:0:19}Z" +%s 2>/dev/null || echo 0)
  fi

  diff=$(( end_e - start_e ))
  [[ $diff -lt 0 ]] && echo "N/A" && return
  [[ $diff -lt 60 ]] && echo "${diff}s" && return
  [[ $diff -lt 3600 ]] && echo "$((diff/60))m $((diff%60))s" && return
  echo "$((diff/3600))h $(((diff%3600)/60))m"
}

# ── 状态颜色 ─────────────────────────────────────────────────────────────────
color_status() {
  local s="$1"
  case "$s" in
    DONE)         echo -e "${GREEN}${s}${RESET}" ;;
    RUNNING)      echo -e "${YELLOW}${s}${RESET}" ;;
    ABORTING|FAILED|OPERATION_FAILED) echo -e "${RED}${s}${RESET}" ;;
    *)            echo -e "${DIM}${s}${RESET}" ;;
  esac
}

# ── 操作类型翻译 ─────────────────────────────────────────────────────────────
translate_op() {
  local op="$1"
  case "$op" in
    UPGRADE_MASTER)      echo "Master 升级" ;;
    UPGRADE_NODES)       echo "Node 升级" ;;
    AUTO_UPGRADE_NODES)  echo "自动升级 Node" ;;
    AUTO_REPAIR_NODES)   echo "自动修复 Node" ;;
    UPDATE_CLUSTER)      echo "更新集群" ;;
    CREATE_CLUSTER)      echo "创建集群" ;;
    DELETE_CLUSTER)     echo "删除集群" ;;
    SET_NODE_POOL_SIZE)  echo "调整节点池" ;;
    SET_MASTER_AUTH)     echo "设置认证" ;;
    SET_NETWORK_POLICY)  echo "网络策略" ;;
    SET_LABELS)          echo "设置标签" ;;
    *)                   echo "$op" ;;
  esac
}

# ── 提取版本变化（从 detail/statusMessage）──────────────────────────────────
extract_version_delta() {
  local detail="$1"
  # jq -r 输出 null 字段时会变成字面量 "null" 字符串
  [[ -z "$detail" || "$detail" == "null" || ${#detail} -lt 5 ]] && echo "N/A → N/A" && return

  # 匹配 "1.28.3-gke.100" -> "1.29.1-gke.1589001" 格式
  local versions
  mapfile -t versions < <(echo "$detail" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[+-][a-z0-9.]+' | sort -u)
  if [[ ${#versions[@]} -ge 2 ]]; then
    echo "${versions[0]} → ${versions[-1]}"
  elif [[ ${#versions[@]} -eq 1 ]]; then
    echo "N/A → ${versions[0]}"
  else
    # 没有版本号模式，显示摘要（截断）
    echo "${detail:0:50}${detail:+...}"
  fi
}
# ── 输出: Table ───────────────────────────────────────────────────────────────
print_table() {
  local ops_json="$1"
  [[ "$JQ" != "true" ]] && echo "$ops_json" && return

  echo ""
  echo -e "${BOLD}${MAGENTA}开始时间           操作类型       状态     耗时     版本变化${RESET}"
  echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"

  echo "$ops_json" | jq -r '
    sort_by(.startTime) | reverse[] |
    [
      (.startTime // "" | .[0:19] | gsub("T"; " ")),
      (.operationType // "UNKNOWN"),
      (.status // "UNKNOWN"),
      (.detail | if . == null or . == "" then .statusMessage else . end // ""),
      (.endTime // "")
    ] | @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r start op status detail end; do
    [[ -z "$start" ]] && continue
    local dur ver
    dur=$(calc_duration "$start" "${end}Z")
    ver=$(extract_version_delta "$detail")
    local status_colored
    status_colored=$(color_status "$status")
    printf "%-20s %-18s %-10s %-10s %s\n" \
      "$start" "$(translate_op "$op")" "$status_colored" "$dur" "$ver"
    [[ "$VERBOSE" == "true" && -n "$detail" ]] && \
      echo -e "  ${DIM}详情: ${detail}${RESET}"
  done
  echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"
}

# ── 输出: JSON ────────────────────────────────────────────────────────────────
print_json() {
  local ops_json="$1"
  [[ "$JQ" != "true" ]] && error "需要 jq 来输出 JSON" && return
  echo "$ops_json" | jq '
    sort_by(.startTime) | reverse[] | .[] |
    {
      time: .startTime,
      operation: .operationType,
      status: .status,
      duration: "",
      versionDelta: (.detail | if . == null or . == "" then .statusMessage else . end // ""),
      cluster: "'"$CLUSTER_NAME"'"
    }
  ' 2>/dev/null
}

# ── 输出: CSV ─────────────────────────────────────────────────────────────────
print_csv() {
  local ops_json="$1"
  [[ "$JQ" != "true" ]] && error "需要 jq 来输出 CSV" && return
  echo "cluster,time,operation,status,duration,versionDelta"
  echo "$ops_json" | jq -r --arg c "$CLUSTER_NAME" '
    sort_by(.startTime) | reverse[] | .[] |
    [
      $c,
      (.startTime // "" | .[0:19]),
      (.operationType // ""),
      (.status // ""),
      "",
      (.detail | if . == null or . == "" then .statusMessage else . end // "" | gsub(","; ";"))
    ] | @csv
  ' 2>/dev/null
}

# ── 升级摘要（从 detail 中提取版本变化列表）──────────────────────────────────
print_upgrade_summary() {
  local ops_json="$1"
  [[ "$JQ" != "true" ]] && return

  local count
  count=$(echo "$ops_json" | jq '[.[] | select(
    .operationType == "UPGRADE_MASTER" or
    .operationType == "UPGRADE_NODES" or
    .operationType == "AUTO_UPGRADE_NODES"
  )] | length' 2>/dev/null)

  if [[ "$count" == "0" || "$count" == "null" ]]; then
    info "最近 ${DAYS} 天内未发现升级操作"
    return
  fi

  header "🔍 升级版本变化摘要: ${CLUSTER_NAME}"

  echo "$ops_json" | jq -r '
    [.[] | select(
      .operationType == "UPGRADE_MASTER" or
      .operationType == "UPGRADE_NODES" or
      .operationType == "AUTO_UPGRADE_NODES"
    )] | sort_by(.startTime) | reverse[] |
    "  \(.startTime[0:19] | gsub("T"; " "))  \(.operationType)  \(.status)  \(.detail | if . == null or . == "" then .statusMessage else . end // "(无版本详情)")"
  ' 2>/dev/null | while IFS= read -r line; do
    echo "$line" | sed \
      "s/DONE/${GREEN}DONE${RESET}/g" \
      "s/RUNNING/${YELLOW}RUNNING${RESET}/g" \
      "s/ABORTING/${RED}ABORTING${RESET}/g"
  done
}

# ── 主流程 ───────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║   GKE 集群升级历史查询工具  v2.0                          ║${RESET}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"

  check_deps
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
  info "发现 ${cluster_count} 个集群，开始查询..."

  local since_date
  since_date=$(get_time_filter)
  info "时间范围: ${since_date} ~ $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local idx=0
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    idx=$(( idx + 1 ))
    echo ""
    echo -e "${DIM}[${idx}/${cluster_count}]${RESET}"

    CLUSTER_NAME="$cluster"

    # 获取当前版本
    local ver_json
    ver_json=$(get_cluster_versions "$cluster")

    if [[ "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "csv" ]]; then
      header "📋 集群: ${cluster}"
      if [[ "$JQ" == "true" && -n "$ver_json" ]]; then
        local master_ver node_ver location status
        master_ver=$(echo "$ver_json" | jq -r '.currentMasterVersion' 2>/dev/null)
        node_ver=$(echo "$ver_json" | jq -r '.currentNodeVersion' 2>/dev/null)
        location=$(echo "$ver_json" | jq -r '.location' 2>/dev/null)
        status=$(echo "$ver_json" | jq -r '.status' 2>/dev/null)
        echo -e "  ${BOLD}状态:${RESET}        $(color_status "${status:-UNKNOWN}")"
        echo -e "  ${BOLD}位置:${RESET}        ${location:-N/A}"
        echo -e "  ${BOLD}Master 版本:${RESET} ${GREEN}${master_ver:-N/A}${RESET}"
        echo -e "  ${BOLD}Node 版本:${RESET}   ${GREEN}${node_ver:-N/A}${RESET}"
      fi
    fi

    # 获取操作记录
    local ops_json
    ops_json=$(get_operations "$cluster" "$since_date")

    if [[ -z "$ops_json" || "$ops_json" == "[]" ]]; then
      [[ "$OUTPUT_FORMAT" == "table" ]] && warn "最近 ${DAYS} 天内未找到升级操作记录"
      continue
    fi

    local op_count=0
    [[ "$JQ" == "true" ]] && op_count=$(echo "$ops_json" | jq 'length' 2>/dev/null)
    info "找到 ${op_count} 条操作记录"

    case "$OUTPUT_FORMAT" in
      json)  print_json "$ops_json" ;;
      csv)   [[ $idx -eq 1 ]] && echo "cluster,time,operation,status,duration,versionDelta"
             print_csv "$ops_json" ;;
      table)
        print_upgrade_summary "$ops_json"
        print_table "$ops_json"
        ;;
    esac

  done <<< "$clusters"

  echo ""
  success "完成！项目: ${PROJECT_ID} | 集群数: ${cluster_count} | 范围: 最近 ${DAYS} 天"
}

main "$@"
```

## `verify-gke-cluster-upgrade.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# verify-gke-cluster-upgrade.sh — GKE 集群升级记录验证脚本
#
# 用途: 查询 GKE 集群的升级操作历史，展示版本变化记录
#       (从 A 版本升级到 B 版本的时间点)
#
# 用法: ./verify-gke-cluster-upgrade.sh [OPTIONS]
#
# 依赖: gcloud, jq (可选，用于更好的 JSON 解析)
# =============================================================================

set -euo pipefail

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
PROJECT_ID=""          # 留空则使用当前激活的 project
CLUSTER_NAME=""        # 留空则轮询所有集群
LOCATION=""            # 留空则使用 --location=- (所有 region/zone)
DAYS=90                # 默认查看最近 90 天的操作
SHOW_ALL_OPS=false     # 是否显示所有类型操作（非仅升级）
OUTPUT_FORMAT="table"  # 输出格式: table / json / csv
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
  -v, --verbose                详细模式，显示更多操作信息
  -h, --help                   显示此帮助信息

${BOLD}环境变量:${RESET}
  GKE_PROJECT      GCP 项目 ID
  GKE_CLUSTER      GKE 集群名称
  GKE_LOCATION     GKE 区域/可用区

${BOLD}示例:${RESET}
  # 查看当前激活项目下所有集群的升级记录
  $(basename "$0")

  # 查看指定项目的所有集群升级记录
  $(basename "$0") --project my-project-id

  # 查看指定集群最近 30 天的升级记录
  $(basename "$0") --project my-project --cluster my-cluster --days 30

  # 查看指定区域的集群（Autopilot/Regional cluster）
  $(basename "$0") --project my-project --location us-central1

  # 输出为 CSV 格式
  $(basename "$0") --project my-project --format csv

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

# 支持环境变量覆盖
PROJECT_ID="${PROJECT_ID:-${GKE_PROJECT:-}}"
CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER:-}}"
LOCATION="${LOCATION:-${GKE_LOCATION:-}}"

# --------------------------------------------------------------------------- #
# 前置检查
# --------------------------------------------------------------------------- #
check_dependencies() {
  local missing=()

  if ! command -v gcloud &>/dev/null; then
    missing+=("gcloud")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "缺少必要的依赖工具: ${missing[*]}"
    error "请安装 Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    exit 1
  fi

  # jq 是可选的，没有也能运行
  if ! command -v jq &>/dev/null; then
    warn "未检测到 jq，将使用内置解析（建议安装 jq 以获得更好体验）"
    JQ_AVAILABLE=false
  else
    JQ_AVAILABLE=true
  fi

  # 检查 gcloud 登录状态
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
# 获取集群列表
# --------------------------------------------------------------------------- #
get_clusters() {
  local location_flag=""
  if [[ -n "$LOCATION" ]]; then
    location_flag="--zone=$LOCATION"
  else
    location_flag="--zone=-"  # 所有 zone 和 region
  fi

  if [[ -n "$CLUSTER_NAME" ]]; then
    # 验证指定的集群存在
    if ! gcloud container clusters describe "$CLUSTER_NAME" \
        $location_flag \
        --project="$PROJECT_ID" \
        --format="value(name)" &>/dev/null; then
      error "集群 '$CLUSTER_NAME' 不存在或无权限访问"
      exit 1
    fi
    echo "$CLUSTER_NAME"
  else
    # 列出所有集群
    gcloud container clusters list \
      $location_flag \
      --project="$PROJECT_ID" \
      --format="value(name)" 2>/dev/null
  fi
}

# --------------------------------------------------------------------------- #
# 获取集群当前版本信息
# --------------------------------------------------------------------------- #
get_cluster_current_version() {
  local cluster="$1"
  local location_flag="--zone=-"
  if [[ -n "$LOCATION" ]]; then
    location_flag="--zone=$LOCATION"
  fi

  gcloud container clusters describe "$cluster" \
    $location_flag \
    --project="$PROJECT_ID" \
    --format="value(currentMasterVersion,currentNodeVersion,location,status)" \
    2>/dev/null
}

# --------------------------------------------------------------------------- #
# 计算时间过滤器（最近 N 天）
# --------------------------------------------------------------------------- #
get_time_filter() {
  # 计算 N 天前的 ISO8601 时间戳
  local since_date
  if date --version &>/dev/null 2>&1; then
    # GNU date (Linux)
    since_date=$(date -d "-${DAYS} days" -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    # BSD date (macOS)
    since_date=$(date -u -v-"${DAYS}"d +"%Y-%m-%dT%H:%M:%SZ")
  fi
  echo "$since_date"
}

# --------------------------------------------------------------------------- #
# 获取并解析升级操作记录
# --------------------------------------------------------------------------- #
get_upgrade_operations() {
  local cluster="$1"
  local since_date="$2"

  local location_flag="--zone=-"
  if [[ -n "$LOCATION" ]]; then
    location_flag="--zone=$LOCATION"
  fi

  # 操作类型过滤
  local op_filter="operationType=UPGRADE_MASTER OR operationType=UPGRADE_NODES OR operationType=AUTO_REPAIR_NODES OR operationType=AUTO_UPGRADE_NODES"
  if [[ "$SHOW_ALL_OPS" == "true" ]]; then
    op_filter=""
  fi

  # 构建 filter 字符串
  local filter="targetLink~clusters/${cluster}"
  if [[ -n "$op_filter" ]]; then
    filter="${filter} AND (${op_filter})"
  fi

  # 查询 operations 列表
  # 输出字段: name,operationType,status,startTime,endTime,statusMessage,detail
  gcloud container operations list \
    $location_flag \
    --project="$PROJECT_ID" \
    --filter="$filter" \
    --format="json(name,operationType,status,startTime,endTime,statusMessage,detail,targetLink)" \
    2>/dev/null
}

# --------------------------------------------------------------------------- #
# 从 operation detail 中提取版本信息
# --------------------------------------------------------------------------- #
parse_version_from_detail() {
  local detail="$1"
  # detail 示例: "Master version: \"1.28.3-gke.100\" -> \"1.29.1-gke.1589001\""
  # 或: "Node version: \"1.28.3-gke.100\" -> \"1.29.1-gke.1589001\""
  echo "$detail"
}

# --------------------------------------------------------------------------- #
# 格式化时间
# --------------------------------------------------------------------------- #
format_time() {
  local ts="$1"
  if [[ -z "$ts" ]]; then
    echo "N/A"
    return
  fi
  # 去掉毫秒部分 (如 .000Z -> Z)
  ts=$(echo "$ts" | sed 's/\.[0-9]*Z/Z/')
  echo "$ts"
}

# --------------------------------------------------------------------------- #
# 计算耗时
# --------------------------------------------------------------------------- #
calc_duration() {
  local start="$1"
  local end="$2"

  if [[ -z "$start" || -z "$end" ]]; then
    echo "N/A"
    return
  fi

  local start_epoch end_epoch diff
  # 移除毫秒
  start=$(echo "$start" | sed 's/\.[0-9]*Z/Z/')
  end=$(echo "$end" | sed 's/\.[0-9]*Z/Z/')

  if date --version &>/dev/null 2>&1; then
    start_epoch=$(date -d "$start" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -d "$end" +%s 2>/dev/null || echo "0")
  else
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end" +%s 2>/dev/null || echo "0")
  fi

  diff=$(( end_epoch - start_epoch ))
  if [[ $diff -lt 0 ]]; then
    echo "N/A"
  elif [[ $diff -lt 60 ]]; then
    echo "${diff}s"
  elif [[ $diff -lt 3600 ]]; then
    echo "$(( diff / 60 ))m $(( diff % 60 ))s"
  else
    echo "$(( diff / 3600 ))h $(( (diff % 3600) / 60 ))m"
  fi
}

# --------------------------------------------------------------------------- #
# 打印 table 表头
# --------------------------------------------------------------------------- #
print_table_header() {
  printf "\n${BOLD}${MAGENTA}%-22s %-28s %-12s %-10s %-16s${RESET}\n" \
    "开始时间" "操作类型" "状态" "耗时" "详情/版本变化"
  divider
}

# --------------------------------------------------------------------------- #
# 状态颜色
# --------------------------------------------------------------------------- #
colorize_status() {
  local status="$1"
  case "$status" in
    DONE)        echo -e "${GREEN}${status}${RESET}" ;;
    RUNNING)     echo -e "${YELLOW}${status}${RESET}" ;;
    ABORTING)    echo -e "${RED}${status}${RESET}" ;;
    FAILED|OPER_ATION_FAILED) echo -e "${RED}${status}${RESET}" ;;
    *)           echo -e "${DIM}${status}${RESET}" ;;
  esac
}

# --------------------------------------------------------------------------- #
# 操作类型翻译
# --------------------------------------------------------------------------- #
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
# 处理单个集群的操作记录
# --------------------------------------------------------------------------- #
process_cluster() {
  local cluster="$1"
  local since_date="$2"

  header "📋 集群: ${cluster}"

  # 获取当前版本
  local cluster_info
  cluster_info=$(get_cluster_current_version "$cluster")

  if [[ -n "$cluster_info" ]]; then
    local master_ver node_ver location status
    master_ver=$(echo "$cluster_info" | awk 'NR==1')
    node_ver=$(echo "$cluster_info" | awk 'NR==2')
    location=$(echo "$cluster_info" | awk 'NR==3')
    status=$(echo "$cluster_info" | awk 'NR==4')
    echo -e "  ${BOLD}当前状态:${RESET} $(colorize_status "${status:-UNKNOWN}")"
    echo -e "  ${BOLD}位置:${RESET}     ${location:-N/A}"
    echo -e "  ${BOLD}Master 版本:${RESET} ${GREEN}${master_ver:-N/A}${RESET}"
    echo -e "  ${BOLD}Node 版本:${RESET}   ${GREEN}${node_ver:-N/A}${RESET}"
  fi

  # 获取操作记录
  info "正在查询最近 ${DAYS} 天的操作记录（自 ${since_date}）..."
  local ops_json
  ops_json=$(get_upgrade_operations "$cluster" "$since_date")

  if [[ -z "$ops_json" || "$ops_json" == "[]" ]]; then
    warn "未找到相关操作记录"
    return
  fi

  local op_count=0
  if [[ "$JQ_AVAILABLE" == "true" ]]; then
    op_count=$(echo "$ops_json" | jq 'length' 2>/dev/null || echo "0")
  fi

  info "找到 ${op_count} 条操作记录"

  case "$OUTPUT_FORMAT" in
    json)
      echo "$ops_json"
      ;;
    csv)
      print_csv "$ops_json" "$cluster"
      ;;
    table|*)
      print_table "$ops_json" "$cluster"
      ;;
  esac
}

# --------------------------------------------------------------------------- #
# 以 Table 格式打印操作记录
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

  # 按时间倒序排列操作
  echo "$ops_json" | jq -r '
    sort_by(.startTime) | reverse[] |
    [
      .startTime // "N/A",
      .endTime // "",
      .operationType // "UNKNOWN",
      .status // "UNKNOWN",
      .detail // .statusMessage // ""
    ] | @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r start_time end_time op_type status detail; do

    local formatted_start formatted_end duration op_label status_colored detail_short

    formatted_start=$(format_time "$start_time")
    formatted_end=$(format_time "$end_time")
    duration=$(calc_duration "$start_time" "$end_time")
    op_label=$(translate_op_type "$op_type")
    status_colored=$(colorize_status "$status")

    # 截断 detail，避免过长
    detail_short="${detail:0:60}"
    if [[ ${#detail} -gt 60 ]]; then
      detail_short="${detail_short}..."
    fi

    printf "%-22s %-30s %-22s %-10s %s\n" \
      "$formatted_start" \
      "$op_label" \
      "$status_colored" \
      "$duration" \
      "$detail_short"

    # verbose 模式显示完整 detail
    if [[ "$VERBOSE" == "true" && -n "$detail" ]]; then
      echo -e "  ${DIM}完整详情: ${detail}${RESET}"
    fi
  done

  divider
}

# --------------------------------------------------------------------------- #
# 以 CSV 格式输出
# --------------------------------------------------------------------------- #
print_csv() {
  local ops_json="$1"
  local cluster="$2"

  if [[ "$JQ_AVAILABLE" != "true" ]]; then
    warn "未安装 jq，无法输出 CSV 格式"
    return
  fi

  echo "cluster,operation_type,status,start_time,end_time,duration,detail"
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
# 打印版本升级摘要（从 operation detail 中提取）
# --------------------------------------------------------------------------- #
print_upgrade_summary() {
  local ops_json="$1"
  local cluster="$2"

  if [[ "$JQ_AVAILABLE" != "true" ]]; then
    return
  fi

  header "🔍 升级版本变化摘要: ${cluster}"

  # 提取所有 UPGRADE 类型操作的版本变化
  local upgrades
  upgrades=$(echo "$ops_json" | jq -r '
    [.[] | select(
      .operationType == "UPGRADE_MASTER" or
      .operationType == "UPGRADE_NODES" or
      .operationType == "AUTO_UPGRADE_NODES"
    )] | sort_by(.startTime) | .[] |
    {
      time: .startTime,
      type: .operationType,
      status: .status,
      detail: (.detail // .statusMessage // "")
    }
  ' 2>/dev/null)

  if [[ -z "$upgrades" ]]; then
    info "在查询时间范围内未发现升级操作"
    return
  fi

  echo "$ops_json" | jq -r '
    [.[] | select(
      .operationType == "UPGRADE_MASTER" or
      .operationType == "UPGRADE_NODES" or
      .operationType == "AUTO_UPGRADE_NODES"
    )] | sort_by(.startTime) | .[] |
    "  \(.startTime[:19] | gsub("T";" "))  [\(.operationType)]  \(.status)  \(.detail // .statusMessage // "(无版本详情)")"
  ' 2>/dev/null | while IFS= read -r line; do
    # 高亮 -> 符号（版本变化箭头）
    echo -e "${line}" | sed \
      "s/DONE/${GREEN}DONE${RESET}/g" \
      "s/RUNNING/${YELLOW}RUNNING${RESET}/g" \
      "s/ABORTING/${RED}ABORTING${RESET}/g"
  done
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        GKE 集群升级记录验证工具  v1.0                               ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  check_dependencies
  resolve_project

  # 获取集群列表
  info "获取集群列表..."
  local clusters
  clusters=$(get_clusters)

  if [[ -z "$clusters" ]]; then
    warn "项目 '${PROJECT_ID}' 下未找到任何集群"
    if [[ -n "$CLUSTER_NAME" ]]; then
      warn "指定的集群 '${CLUSTER_NAME}' 不存在或无权访问"
    fi
    exit 0
  fi

  local cluster_count
  cluster_count=$(echo "$clusters" | wc -l | tr -d ' ')
  info "发现 ${cluster_count} 个集群，开始轮询检查..."

  # 计算时间起点
  local since_date
  since_date=$(get_time_filter)
  info "查询时间范围: ${since_date} ~ $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # 如果是 CSV 模式，先输出表头
  if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo ""
    echo "cluster,operation_type,status,start_time,end_time,duration,detail"
  fi

  # 轮询每个集群
  local idx=0
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    idx=$(( idx + 1 ))

    echo ""
    echo -e "${DIM}[${idx}/${cluster_count}]${RESET}"

    # 获取该集群的操作记录
    local ops_json
    ops_json=$(get_upgrade_operations "$cluster" "$since_date")

    if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
      # CSV 模式直接追加输出，不需要 header
      if [[ -n "$ops_json" && "$ops_json" != "[]" ]]; then
        if [[ "$JQ_AVAILABLE" == "true" ]]; then
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
        fi
      fi
    else
      # 获取当前版本
      local cluster_info
      cluster_info=$(get_cluster_current_version "$cluster")

      header "📋 集群: ${cluster}"
      if [[ -n "$cluster_info" ]]; then
        local master_ver node_ver location cl_status
        master_ver=$(echo "$cluster_info" | awk 'NR==1')
        node_ver=$(echo "$cluster_info" | awk 'NR==2')
        location=$(echo "$cluster_info" | awk 'NR==3')
        cl_status=$(echo "$cluster_info" | awk 'NR==4')
        echo -e "  ${BOLD}当前状态:${RESET}    $(colorize_status "${cl_status:-UNKNOWN}")"
        echo -e "  ${BOLD}位置:${RESET}        ${location:-N/A}"
        echo -e "  ${BOLD}Master 版本:${RESET} ${GREEN}${master_ver:-N/A}${RESET}"
        echo -e "  ${BOLD}Node 版本:${RESET}   ${GREEN}${node_ver:-N/A}${RESET}"
      fi

      if [[ -z "$ops_json" || "$ops_json" == "[]" ]]; then
        warn "最近 ${DAYS} 天内未找到相关操作记录"
        continue
      fi

      # 升级摘要（版本变化）
      print_upgrade_summary "$ops_json" "$cluster"

      # 详细操作记录
      header "📜 详细操作记录: ${cluster}"
      print_table_header

      echo "$ops_json" | jq -r '
        sort_by(.startTime) | reverse[] |
        [
          .startTime // "N/A",
          .endTime // "",
          .operationType // "UNKNOWN",
          .status // "UNKNOWN",
          .detail // .statusMessage // ""
        ] | @tsv
      ' 2>/dev/null | while IFS=$'\t' read -r start_time end_time op_type status detail; do
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

        if [[ "$VERBOSE" == "true" && -n "$detail" ]]; then
          echo -e "  ${DIM}详情: ${detail}${RESET}"
        fi
      done
      divider
    fi

  done <<< "$clusters"

  echo ""
  success "验证完成！项目: ${PROJECT_ID} | 集群数: ${cluster_count} | 查询范围: 最近 ${DAYS} 天"
  echo ""
}

main "$@"

```

