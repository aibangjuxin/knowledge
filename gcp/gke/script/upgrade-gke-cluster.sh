#!/usr/bin/env bash
# =============================================================================
# upgrade-gke-cluster.sh — GKE 集群升级脚本
#
# 用途: 升级 GKE 集群 Master 和/或 Node 版本，支持 dry-run 预览
#
# 用法: ./upgrade-gke-cluster.sh [OPTIONS]
#
# 依赖: gcloud, jq (可选)
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
error()   { echo -e "${RED}[ERROR]${RESET} $* >&2" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
divider() { echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"; }

# --------------------------------------------------------------------------- #
# 默认配置
# --------------------------------------------------------------------------- #
PROJECT_ID=""
CLUSTER_NAME=""
LOCATION=""
DRY_RUN=false
AUTO_UPGRADE_NODES=false
VERBOSE=false
SKIP_CONFIRMATION=false

# --------------------------------------------------------------------------- #
# 帮助信息
# --------------------------------------------------------------------------- #
usage() {
cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") [OPTIONS]

${BOLD}描述:${RESET}
  升级 GKE 集群 Master 和/或 Node 版本
  不指定 --cluster 时将交互式列出所有集群供选择

${BOLD}Options:${RESET}
  -p, --project   PROJECT_ID    指定 GCP 项目 ID（默认: 当前激活的项目）
  -c, --cluster   CLUSTER_NAME  指定集群名称
  -l, --location  LOCATION      指定区域/可用区（默认: 自动推断）
  -n, --dry-run                  预览模式（不实际执行升级）
  -a, --auto-upgrade-nodes       同时自动升级 Node（等同于 gcloud 官方行为）
  -y, --yes                      跳过确认提示
  -v, --verbose                  详细输出
  -h, --help                     显示此帮助信息

${BOLD}示例:${RESET}
  # 预览集群升级路径
  $(basename "$0") -p my-project -c my-cluster -n

  # 执行升级（跳过确认）
  $(basename "$0") -p my-project -c my-cluster -y

  # 查看当前项目所有集群状态
  $(basename "$0") -p my-project

EOF
exit 0
}

# --------------------------------------------------------------------------- #
# 参数解析
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)   PROJECT_ID="$2";      shift 2 ;;
    -c|--cluster)   CLUSTER_NAME="$2";    shift 2 ;;
    -l|--location)  LOCATION="$2";       shift 2 ;;
    -n|--dry-run)   DRY_RUN=true;         shift   ;;
    -a|--auto-upgrade-nodes) AUTO_UPGRADE_NODES=true; shift ;;
    -y|--yes)       SKIP_CONFIRMATION=true; shift   ;;
    -v|--verbose)   VERBOSE=true;         shift   ;;
    -h|--help)      usage ;;
    *)  error "未知参数: $1"; echo ""; usage ;;
  esac
done

PROJECT_ID="${PROJECT_ID:-${GKE_PROJECT:-}}"
CLUSTER_NAME="${CLUSTER_NAME:-${GKE_CLUSTER:-}}"
LOCATION="${LOCATION:-${GKE_LOCATION:-}}"

# --------------------------------------------------------------------------- #
# 依赖检查
# --------------------------------------------------------------------------- #
check_dependencies() {
  if ! command -v gcloud &>/dev/null; then
    error "缺少 gcloud，请安装 Google Cloud SDK"
    exit 1
  fi
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
    error "未登录 gcloud，请先执行: gcloud auth login"
    exit 1
  fi
}

# --------------------------------------------------------------------------- #
# 获取 Project
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
# 判断 location 类型
# --------------------------------------------------------------------------- #
is_zone() {
  local loc="$1"
  [[ "$loc" =~ ^[a-z]+-[a-z]+\d+-[a-z]$ ]]
}

# --------------------------------------------------------------------------- #
# 获取 location flag
# --------------------------------------------------------------------------- #
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

