#!/usr/bin/env bash
# =============================================================================
# upgrade-gke-node.sh — GKE Node Pool 升级脚本
#
# 功能：升级 GKE 节点池到指定版本，支持 Surge Upgrade 策略
# 版本：v1.3 | 2026-05-30（修复版本一致性检查：current==target 时跳过）
# =============================================================================

set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

CLUSTER_NAME=""
REGION=""
PROJECT_ID=""
NODE_POOL_NAME=""
TARGET_VERSION=""
DRY_RUN=false
AUTO_YES=false

# -----------------------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }

usage() {
  cat <<EOF
$(basename "$0") — GKE Node Pool 升级脚本 v1.3

用法: $(basename "$0") --cluster <CLUSTER> --region <REGION> --project <PROJECT>
                [--node-pool-version <VERSION>] [--node-pool <POOL>]
                [--dry-run] [--yes]

必需参数:
  --cluster       GKE 集群名称
  --region        集群区域（如 europe-west2）
  --project       GCP 项目 ID

可选参数:
  --node-pool-version   目标版本（默认：跟随 Master 版本）
  --node-pool           指定节点池（默认：全部）
  --dry-run             仅验证，不执行
  --yes                 跳过确认

版本约束:
  1. 目标版本不能超过 Master 版本（硬约束）
  2. 如果节点当前版本已等于目标版本，直接退出，不执行升级
  3. 升级顺序：Master → Node（Node ≤ Master）
EOF
  exit 1
}

# -----------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cluster)         CLUSTER_NAME="$2"; shift 2 ;;
      --region)          REGION="$2";       shift 2 ;;
      --project)         PROJECT_ID="$2";    shift 2 ;;
      --node-pool)       NODE_POOL_NAME="$2"; shift 2 ;;
      --node-pool-version) TARGET_VERSION="$2"; shift 2 ;;
      --dry-run)  DRY_RUN=true;  shift ;;
      --yes)      AUTO_YES=true; shift ;;
      --help|-h)  usage ;;
      *)          error "未知参数: $1"; usage ;;
    esac
  done
}

validate_args() {
  local missing=0
  [[ -z "$CLUSTER_NAME" ]] && { error "缺少 --cluster"; missing=1; }
  [[ -z "$REGION" ]]      && { error "缺少 --region"; missing=1; }
  [[ -z "$PROJECT_ID" ]] && { error "缺少 --project"; missing=1; }
  (( missing == 1 )) && usage
}

# -----------------------------------------------------------------------------
get_cluster_info() {
  gcloud container clusters describe "$CLUSTER_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null
}

get_node_pool_names() {
  local json="$1"
  echo "$json" | jq -r '.nodePools[].name' 2>/dev/null
}

get_pool_version() {
  local pool="$1"
  local json="$2"
  echo "$json" | jq -r ".nodePools[] | select(.name==\"$pool\") | .version" 2>/dev/null
}

check_pdbs() {
  info "检查 PodDisruptionBudget..."
  local out
  out=$(kubectl get pdb --all-namespaces 2>/dev/null || true)
  if [[ -z "$out" ]] || echo "$out" | grep -q "No resources"; then
    warn "未发现 PDB，建议为关键应用配置 PDB"
    return 0
  fi
  local bad
  bad=$(echo "$out" | awk 'NR>1 && ($3!=$5)')
  if [[ -n "$bad" ]]; then
    error "发现不健康的 PDB:"
    echo "$bad" | column -t
    return 1
  fi
  success "PDB 检查通过"
  return 0
}

# -----------------------------------------------------------------------------
do_upgrade_cmd() {
  local ver="$1"
  local pool="$2"
  local op_id

  if [[ -n "$pool" ]]; then
    op_id=$(gcloud container clusters upgrade "$CLUSTER_NAME" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --cluster-version="$ver" \
      --node-pool="$pool" \
      --async \
      --format='value(operation.name)' 2>/dev/null)
  else
    op_id=$(gcloud container clusters upgrade "$CLUSTER_NAME" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --cluster-version="$ver" \
      --async \
      --format='value(operation.name)' 2>/dev/null)
  fi

  echo "$op_id"
}

wait_op() {
  local op_id="$1"
  local desc="$2"
  local max_wait=600
  local elapsed=0
  local interval=15

  info "$desc"
  info "操作 ID: $op_id"

  while (( elapsed < max_wait )); do
    local status
    status=$(gcloud container operations describe "$op_id" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(status)' 2>/dev/null)

    case "$status" in
      DONE)  success "操作已完成"; return 0 ;;
      RUNNING)
        info "升级进行中... 已等待 ${elapsed}s"
        sleep $interval
        (( elapsed += interval ))
        ;;
      *)  error "操作状态异常: $status"; return 1 ;;
    esac
  done

  warn "等待超时，检查最终状态..."
  status=$(gcloud container operations describe "$op_id" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status)' 2>/dev/null)
  [[ "$status" == "DONE" ]] && success "操作已确认完成" || error "操作状态: $status"
  [[ "$status" == "DONE" ]] && return 0 || return 1
}

