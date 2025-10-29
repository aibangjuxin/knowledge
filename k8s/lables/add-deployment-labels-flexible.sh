#!/bin/bash

# 脚本用途：给指定的 deployment 添加 labels
# 使用方法：
#   ./add-deployment-labels-flexible.sh -n namespace -l key=value -d "deploy1,deploy2,deploy3"
#   ./add-deployment-labels-flexible.sh -n my-namespace -l lex=enabled -d "app1,app2"

set -e

# 默认值
NAMESPACE=""
LABEL=""
DEPLOYMENTS=""
HELP=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -l | --label)
    LABEL="$2"
    shift 2
    ;;
  -d | --deployments)
    DEPLOYMENTS="$2"
    shift 2
    ;;
  -h | --help)
    HELP=true
    shift
    ;;
  *)
    echo "未知参数: $1"
    HELP=true
    shift
    ;;
  esac
done

# 显示帮助信息
if [ "$HELP" = true ] || [ -z "$NAMESPACE" ] || [ -z "$LABEL" ] || [ -z "$DEPLOYMENTS" ]; then
  echo "用法: $0 -n <namespace> -l <key=value> -d <deployment1,deployment2,...>"
  echo ""
  echo "参数:"
  echo "  -n, --namespace     目标 namespace"
  echo "  -l, --label         要添加的 label (格式: key=value)"
  echo "  -d, --deployments   deployment 列表 (用逗号分隔)"
  echo "  -h, --help          显示帮助信息"
  echo ""
  echo "示例:"
  echo "  $0 -n my-namespace -l lex=enabled -d \"app1,app2,app3\""
  echo "  $0 -n production -l env=prod -d \"web-server,api-server\""
  exit 1
fi

# 解析 label
if [[ ! "$LABEL" =~ ^[^=]+=[^=]+$ ]]; then
  echo "❌ Label 格式错误，应该是 key=value 格式"
  exit 1
fi

LABEL_KEY=$(echo "$LABEL" | cut -d'=' -f1)
LABEL_VALUE=$(echo "$LABEL" | cut -d'=' -f2)

# 将 deployment 字符串转换为数组
IFS=',' read -ra DEPLOY_ARRAY <<<"$DEPLOYMENTS"

echo "🚀 开始为 deployment 添加 labels..."
echo "Namespace: ${NAMESPACE}"
echo "Label: ${LABEL_KEY}=${LABEL_VALUE}"
echo "Target deployments: ${DEPLOY_ARRAY[*]}"
echo "=========================================="

# 检查 namespace 是否存在
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' 不存在，请检查配置"
  exit 1
fi

# 为每个 deployment 添加 label
for deploy in "${DEPLOY_ARRAY[@]}"; do
  # 去除空格
  deploy=$(echo "$deploy" | xargs)

  echo "📝 处理 deployment: ${deploy}"

  # 检查 deployment 是否存在
  if ! kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "⚠️  Deployment '${deploy}' 在 namespace '${NAMESPACE}' 中不存在，跳过"
    continue
  fi

  # 添加 label 到 pod template
  echo "   添加 label 到 pod template..."
  kubectl patch deployment "${deploy}" -n "${NAMESPACE}" --type='merge' \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"${LABEL_KEY}\":\"${LABEL_VALUE}\"}}}}}"

  if [ $? -eq 0 ]; then
    echo "   ✅ ${deploy} label 添加成功"
  else
    echo "   ❌ ${deploy} label 添加失败"
    continue
  fi

  # 等待滚动更新完成
  echo "   等待滚动更新完成..."
  kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=300s

  if [ $? -eq 0 ]; then
    echo "   ✅ ${deploy} 滚动更新完成"
  else
    echo "   ⚠️  ${deploy} 滚动更新超时，请手动检查"
  fi

  echo ""
done

echo "=========================================="
echo "🔍 验证结果："

# 验证 pods 是否带有正确的 label
for deploy in "${DEPLOY_ARRAY[@]}"; do
  deploy=$(echo "$deploy" | xargs)
  if kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "📋 Deployment ${deploy} 的 pods:"
    kubectl get pods -n "${NAMESPACE}" -l "${LABEL_KEY}=${LABEL_VALUE}" --show-labels | grep "${deploy}" || echo "   ⚠️  未找到 ${deploy} 的带有 ${LABEL_KEY}=${LABEL_VALUE} 的 pods"
    echo ""
  fi
done

echo "✅ 脚本执行完成！"
