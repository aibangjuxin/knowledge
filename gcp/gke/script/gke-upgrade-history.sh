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