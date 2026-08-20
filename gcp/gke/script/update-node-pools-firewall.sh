#!/usr/bin/env bash
# =============================================================================
# update-node-pools-firewall.sh — GKE Node Pool Network Tags 更新脚本
#
# 用途: 给指定 GKE 集群下的一个或多个 Node Pool 添加/替换 network tags,
#      以便 VPC firewall rules 通过 targetTags 匹配这些节点。
#
# 用法: ./update-node-pools-firewall.sh --project <PROJECT_ID> \
#                                      --cluster <CLUSTER_NAME> \
#                                      --location <LOCATION> \
#                                      --add-tags <TAG1,TAG2,...> \
#                                      [--node-pool <NP_NAME>|--all-node-pools] \
#                                      [--apply] [-h]
#
# 默认行为 (无 --apply): 仅打印将要执行的 gcloud 命令,不真正调用。
# 加 --apply:           才真正执行 gcloud container node-pools update --tags=...
#
# 依赖: gcloud, jq (可选,用于校验 JSON 输出)
#
# 关键事实 (2026-08-20, 来源 https://cloud.google.com/kubernetes-engine/docs/how-to/autopilot-network-tags):
#   - Standard 集群下, --tags 作用在 Node Pool 级别, GKE 会把 tags
#     同步到底层 Compute Engine VM 实例, 并应用到后续自动 provision 的新节点。
#   - Autopilot 集群没有 node pool 概念, 应该用 --autoprovisioning-network-tags
#     (本脚本不覆盖 Autopilot)。
#   - GKE 1.28+ 推荐使用 Tags (key-value + IAM) 而非 legacy network tags,
#     本脚本用的是 legacy --tags, 与 Lex 当前命令风格一致。
#
# 重要副作用提醒:
#   gcloud container node-pools update --tags=... 会 REPLACE 整个 tags 列表,
#   不会追加。如果想保留已有 tag, 必须把已有 tag 一起传进来。
#   脚本默认会先 describe 当前 tags, 打印合并后的最终 tag 列表, 供用户核对。
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0.34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}== $* ==${RESET}"; }

# --------------------------------------------------------------------------- #
# 默认值
# --------------------------------------------------------------------------- #
PROJECT=""
CLUSTER=""
LOCATION=""
NEW_TAGS=""           # 逗号分隔, 例如 "https-server,sslv2"
NODE_POOL=""          # 单个 node pool 名称
ALL_NODE_POOLS=false  # 处理该集群下全部 node pool
APPLY=false

# --------------------------------------------------------------------------- #
# 帮助
# --------------------------------------------------------------------------- #
show_help() {
    echo -e "${BOLD}update-node-pools-firewall.sh${RESET} — 给 GKE Node Pool 添加 / 替换 network tags"
    echo ""
    echo -e "${BOLD}用法:${RESET}"
    echo -e "    $0 --project PROJECT_ID --cluster CLUSTER_NAME --location LOCATION \\"
    echo -e "       --add-tags TAG1,TAG2,... [OPTIONS]"
    echo ""
    echo -e "${BOLD}必填:${RESET}"
    echo -e "    --project      PROJECT_ID          GCP project ID"
    echo -e "    --cluster      CLUSTER_NAME        GKE 集群名"
    echo -e "    --location     LOCATION            region 或 zone (例如 asia-east2 / asia-east2-a)"
    echo -e "    --add-tags     TAG1,TAG2,...       要设置的 network tags (逗号分隔)"
    echo ""
    echo -e "${BOLD}可选:${RESET}"
    echo -e "    --node-pool    NP_NAME             只处理指定 node pool (默认)"
    echo -e "    --all-node-pools                    处理该集群下全部 node pool"
    echo -e "    --apply                           真正执行 gcloud (默认只打印命令)"
    echo -e "    -h, --help                        显示本帮助"
    echo ""
    echo -e "${BOLD}示例:${RESET}"
    echo -e "    # 只打印命令, 不真正执行"
    echo -e "    $0 --project my-proj --cluster my-cluster --location asia-east2 \\"
    echo -e "       --add-tags https-server,api-gateway --node-pool default-pool"
    echo ""
    echo -e "    # 真正执行, 并应用到全部 node pool"
    echo -e "    $0 --project my-proj --cluster my-cluster --location asia-east2 \\"
    echo -e "       --add-tags https-server --all-node-pools --apply"
    echo ""
    echo -e "${BOLD}注意:${RESET}"
    echo -e "    gcloud container node-pools update --tags=... 是 REPLACE 语义,"
    echo -e "    不是 APPEND。已有 tag 必须一起传入,否则会被清除。"
}