# --------------------------------------------------------------------------- #
# 推断集群的 location
# --------------------------------------------------------------------------- #
infer_cluster_location() {
  local cluster="$1"
  local line
  line=$(gcloud container clusters list \
    --project="$PROJECT_ID" \
    --format="value(name,location)" 2>/dev/null | grep "^${cluster}\t" || true)
  if [[ -n "$line" ]]; then
    echo "$line" | awk '{print $2}'
  fi
}

# --------------------------------------------------------------------------- #
# 获取集群信息
# --------------------------------------------------------------------------- #
get_cluster_info() {
  local cluster="$1"
  local loc="${2:-$(infer_cluster_location "$cluster")}"
  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  gcloud container clusters describe "$cluster" \
    $loc_flag \
    --project="$PROJECT_ID" \
    --format="json(name,location,status,currentMasterVersion,currentNodeVersion,releaseChannel,nodePoolConfigs)" \
    2>/dev/null
}

# --------------------------------------------------------------------------- #
# 获取升级建议
# --------------------------------------------------------------------------- #
get_upgrade_guide() {
  local cluster="$1"
  local loc="$2"

  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  gcloud container clusters describe "$cluster" \
    $loc_flag \
    --project="$PROJECT_ID" \
    --format="json(name,location,status,currentMasterVersion,currentNodeVersion,releaseChannel,nodePools)" \
    2>/dev/null
}

# --------------------------------------------------------------------------- #
# 获取集群列表
# --------------------------------------------------------------------------- #
list_clusters() {
  local loc_flag
  loc_flag=$(get_loc_flag "$LOCATION")

  if [[ -n "$CLUSTER_NAME" ]]; then
    echo -e "${CLUSTER_NAME}\t$LOCATION"
  else
    gcloud container clusters list \
      $loc_flag \
      --project="$PROJECT_ID" \
      --format="value(name,location)" 2>/dev/null
  fi
}

# --------------------------------------------------------------------------- #
# 打印状态颜色
# --------------------------------------------------------------------------- #
colorize_status() {
  local status="$1"
  case "$status" in
    RUNNING)         echo -e "${GREEN}${status}${RESET}" ;;
    RECONCILING)     echo -e "${YELLOW}${status}${RESET}" ;;
    ERROR)           echo -e "${RED}${status}${RESET}" ;;
    STOPPING)        echo -e "${RED}${status}${RESET}" ;;
    *)               echo -e "${DIM}${status}${RESET}" ;;
  esac
}

# --------------------------------------------------------------------------- #
# 打印集群当前信息预览
# --------------------------------------------------------------------------- #
print_cluster_preview() {
  local cluster="$1"
  local loc="$2"
  local info_json="$3"

  if [[ -z "$info_json" || "$info_json" == "null" ]]; then
    warn "无法获取集群 '$cluster' 的信息，跳过"
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
  echo -e "  ${BOLD}推荐升级版本:${RESET}   ${GREEN}${recommended_master:-N/A}${RESET}"

  return 0
}

