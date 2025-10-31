#!/bin/bash
# -------------------------------------------------------
# Kubernetes Deployment Image Updater
# Version: 2.1 (keyword-based interactive)
# Author: GPT-5 + User logic preserved
# -------------------------------------------------------

set -euo pipefail

# ======= 通用函数 =======

log() {
  echo -e "🔹 $1"
}

warn() {
  echo -e "⚠️  $1"
}

error() {
  echo -e "❌ $1" >&2
}

usage() {
  echo
  echo "用法: $0 -i <image-keyword> [-n <namespace>]"
  echo
  echo "参数说明:"
  echo "  -i  镜像关键字（用于匹配当前 Deployment 的镜像）"
  echo "  -n  指定命名空间（可选，不填则扫描全部命名空间）"
  echo
  echo "示例:"
  echo "  $0 -i my-service"
  echo "  $0 -i v1.2.3 -n production"
  echo
  exit 1
}

# ======= 参数解析 =======

NAMESPACE=""
IMAGE_KEYWORD=""

while getopts ":i:n:h" opt; do
  case ${opt} in
    i ) IMAGE_KEYWORD=$OPTARG ;;
    n ) NAMESPACE=$OPTARG ;;
    h ) usage ;;
    * ) usage ;;
  esac
done

if [[ -z "${IMAGE_KEYWORD}" ]]; then
  usage
fi

# ======= 环境检查 =======

if ! command -v kubectl &> /dev/null; then
  error "kubectl 未安装，请先安装 kubectl"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  error "无法连接到 Kubernetes 集群，请检查 kubeconfig"
  exit 1
fi

# ======= 获取 Deployment 列表 =======

if [[ -n "$NAMESPACE" ]]; then
  NS_OPT="-n $NAMESPACE"
else
  NS_OPT="--all-namespaces"
fi

log "正在检索 Deployment 信息（关键字: $IMAGE_KEYWORD）..."

DEPLOY_INFO=$(kubectl get deploy $NS_OPT -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"|"}{.image}{"\n"}{end}{end}')

if [[ -z "$DEPLOY_INFO" ]]; then
  error "未找到任何 Deployment"
  exit 1
fi

# ======= 模糊匹配镜像关键字 =======

MATCHED_LINES=$(echo "$DEPLOY_INFO" | grep -i "$IMAGE_KEYWORD" || true)
if [[ -z "$MATCHED_LINES" ]]; then
  error "未找到包含关键字 '$IMAGE_KEYWORD' 的镜像"
  exit 1
fi

echo
log "找到以下匹配的 Deployment 与镜像:"
echo "---------------------------------------------"

MATCHED_NS=()
MATCHED_DEPLOY=()
MATCHED_CONTAINER=()
MATCHED_IMAGE=()

i=0
while IFS='|' read -r ns deploy container image; do
  MATCHED_NS[i]="$ns"
  MATCHED_DEPLOY[i]="$deploy"
  MATCHED_CONTAINER[i]="$container"
  MATCHED_IMAGE[i]="$image"
  printf "%2d) %s/%s (%s): %s\n" "$i" "$ns" "$deploy" "$container" "$image"
  ((i++))
done <<< "$MATCHED_LINES"

if [[ $i -eq 0 ]]; then
  error "未匹配到任何镜像"
  exit 1
fi

echo
read -p "请输入要更新的序号（可输入多个，用空格分隔）: " -a SELECTED_INDICES
if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
  error "未选择任何 Deployment"
  exit 1
fi

# ======= 展示将执行的操作 =======

echo
log "将要执行以下更新操作:"
for idx in "${SELECTED_INDICES[@]}"; do
  echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> ?"
done

# ======= 输入目标镜像 =======

echo
log "请输入完整的目标镜像名称 (包含标签):"
warn "提示: 当前搜索关键字是 '$IMAGE_KEYWORD'"
read -p "目标镜像: " FINAL_IMAGE

if [[ -z "$FINAL_IMAGE" ]]; then
  error "目标镜像不能为空"
  exit 1
fi

# ======= 确认替换计划 =======

echo
log "最终替换计划如下:"
for idx in "${SELECTED_INDICES[@]}"; do
  echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> $FINAL_IMAGE"
done

echo
read -p "确认执行以上更新操作吗？(y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "🚫 已取消操作"
  exit 0
fi

# ======= 执行更新 =======

for idx in "${SELECTED_INDICES[@]}"; do
  ns="${MATCHED_NS[idx]}"
  deploy="${MATCHED_DEPLOY[idx]}"
  container="${MATCHED_CONTAINER[idx]}"
  echo
  log "正在更新: $ns/$deploy ($container)"
  kubectl set image deployment/"$deploy" "$container"="$FINAL_IMAGE" -n "$ns" --record
  log "等待 Rollout 完成..."
  kubectl rollout status deployment/"$deploy" -n "$ns"
done

echo
log "✅ 所有更新操作已完成！"
