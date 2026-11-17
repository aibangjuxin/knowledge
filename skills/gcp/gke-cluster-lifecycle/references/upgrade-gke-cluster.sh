#!/usr/bin/env bash
# =============================================================================
# upgrade-gke-cluster.sh — GKE 集群升级脚本 v1.0
#
# 用途: 执行 GKE 集群 Master 和/或 Node 升级，支持 dry-run 预览
#
# 用法: ./upgrade-gke-cluster.sh [OPTIONS]
#
# 依赖: gcloud, jq (可选)
# =============================================================================

set -euo pipefail

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
error()   { echo -e "${RED}[ERROR]${RESET} $* >&2" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
divider() { echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"; }

PROJECT_ID=""
CLUSTER_NAME=""
LOCATION=""
DRY_RUN=false
AUTO_UPGRADE_NODES=false
SKIP_CONFIRMATION=false
VERBOSE=false

usage() {
cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") [OPTIONS]

${BOLD}描述:${RESET}
  升级 GKE 集群 Master 和/或 Node 版本

${BOLD}Options:${RESET}
  -p, --project   PROJECT_ID    指定 GCP 项目 ID（默认: 当前激活的项目）
  -c, --cluster   CLUSTER_NAME  指定集群名称
  -l, --location  LOCATION      指定区域/可用区（默认: 自动推断）
  -n, --dry-run                  预览模式（不实际执行升级）
  -a, --auto-upgrade-nodes       同时自动升级 Node
  -y, --yes                      跳过确认提示
  -v, --verbose                  详细输出
  -h, --help                     显示此帮助信息

${BOLD}示例:${RESET}
  $(basename "$0") -p my-project -c my-cluster -n        # 预览
  $(basename "$0") -p my-project -c my-cluster -y        # 执行
  $(basename "$0") -p my-project -c my-cluster -a -y     # 同时升级 Node

EOF
exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)   PROJECT_ID="$2";      shift 2 ;;
    -c|--cluster)   CLUSTER_NAME="$2";   shift 2 ;;
    -l|--location)  LOCATION="$2";       shift 2 ;;
    -n|--dry-run)   DRY_RUN=true;        shift   ;;
    -a|--auto-upgrade-nodes) AUTO_UPGRADE_NODES=true; shift ;;
    -y|--yes)       SKIP_CONFIRMATION=true; shift   ;;
    -v|--verbose)   VERBOSE=true;        shift   ;;
    -h|--help)      usage ;;
    *)  error "未知参数: $1"; echo ""; usage ;;
  esac
done

PROJECT_ID="${PROJECT_ID:-${GKE_PROJECT:-}}"
CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER:-}}"
LOCATION="${LOCATION:-${GKE_LOCATION:-}}"

check_dependencies() {
  if ! command -v gcloud &>/dev/null; then
    error "缺少 gcloud"
    exit 1
  fi
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
    error "未登录 gcloud，请先执行: gcloud auth login"
    exit 1
  fi
}

resolve_project() {
  if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
      error "未找到激活的 GCP 项目，请指定 --project"
      exit 1
    fi
  fi
  info "使用项目: ${BOLD}${PROJECT_ID}${RESET}"
}

is_zone() { [[ "$1" =~ ^[a-z]+-[a-z]+\d+-[a-z]$ ]]; }

get_loc_flag() {
  local loc="$1"
  if [[ -z "$loc" ]]; then
    echo "--region=-"
  elif is_zone "$loc"; then
    echo "--zone=$loc"
  else
    echo "--region=$loc"
  fi
}

infer_cluster_location() {
  local cluster="$1"
  gcloud container clusters list \
    --project="$PROJECT_ID" \
    --format="value(name,location)" 2>/dev/null | grep "^${cluster}" | awk '{print $2}'
}

list_clusters() {
  local loc_flag
  loc_flag=$(get_loc_flag "$LOCATION")
  if [[ -n "$CLUSTER_NAME" ]]; then
    echo -e "${CLUSTER_NAME}\t$LOCATION"
  else
    gcloud container clusters list $loc_flag --project="$PROJECT_ID" \
      --format="value(name,location)" 2>/dev/null
  fi
}