# --------------------------------------------------------------------------- #
# 执行升级
# --------------------------------------------------------------------------- #
do_upgrade_master() {
  local cluster="$1"
  local loc="$2"
  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  info "正在升级 Master..."

  local op_result
  op_result=$(gcloud container clusters upgrade "$cluster" \
    $loc_flag \
    --project="$PROJECT_ID" \
    --master \
    --quiet \
    2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    success "Master 升级已启动"
    echo -e "  ${DIM}查看进度: gcloud container operations list $loc_flag --project=$PROJECT_ID${RESET}"
  else
    error "Master 升级失败: $op_result"
    return 1
  fi
}

do_upgrade_nodes() {
  local cluster="$1"
  local loc="$2"
  local loc_flag
  loc_flag=$(get_loc_flag "$loc")

  info "正在升级 Node..."

  local op_result
  op_result=$(gcloud container clusters upgrade "$cluster" \
    $loc_flag \
    --project="$PROJECT_ID" \
    --node-pool=default-pool \
    --quiet \
    2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    success "Node 升级已启动"
  else
    error "Node 升级失败: $op_result"
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║            GKE 集群升级工具  v1.0                                  ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} 预览模式，不会实际执行升级"
    echo ""
  fi

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
  info "发现 ${cluster_count} 个集群"

  # 如果未指定集群，交互式选择
  if [[ -z "$CLUSTER_NAME" && "$cluster_count" -gt 1 ]]; then
    echo ""
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
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "$cluster_count" ]]; then
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

  # 获取该集群的 location
  local cluster_loc="${LOCATION:-$(infer_cluster_location "$CLUSTER_NAME")}"
  if [[ -z "$cluster_loc" ]]; then
    error "无法推断集群 '$CLUSTER_NAME' 的区域，请使用 --location 参数指定"
    exit 1
  fi

  header "📋 集群: ${CLUSTER_NAME}"
  echo -e "${DIM}区域: ${cluster_loc}${RESET}"

  # 获取集群信息
  local info_json
  info_json=$(get_cluster_info "$CLUSTER_NAME" "$cluster_loc")

  print_cluster_preview "$CLUSTER_NAME" "$cluster_loc" "$info_json"

  # 获取推荐升级版本
  info "正在获取推荐升级版本..."
  local recommended_master=""
  recommended_master=$(gcloud container clusters describe "$CLUSTER_NAME" \
    $(get_loc_flag "$cluster_loc") \
    --project="$PROJECT_ID" \
    --format="value(currentMasterVersion)" 2>/dev/null)

  # 查询升级操作记录（历史）
  local since_date
  if date --version &>/dev/null 2>&1; then
    since_date=$(date -d "-90 days" -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    since_date=$(date -u -v-90d +"%Y-%m-%dT%H:%M:%SZ")
  fi

  local ops_json
  ops_json=$(gcloud container operations list \
    $(get_loc_flag "$cluster_loc") \
    --project="$PROJECT_ID" \
    --filter="targetLink~clusters/${CLUSTER_NAME} AND (operationType=UPGRADE_MASTER OR operationType=UPGRADE_NODES OR operationType=AUTO_UPGRADE_NODES)" \
    --format="json(name,operationType,status,startTime,detail)" 2>/dev/null || echo "[]")

  if [[ "$ops_json" != "[]" && -n "$ops_json" ]]; then
    local op_count
    op_count=$(echo "$ops_json" | jq 'length' 2>/dev/null || echo "0")
    if [[ "$op_count" -gt 0 ]]; then
      info "历史升级记录（最近 90 天）:"
      echo "$ops_json" | jq -r '
        sort_by(.startTime) | reverse[] |
        "  \(.startTime[:19] | gsub("T";" "))  [\(.operationType)]  \(.status)  \(.detail // .statusMessage // "")"
      ' 2>/dev/null
    fi
  fi

  echo ""
  divider
  echo -e "${BOLD}升级计划:${RESET}"
  echo -e "  • Master:     ${CYAN}从当前版本升级到最新版本${RESET}"
  if [[ "$AUTO_UPGRADE_NODES" == "true" ]]; then
    echo -e "  • Node:       ${CYAN}同时升级 Node${RESET}"
  else
    echo -e "  • Node:       ${DIM}不升级（使用 --auto-upgrade-nodes 可同时升级）${RESET}"
  fi
  echo -e "  • 区域:       ${cluster_loc}"
  divider
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Dry-run 模式，以上为预览信息，未执行实际升级"
    exit 0
  fi

  if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
    printf "确认执行升级? (y/N): "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && info "已取消" && exit 0
  fi

  # 执行 Master 升级
  echo ""
  do_upgrade_master "$CLUSTER_NAME" "$cluster_loc"

  # 如果指定了 auto-upgrade-nodes，也升级 Node
  if [[ "$AUTO_UPGRADE_NODES" == "true" ]]; then
    echo ""
    do_upgrade_nodes "$CLUSTER_NAME" "$cluster_loc"
  fi

  echo ""
  success "升级操作已触发，请使用 verify-gke-cluster-upgrade.sh 监控进度"
  echo ""
}

main "$@"