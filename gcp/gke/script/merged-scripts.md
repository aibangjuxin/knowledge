# Shell Scripts Collection

Generated on: 2026-08-21 09:11:57
Directory: /Users/lex/git/knowledge/gcp/gke/script

## `update-node-pools-firewall.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# update-node-pools-firewall.sh — Manage GKE Standard node-pool network tags
#
# Network tags are evaluated by VPC firewall rules. This script is deliberately
# dry-run by default and preserves existing tags unless --replace-tags is used.
# It supports manually-created Standard node pools only; Autopilot and
# auto-provisioned node pools must use cluster-level autoprovisioning tags.
# =============================================================================

set -euo pipefail

RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}== $* ==${RESET}"; }

PROJECT=''; CLUSTER=''; LOCATION=''; NODE_POOL=''; ALL_NODE_POOLS=false
ADD_TAGS=''; REMOVE_TAGS=''; REPLACE_TAGS=''; APPLY=false; ASSUME_YES=false

show_help() {
    cat <<EOF
${BOLD}update-node-pools-firewall.sh${RESET} — 管理 GKE Standard node pool 的 legacy network tags

用法:
  $0 --project PROJECT_ID --cluster CLUSTER_NAME --location LOCATION \\
     (--node-pool NP_NAME | --all-node-pools) OPERATION [--apply --yes]

操作（三选一）:
  --add-tags TAG1,TAG2        添加 tag，并保留已有 tag
  --remove-tags TAG1,TAG2     删除指定 tag
  --replace-tags TAG1,TAG2    用指定 tag 完全替换现有列表

范围:
  --node-pool NP_NAME         只处理指定 node pool
  --all-node-pools            处理全部手动创建的 node pool

执行控制:
  --apply                     真正执行（默认 dry-run）
  --yes                       跳过 --apply 的交互确认；适合 CI/CD
  -h, --help                  显示本帮助

示例:
  # 演练：为一个 node pool 添加 tag
  $0 --project my-proj --cluster my-cluster --location asia-east2 \\
     --node-pool default-pool --add-tags api-gateway

  # 非交互地执行，并在写入后校验
  $0 --project my-proj --cluster my-cluster --location asia-east2 \\
     --all-node-pools --remove-tags old-firewall-tag --apply --yes

注意: --replace-tags 会清除未包含的原有 tag。Autopilot 和 NAP node pool
不适用本脚本；应使用 --autoprovisioning-network-tags 管理。
EOF
}

need_value() { [[ -n "${2:-}" ]] || { error "$1 需要一个值"; exit 2; }; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project|--cluster|--location|--node-pool|--add-tags|--remove-tags|--replace-tags)
            need_value "$1" "${2:-}"
            case "$1" in
                --project) PROJECT="$2" ;; --cluster) CLUSTER="$2" ;;
                --location) LOCATION="$2" ;; --node-pool) NODE_POOL="$2" ;;
                --add-tags) ADD_TAGS="$2" ;; --remove-tags) REMOVE_TAGS="$2" ;;
                --replace-tags) REPLACE_TAGS="$2" ;;
            esac
            shift 2 ;;
        --all-node-pools) ALL_NODE_POOLS=true; shift ;;
        --apply) APPLY=true; shift ;;
        --yes) ASSUME_YES=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) error "未知参数: $1"; exit 2 ;;
    esac
done

require_param() { [[ -n "${!1}" ]] || { error "缺少必填参数: --${2}"; exit 2; }; }
require_param PROJECT project; require_param CLUSTER cluster; require_param LOCATION location
if [[ -n "$NODE_POOL" && "$ALL_NODE_POOLS" == true ]]; then error '--node-pool 与 --all-node-pools 不能同时使用'; exit 2; fi
if [[ -z "$NODE_POOL" && "$ALL_NODE_POOLS" == false ]]; then error '必须指定 --node-pool 或 --all-node-pools'; exit 2; fi

operation_count=0
[[ -n "$ADD_TAGS" ]] && ((operation_count+=1)) || true
[[ -n "$REMOVE_TAGS" ]] && ((operation_count+=1)) || true
[[ -n "$REPLACE_TAGS" ]] && ((operation_count+=1)) || true
if (( operation_count != 1 )); then error '必须且只能指定一个操作：--add-tags、--remove-tags 或 --replace-tags'; exit 2; fi

