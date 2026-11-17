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
