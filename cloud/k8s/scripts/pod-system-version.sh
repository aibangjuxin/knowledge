#!/bin/bash

# 脚本名称: check-pod-versions-concurrent.sh
# 用途: 并发查询 GKE 中每个 Deployment 的 Pod 系统版本

set -e

# 默认值
NAMESPACE="default"
MAX_JOBS=10

# 使用说明
usage() {
  cat <<EOF
使用方法: $0 [选项]

选项:
    -n NAMESPACE    指定 Kubernetes namespace (默认: default)
    -j JOBS         最大并发任务数 (默认: 10)
    -h              显示此帮助信息

示例:
    $0 -n production
    $0 -n staging -j 20
EOF
  exit 1
}

# 解析命令行参数
while getopts "n:j:h" opt; do
  case $opt in
  n)
    NAMESPACE="$OPTARG"
    ;;
  j)
    MAX_JOBS="$OPTARG"
    ;;
  h)
    usage
    ;;
  \?)
    echo "无效选项: -$OPTARG" >&2
    usage
    ;;
  esac
done

# 检查 kubectl 是否可用
if ! command -v kubectl &>/dev/null; then
  echo "错误: kubectl 未安装或不在 PATH 中"
  exit 1
fi

# 检查 namespace 是否存在
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "错误: Namespace '$NAMESPACE' 不存在"
  exit 1
fi

echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "查询时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "并发任务数: $MAX_JOBS"
echo "=========================================="
echo ""

# 创建临时目录和文件
TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/results.txt"
LOCK_DIR="$TEMP_DIR/locks"
mkdir -p "$LOCK_DIR"

# 清理函数
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 确定 Deployment 名称的函数
determine_deployment_name() {
  local pod_name="$1"
  local app_label="$2"
  local owner_name="$3"
  local deployment_name=""

  # 方法1: 从 owner reference 获取(适用于 ReplicaSet)
  if [[ "$owner_name" =~ ^(.+)-[a-z0-9]+$ ]]; then
    deployment_name="${BASH_REMATCH[1]}"
  fi

  # 方法2: 使用 app 标签
  if [ -z "$deployment_name" ] && [ -n "$app_label" ] && [ "$app_label" != "null" ]; then
    deployment_name="$app_label"
  fi

  # 方法3: 从 Pod 名称推断
  if [ -z "$deployment_name" ]; then
    if [[ "$pod_name" =~ ^(.+)-[a-z0-9]+-[a-z0-9]+$ ]]; then
      deployment_name="${BASH_REMATCH[1]}"
    else
      deployment_name="$pod_name"
    fi
  fi

  echo "$deployment_name"
}

# 查询单个 Pod 的函数
query_pod_version() {
  local pod_name="$1"
  local app_label="$2"
  local owner_name="$3"
  local namespace="$4"

  # 确定 Deployment 名称
  local deployment_name
  deployment_name=$(determine_deployment_name "$pod_name" "$app_label" "$owner_name")

  # 使用文件锁实现去重
  local lock_file="$LOCK_DIR/$deployment_name.lock"

  # 尝试创建锁文件(原子操作)
  if mkdir "$lock_file" 2>/dev/null; then
    # 成功创建锁,表示此 Deployment 未被处理

    # 执行查询
    local os_version
    os_version=$(kubectl exec -n "$namespace" "$pod_name" -- cat /etc/issue 2>/dev/null | head -n 1 | tr -d '\n' || echo "无法获取")

    # 清理版本信息
    os_version=$(echo "$os_version" | sed 's/\\[a-z]//g' | xargs)

    # 写入结果(使用追加模式并加锁)
    (
      flock -x 200
      echo "$deployment_name|$pod_name|$os_version" >>"$TEMP_FILE"
    ) 200>"$TEMP_FILE.lock"

  fi
  # 如果锁已存在,说明此 Deployment 已被其他进程处理,直接跳过
}

# 导出函数和变量供子进程使用
export -f determine_deployment_name
export -f query_pod_version
export TEMP_FILE
export LOCK_DIR
export NAMESPACE

# 获取所有 Running 状态的 Pod
PODS=$(kubectl get pods -n "$NAMESPACE" \
  --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.app}{"\t"}{.metadata.ownerReferences[0].name}{"\n"}{end}')

# 检查是否有 Running 的 Pod
if [ -z "$PODS" ]; then
  echo "警告: 在 namespace '$NAMESPACE' 中没有找到 Running 状态的 Pod"
  exit 0
fi

# 并发处理每个 Pod
job_count=0
while IFS=$'\t' read -r pod_name app_label owner_name; do
  # 跳过空行
  [ -z "$pod_name" ] && continue

  # 后台执行查询
  query_pod_version "$pod_name" "$app_label" "$owner_name" "$NAMESPACE" &

  ((job_count++))

  # 控制并发数
  while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
    sleep 0.1
  done

done <<<"$PODS"

# 等待所有后台任务完成
wait

echo "处理了 $job_count 个 Pod"
echo ""

# 输出表头
printf "%-40s %-40s %-50s\n" "DEPLOYMENT" "POD" "OS VERSION"
printf "%-40s %-40s %-50s\n" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..50})"

# 输出结果(按 Deployment 名称排序)
if [ -f "$TEMP_FILE" ]; then
  sort "$TEMP_FILE" | while IFS='|' read -r deployment pod version; do
    printf "%-40s %-40s %-50s\n" "$deployment" "$pod" "$version"
  done
else
  echo "没有收集到任何数据"
fi

echo ""
echo "查询完成!"