# Compute Engine network tags must meet RFC 1035: lowercase letters, digits and hyphens.
validate_tags() {
    local value="$1" tag
    IFS=',' read -r -a tags <<< "$value"
    for tag in "${tags[@]}"; do
        if ! [[ "$tag" =~ ^[a-z]([-a-z0-9]*[a-z0-9])?$ && ${#tag} -le 63 ]]; then
            error "非法 network tag: '$tag'（需符合 RFC 1035，最长 63 个字符）"
            exit 2
        fi
    done
}
[[ -n "$ADD_TAGS" ]] && validate_tags "$ADD_TAGS"
[[ -n "$REMOVE_TAGS" ]] && validate_tags "$REMOVE_TAGS"
[[ -n "$REPLACE_TAGS" ]] && validate_tags "$REPLACE_TAGS"
command -v gcloud >/dev/null 2>&1 || { error 'gcloud 未安装或不在 PATH'; exit 1; }

normalize_tags() {
    tr ';,' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | sort -u | paste -sd ',' -
}
get_current_tags() {
    gcloud container node-pools describe "$1" --cluster="$CLUSTER" --location="$LOCATION" --project="$PROJECT" \
        --format='value(config.tags)' 2>/dev/null | normalize_tags
}
list_node_pools() {
    gcloud container node-pools list --cluster="$CLUSTER" --location="$LOCATION" --project="$PROJECT" --format='value(name)'
}
is_autoprovisioned_pool() {
    [[ "$(gcloud container node-pools describe "$1" --cluster="$CLUSTER" --location="$LOCATION" --project="$PROJECT" --format='value(autoscaling.autoprovisioned)' 2>/dev/null | tr '[:upper:]' '[:lower:]')" == 'true' ]]
}
compute_final_tags() {
    local current="$1" input="$2"
    if [[ -n "$REPLACE_TAGS" ]]; then printf '%s\n' "$REPLACE_TAGS" | normalize_tags; return; fi
    if [[ -n "$ADD_TAGS" ]]; then printf '%s,%s\n' "$current" "$input" | normalize_tags; return; fi
    local tag result=''
    IFS=',' read -r -a current_array <<< "$current"
    for tag in "${current_array[@]}"; do
        [[ -z "$tag" || ",$input," == *",$tag,"* ]] && continue
        result+="${result:+,}$tag"
    done
    printf '%s\n' "$result" | normalize_tags
}
print_command() { printf ' '; printf '%q ' "$@"; printf '\n'; }

cluster_autopilot="$(gcloud container clusters describe "$CLUSTER" --location="$LOCATION" --project="$PROJECT" --format='value(autopilot.enabled)' 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
if [[ "$cluster_autopilot" == true ]]; then
    error '这是 Autopilot 集群；请使用 gcloud container clusters update --autoprovisioning-network-tags 管理 tags'
    exit 1
fi

if [[ "$APPLY" == true && "$ASSUME_YES" == false ]]; then
    read -r -p "将修改 GKE node pool network tags。继续吗？[y/N] " confirmation
    [[ "$confirmation" =~ ^[Yy]([Ee][Ss])?$ ]] || { info '已取消。'; exit 0; }
fi

header '参数'
echo "  project      : $PROJECT"; echo "  cluster      : $CLUSTER"; echo "  location     : $LOCATION"
echo "  scope        : $([[ "$ALL_NODE_POOLS" == true ]] && echo '全部 node pools' || echo "$NODE_POOL")"
if [[ -n "$ADD_TAGS" ]]; then
    operation_display="add $ADD_TAGS"
elif [[ -n "$REMOVE_TAGS" ]]; then
    operation_display="remove $REMOVE_TAGS"
else
    operation_display="replace $REPLACE_TAGS"
fi
echo "  operation    : $operation_display"
echo "  mode         : $([[ "$APPLY" == true ]] && echo APPLY || echo DRY-RUN)"

if [[ "$ALL_NODE_POOLS" == true ]]; then
    pools=()
    while IFS= read -r pool; do
        [[ -n "$pool" ]] && pools+=("$pool")
    done < <(list_node_pools)
    ((${#pools[@]} > 0)) || { error '未找到 node pool，或缺少读取权限'; exit 1; }
else
    pools=("$NODE_POOL")
fi

failed=0; changed=0; skipped=0
for pool in "${pools[@]}"; do
    [[ -z "$pool" ]] && continue
    header "Node pool: $pool"
    if is_autoprovisioned_pool "$pool"; then
        warn '这是 auto-provisioned node pool；跳过。请使用 cluster-level --autoprovisioning-network-tags。'
        ((skipped+=1)); continue
    fi
    if ! current_tags="$(get_current_tags "$pool")"; then
        error '读取 config.tags 失败（node pool 不存在或权限不足）'
        ((failed+=1)); continue
    fi
    final_tags="$(compute_final_tags "$current_tags" "${ADD_TAGS:-$REMOVE_TAGS}")"
    info "当前 tags: ${current_tags:-(无)}"; info "目标 tags: ${final_tags:-(无)}"
    if [[ "$current_tags" == "$final_tags" ]]; then info '无需变更'; ((skipped+=1)); continue; fi

    cmd=(gcloud container node-pools update "$pool" --cluster="$CLUSTER" --location="$LOCATION" --project="$PROJECT" --tags="$final_tags")
    if [[ "$APPLY" == false ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} 将执行:"; print_command "${cmd[@]}"
        echo -e "${DIM}Rollback:${RESET}"; print_command gcloud container node-pools update "$pool" --cluster="$CLUSTER" --location="$LOCATION" --project="$PROJECT" --tags="$current_tags"
        ((changed+=1)); continue
    fi
    print_command "${cmd[@]}"
    if ! "${cmd[@]}"; then error '更新失败'; ((failed+=1)); continue; fi
    actual_tags="$(get_current_tags "$pool" || true)"
    if [[ "$actual_tags" != "$final_tags" ]]; then
        error "写后校验失败：期望 '${final_tags:-(无)}'，实际 '${actual_tags:-(无)}'"
        ((failed+=1)); continue
    fi
    success '更新并校验成功'; ((changed+=1))
done

header '结果'
echo "  changed : $changed"; echo "  skipped : $skipped"; echo "  failed  : $failed"
(( failed == 0 )) || exit 1
if [[ "$APPLY" == true ]]; then
    success '全部变更已完成并通过校验'
else
    info 'Dry-run 完成；加 --apply --yes 执行。'
fi

```

## `upgrade-gke-node.sh`

```bash
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
```

## `upgrade-gke-cluster.sh`

```bash
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
```