# --------------------------------------------------------------------------- #
# 参数解析
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT="${2:-}"; shift 2 ;;
        --cluster)
            CLUSTER="${2:-}"; shift 2 ;;
        --location)
            LOCATION="${2:-}"; shift 2 ;;
        --add-tags)
            NEW_TAGS="${2:-}"; shift 2 ;;
        --node-pool)
            NODE_POOL="${2:-}"; shift 2 ;;
        --all-node-pools)
            ALL_NODE_POOLS=true; shift ;;
        --apply)
            APPLY=true; shift ;;
        -h|--help)
            show_help; exit 0 ;;
        *)
            error "未知参数: $1"
            echo "运行 $0 -h 查看用法" >&2
            exit 1 ;;
    esac
done

# --------------------------------------------------------------------------- #
# 参数校验
# --------------------------------------------------------------------------- #
require_param() {
    if [[ -z "${!1}" ]]; then
        error "缺少必填参数: --$1"
        show_help >&2
        exit 1
    fi
}

require_param PROJECT
require_param CLUSTER
require_param LOCATION
require_param NEW_TAGS

if [[ -n "${NODE_POOL}" && "${ALL_NODE_POOLS}" == "true" ]]; then
    error "--node-pool 和 --all-node-pools 不能同时使用"
    exit 1
fi

if [[ -z "${NODE_POOL}" && "${ALL_NODE_POOLS}" == "false" ]]; then
    warn "未指定 --node-pool, 默认只处理名为 'default-pool' 的 node pool。"
    warn "如需处理全部 node pool, 加 --all-node-pools。"
    NODE_POOL="default-pool"
fi

# 校验 tag 格式: 字母数字 + 短横线 + 下划线, 不允许逗号/空格混进 tag 本身
if ! [[ "${NEW_TAGS}" =~ ^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$ ]]; then
    error "--add-tags 格式非法: '${NEW_TAGS}'"
    error "每个 tag 只能含 [A-Za-z0-9_.-], 多个 tag 用英文逗号分隔"
    exit 1
fi

# 校验依赖
if ! command -v gcloud >/dev/null 2>&1; then
    error "gcloud 未安装或不在 PATH"
    exit 1
fi

# --------------------------------------------------------------------------- #
# 核心逻辑
# --------------------------------------------------------------------------- #
# 取单个 node pool 当前 tags (GKE 在 describe 输出中不直接暴露 tags,
# 但底层是同步到 instance template 的 tags 字段。
# 我们用 gcloud container node-pools describe 拿 config.instanceTemplate,
# 然后从 instance template 上读 tags。)
get_current_tags() {
    local np_name="$1"

    # 拿到 instance template URL
    local it_url
    if ! it_url="$(gcloud container node-pools describe "${np_name}" \
            --cluster="${CLUSTER}" \
            --location="${LOCATION}" \
            --project="${PROJECT}" \
            --format="value(config.instanceTemplate)" 2>/dev/null)"; then
        return 1
    fi

    # 空值 = 没设过
    if [[ -z "${it_url}" ]]; then
        return 0
    fi

    # 从 instance template 取 tags.items
    gcloud compute instance-templates describe "${it_url##*/}" \
        --project="${PROJECT}" \
        --format="value(properties.tags.items)" 2>/dev/null \
        | tr ';' ',' \
        | sed 's/^,*//; s/,*$//'
}

# 列出该集群下全部 node pool 名称
list_node_pools() {
    gcloud container node-pools list \
        --cluster="${CLUSTER}" \
        --location="${LOCATION}" \
        --project="${PROJECT}" \
        --format="value(name)"
}