get_cluster_info() {
  local cluster="$1"
  local loc="${2:-$(infer_cluster_location "$cluster")}"
  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  gcloud container clusters describe "$cluster" \
    $loc_flag --project="$PROJECT_ID" \
    --format="json(name,location,status,currentMasterVersion,currentNodeVersion,releaseChannel)" \
    2>/dev/null
}

colorize_status() {
  local s="$1"
  case "$s" in
    RUNNING)   echo -e "${GREEN}${s}${RESET}" ;;
    RECONCILING) echo -e "${YELLOW}${s}${RESET}" ;;
    ERROR)     echo -e "${RED}${s}${RESET}" ;;
    STOPPING)  echo -e "${RED}${s}${RESET}" ;;
    *)         echo -e "${DIM}${s}${RESET}" ;;
  esac
}

print_cluster_preview() {
  local cluster="$1"
  local loc="$2"
  local info_json="$3"

  if [[ -z "$info_json" || "$info_json" == "null" ]]; then
    warn "无法获取集群 '$cluster' 的信息"
    return 1
  fi

  local master_ver node_ver location status release_ch
  master_ver=$(echo "$info_json" | jq -r '.currentMasterVersion // "N/A"' 2>/dev/null)
  node_ver=$(echo "$info_json" | jq -r '.currentNodeVersion // "N/A"' 2>/dev/null)
  location=$(echo "$info_json" | jq -r '.location // "N/A"' 2>/dev/null)
  status=$(echo "$info_json" | jq -r '.status // "UNKNOWN"' 2>/dev/null)
  release_ch=$(echo "$info_json" | jq -r '.releaseChannel.channel // "N/A"' 2>/dev/null)

  echo -e "  ${BOLD}集群名称:${RESET}      ${cluster}"
  echo -e "  ${BOLD}位置:${RESET}          ${location}"
  echo -e "  ${BOLD}当前状态:${RESET}      $(colorize_status "$status")"
  echo -e "  ${BOLD}Release Channel:${RESET} ${GREEN}${release_ch}${RESET}"
  echo -e "  ${BOLD}Master 版本:${RESET}   ${YELLOW}${master_ver}${RESET}"
  echo -e "  ${BOLD}Node 版本:${RESET}     ${YELLOW}${node_ver}${RESET}"
  return 0
}

do_upgrade_master() {
  local cluster="$1"
  local loc="$2"
  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  info "正在触发 Master 升级..."
  local out
  if out=$(gcloud container clusters upgrade "$cluster" \
    $loc_flag --project="$PROJECT_ID" --master --quiet 2>&1); then
    success "Master 升级已触发"
    echo -e "  ${DIM}监控: gcloud container operations list $loc_flag --project=$PROJECT_ID${RESET}"
  else
    error "Master 升级失败: $out"
    return 1
  fi
}

do_upgrade_nodes() {
  local cluster="$1"
  local loc="$2"
  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  info "正在触发 Node 升级..."
  local out
  if out=$(gcloud container clusters upgrade "$cluster" \
    $loc_flag --project="$PROJECT_ID" --node-pool=default-pool --quiet 2>&1); then
    success "Node 升级已触发"
  else
    error "Node 升级失败: $out"
    return 1
  fi
}