# -----------------------------------------------------------------------------
preflight_check() {
  local json
  json=$(get_cluster_info)

  if [[ -z "$json" ]]; then
    error "无法获取集群信息"
    exit 1
  fi

  local master_ver cluster_status current_ver
  master_ver=$(echo "$json" | jq -r '.currentMasterVersion')
  cluster_status=$(echo "$json" | jq -r '.status')
  current_ver=$(echo "$json" | jq -r '.currentNodeVersion')

  info "集群状态: $cluster_status"
  info "Master 版本: $master_ver"
  info "Node 当前版本: $current_ver"

  if [[ "$cluster_status" != "RUNNING" ]]; then
    error "集群状态非 RUNNING: $cluster_status"
    exit 3
  fi

  if [[ -z "$TARGET_VERSION" ]]; then
    TARGET_VERSION="$master_ver"
    info "目标版本未指定，自动跟随 Master: $TARGET_VERSION"
  fi

  # 硬约束：目标版本不能超过 Master
  local p_target p_master
  p_target="${TARGET_VERSION##*-gke.}"  && p_target="${p_target//[^0-9]/}"
  p_master="${master_ver##*-gke.}"       && p_master="${p_master//[^0-9]/}"
  if (( p_target > p_master )); then
    error "版本约束违反: 目标($TARGET_VERSION) > Master($master_ver)"
    error "Node 版本不得超过 Master 版本"
    exit 2
  fi

  # 如果已经一致，直接退出
  if [[ "$current_ver" == "$TARGET_VERSION" ]]; then
    success "Node 当前版本($current_ver) 已等于目标版本，无需升级"
    exit 0
  fi

  info "版本升级路径: $current_ver -> $TARGET_VERSION (Master=$master_ver)"

  # 节点池列表
  echo -e "\n${BOLD}节点池当前版本:${RESET}"
  local pool_name pool_ver
  while IFS= read -r pool_name; do
    [[ -z "$pool_name" ]] && continue
    pool_ver=$(get_pool_version "$pool_name" "$json")
    printf "  %-20s %s\n" "$pool_name" "$pool_ver"
  done < <(get_node_pool_names "$json")

  if command -v kubectl >/dev/null 2>&1; then
    check_pdbs || true
  else
    info "kubectl 未安装，跳过 PDB 检查"
  fi
}

# -----------------------------------------------------------------------------
print_summary() {
  local action="$1"
  cat <<EOF

${BOLD}══════════════════════════════════════════════════════════════${RESET}
${BOLD}  GKE Node 池升级摘要${RESET}
${BOLD}══════════════════════════════════════════════════════════════${RESET}

  集群:       $CLUSTER_NAME
  区域:       $REGION
  项目:       $PROJECT_ID
  节点池:     ${NODE_POOL_NAME:-全部}
  目标版本:   $TARGET_VERSION
  策略:       surge=1 / maxUnavailable=0
  操作:       $action

${BOLD}══════════════════════════════════════════════════════════════${RESET}
EOF
}

confirm_upgrade() {
  print_summary "待执行"

  [[ "$DRY_RUN" == "true" ]] && info "[DRY-RUN] 预览完成" && return 1
  [[ "$AUTO_YES" == "true" ]] && return 0

  echo -n -e "${YELLOW}[CONFIRM]${RESET} 确定升级 Node 池吗？[y/N]: "
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] && return 0
  info "取消升级"
  exit 0
}

# -----------------------------------------------------------------------------
do_upgrade() {
  local json
  json=$(get_cluster_info)

  if [[ -n "$NODE_POOL_NAME" ]]; then
    do_upgrade_single "$NODE_POOL_NAME"
  else
    do_upgrade_all "$json"
  fi
}

do_upgrade_single() {
  local pool="$1"
  local ver
  ver=$(get_pool_version "$pool" "$(get_cluster_info)")
  info "升级节点池: $pool ($ver -> $TARGET_VERSION)"

  local op_id
  op_id=$(do_upgrade_cmd "$TARGET_VERSION" "$pool")

  if [[ -z "$op_id" ]]; then
    error "获取操作 ID 失败（可能升级已在进行中）"
    exit 1
  fi

  wait_op "$op_id" "升级节点池 $pool"
}

do_upgrade_all() {
  local json="$1"
  local first_op

  while IFS= read -r pool; do
    [[ -z "$pool" ]] && continue
    local ver
    ver=$(get_pool_version "$pool" "$json")
    info "升级节点池: $pool ($ver -> $TARGET_VERSION)"

    local op_id
    op_id=$(do_upgrade_cmd "$TARGET_VERSION" "$pool")

    if [[ -z "$op_id" ]]; then
      warn "节点池 $pool 获取操作 ID 失败，跳过"
      continue
    fi
    [[ -z "$first_op" ]] && first_op="$op_id"
  done < <(get_node_pool_names "$json")

  if [[ -n "$first_op" ]]; then
    wait_op "$first_op" "升级所有节点池"
  else
    error "没有成功发起任何升级操作"
    exit 1
  fi
}

post_verify() {
  info "验证升级结果..."

  local json
  json=$(get_cluster_info)

  echo -e "\n${BOLD}节点池版本状态:${RESET}"
  local pool pool_ver
  while IFS= read -r pool; do
    [[ -z "$pool" ]] && continue
    pool_ver=$(get_pool_version "$pool" "$json")
    printf "  %-20s %s\n" "$pool" "$pool_ver"
  done < <(get_node_pool_names "$json")

  local final_ver
  final_ver=$(echo "$json" | jq -r '.currentNodeVersion' 2>/dev/null || echo "?")

  if [[ "$final_ver" == "$TARGET_VERSION" ]]; then
    success "Node 版本已升级到: $TARGET_VERSION"
  else
    success "Node 版本: $final_ver"
  fi
}

# -----------------------------------------------------------------------------
main() {
  parse_args "$@"
  validate_args

  info "========================================"
  info " GKE Node 池升级工具 v1.3"
  info "========================================"

  preflight_check
  confirm_upgrade || return 0
  [[ "$DRY_RUN" == "true" ]] && print_summary "dry-run 完成" && return 0

  do_upgrade
  post_verify
  print_summary "升级完成"
  success "Node 池升级成功"
}

main "$@"