# 计算合并后的最终 tag 列表 (REPLACE 语义下, 我们把 [已有] + [新增] 求并集去重)
merge_tags() {
    local current="$1"
    local incoming="$2"
    local merged
    merged="$(printf "%s,%s" "${current}" "${incoming}" \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -v '^$' \
        | sort -u \
        | paste -sd ',' -)"
    echo "${merged}"
}

# 执行单个 node pool 的更新
update_one_pool() {
    local np_name="$1"

    header "Node pool: ${np_name}"

    local current_tags=""
    if current_tags="$(get_current_tags "${np_name}")"; then
        if [[ -n "${current_tags}" ]]; then
            info "当前 tags: ${current_tags}"
        else
            info "当前 tags: (无)"
        fi
    else
        warn "读取 instance template 失败, 跳过 (cluster 可能不是 Standard 或权限不足)"
        return 1
    fi

    local final_tags
    final_tags="$(merge_tags "${current_tags}" "${NEW_TAGS}")"

    info "合并后 tags: ${final_tags}"

    local cmd
    cmd="gcloud container node-pools update ${np_name} \
    --cluster=${CLUSTER} \
    --location=${LOCATION} \
    --project=${PROJECT} \
    --tags=${final_tags}"

    if [[ "${APPLY}" == "true" ]]; then
        echo -e "${DIM}\$ ${cmd}${RESET}"
        if eval "${cmd}"; then
            success "${np_name} tags 已更新"
        else
            error "${np_name} 更新失败"
            return 1
        fi
    else
        echo -e "${YELLOW}[DRY-RUN]${RESET} 将执行:"
        echo -e "${DIM}${cmd}${RESET}"
        echo ""
        echo -e "${YELLOW}[DRY-RUN]${RESET} 注: gcloud --tags 是 REPLACE 语义,"
        echo -e "${YELLOW}[DRY-RUN]${RESET} 实际写入的 tags = ${BOLD}${final_tags}${RESET}"
        echo -e "${YELLOW}[DRY-RUN]${RESET} 加 --apply 才真正调用 gcloud"
    fi
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
header "参数"
echo "  project      : ${PROJECT}"
echo "  cluster      : ${CLUSTER}"
echo "  location     : ${LOCATION}"
echo "  add-tags     : ${NEW_TAGS}"
if [[ "${ALL_NODE_POOLS}" == "true" ]]; then
    echo "  node pool    : (全部)"
else
    echo "  node pool    : ${NODE_POOL}"
fi
echo "  mode         : $([[ "${APPLY}" == "true" ]] && echo "APPLY (真正执行)" || echo "DRY-RUN (只打印命令)")"

# 校验集群存在
if ! gcloud container clusters describe "${CLUSTER}" \
        --location="${LOCATION}" \
        --project="${PROJECT}" \
        --format="value(name)" >/dev/null 2>&1; then
    error "集群不存在或无权限: ${CLUSTER} @ ${LOCATION} (project=${PROJECT})"
    exit 1
fi

# 决定处理哪些 node pool
if [[ "${ALL_NODE_POOLS}" == "true" ]]; then
    np_list="$(list_node_pools || true)"
    if [[ -z "${np_list}" ]]; then
        error "集群 ${CLUSTER} 下没有 node pool, 或读取失败"
        exit 1
    fi
    header "将处理 $(echo "${np_list}" | wc -l | tr -d ' ') 个 node pool"
    echo "${np_list}" | while read -r np; do
        [[ -z "${np}" ]] && continue
        update_one_pool "${np}" || warn "${np} 处理失败, 继续下一个"
    done
else
    # 校验指定 node pool 存在
    if ! gcloud container node-pools describe "${NODE_POOL}" \
            --cluster="${CLUSTER}" \
            --location="${LOCATION}" \
            --project="${PROJECT}" \
            --format="value(name)" >/dev/null 2>&1; then
        error "node pool 不存在: ${NODE_POOL}"
        exit 1
    fi
    update_one_pool "${NODE_POOL}"
fi

if [[ "${APPLY}" == "true" ]]; then
    success "全部完成"
else
    info "全部完成 (DRY-RUN)。 加 --apply 才真正调用 gcloud。"
fi