main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║            GKE 集群升级工具  v1.0                                  ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  [[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}[DRY-RUN]${RESET} 预览模式，不会实际执行升级\n"

  check_dependencies
  resolve_project

  info "获取集群列表..."
  local clusters
  clusters=$(list_clusters)

  if [[ -z "$clusters" ]]; then
    error "项目 '${PROJECT_ID}' 下未找到任何集群"
    exit 1
  fi

  local cluster_count
  cluster_count=$(echo "$clusters" | wc -l | tr -d ' ')

  # 多集群时交互式选择
  if [[ -z "$CLUSTER_NAME" && "$cluster_count" -gt 1 ]]; then
    echo "请选择要升级的集群:"
    local idx=0
    while IFS=$'\t' read -r cn cl; do
      [[ -z "$cn" ]] && continue
      idx=$(( idx + 1 ))
      echo "  [$idx] $cn  ($cl)"
    done <<< "$clusters"
    echo ""
    printf "请输入选项 (1-%d): " "$cluster_count"
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "$cluster_count" ]]; then
      CLUSTER_NAME=$(echo "$clusters" | sed -n "${choice}p" | awk '{print $1}')
    else
      error "无效选择"
      exit 1
    fi
  elif [[ -z "$CLUSTER_NAME" && "$cluster_count" -eq 1 ]]; then
    CLUSTER_NAME=$(echo "$clusters" | awk '{print $1}')
  fi

  if [[ -z "$CLUSTER_NAME" ]]; then
    error "请指定要升级的集群: --cluster <NAME>"
    exit 1
  fi

  local cluster_loc
  cluster_loc="${LOCATION:-$(infer_cluster_location "$CLUSTER_NAME")}"
  if [[ -z "$cluster_loc" ]]; then
    error "无法推断集群位置，请使用 --location 参数指定"
    exit 1
  fi

  header "📋 集群: ${CLUSTER_NAME}"
  echo -e "${DIM}区域: ${cluster_loc}${RESET}"

  local info_json
  info_json=$(get_cluster_info "$CLUSTER_NAME" "$cluster_loc")
  print_cluster_preview "$CLUSTER_NAME" "$cluster_loc" "$info_json"

  # 历史升级记录
  local since_date
  if date --version &>/dev/null 2>&1; then
    since_date=$(date -d "-90 days" -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    since_date=$(date -u -v-90d +"%Y-%m-%dT%H:%M:%SZ")
  fi

  local ops_json
  ops_json=$(gcloud container operations list \
    $(get_loc_flag "$cluster_loc") --project="$PROJECT_ID" \
    --filter="targetLink~clusters/${CLUSTER_NAME} AND (operationType=UPGRADE_MASTER OR operationType=UPGRADE_NODES OR operationType=AUTO_UPGRADE_NODES)" \
    --format="json(name,operationType,status,startTime,detail)" 2>/dev/null || echo "[]")

  if [[ "$ops_json" != "[]" && -n "$ops_json" ]]; then
    local op_count
    op_count=$(echo "$ops_json" | jq 'length' 2>/dev/null || echo "0")
    if [[ "$op_count" -gt 0 ]]; then
      info "历史升级记录（最近 90 天）:"
      echo "$ops_json" | jq -r 'sort_by(.startTime) | reverse[] |
        "  \(.startTime[:19] | gsub("T";" "))  [\(.operationType)]  \(.status)  \(.detail // .statusMessage // "")"
      ' 2>/dev/null
    fi
  fi

  echo ""
  divider
  echo -e "${BOLD}升级计划:${RESET}"
  echo -e "  • Master:     ${CYAN}升级到最新可用版本${RESET}"
  echo -e "  • Node:       $([ "$AUTO_UPGRADE_NODES" == "true" ] && echo "${CYAN}同时升级 Node${RESET}" || echo "${DIM}不升级（--auto-upgrade-nodes 可同时升级）${RESET}")"
  echo -e "  • 区域:       ${cluster_loc}"
  divider
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Dry-run 模式，以上为预览信息"
    exit 0
  fi

  if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
    printf "确认执行升级? (y/N): "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && info "已取消" && exit 0
  fi

  echo ""
  do_upgrade_master "$CLUSTER_NAME" "$cluster_loc"

  if [[ "$AUTO_UPGRADE_NODES" == "true" ]]; then
    echo ""
    do_upgrade_nodes "$CLUSTER_NAME" "$cluster_loc"
  fi

  echo ""
  success "升级操作已触发，请使用 verify-gke-cluster-upgrade.sh 监控进度"
  echo ""
}

main "$@"