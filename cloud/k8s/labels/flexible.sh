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
DRY_RUN=false

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
  --dry-run)
    DRY_RUN=true
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
  echo "  --dry-run           预览模式，只显示将要执行的操作，不实际执行"
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

if [ "$DRY_RUN" = true ]; then
  echo "🔍 预览模式 - 将要执行的操作："
else
  echo "🚀 开始为 deployment 添加 labels..."
fi
echo "Namespace: ${NAMESPACE}"
echo "Label: ${LABEL_KEY}=${LABEL_VALUE}"
echo "Target deployments: ${DEPLOY_ARRAY[*]}"
if [ "$DRY_RUN" = true ]; then
  echo "模式: 预览模式 (不会实际执行)"
fi
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

  # 检查 pod template 中是否已经存在该 label
  echo "   检查 label 是否已存在..."
  CURRENT_LABEL_VALUE=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath="{.spec.template.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")
  
  if [ "$CURRENT_LABEL_VALUE" = "$LABEL_VALUE" ]; then
    echo "   ℹ️  Label ${LABEL_KEY}=${LABEL_VALUE} 已存在，跳过更新"
    echo "   ✅ ${deploy} 无需更新"
  else
    if [ -n "$CURRENT_LABEL_VALUE" ]; then
      echo "   📝 当前 label 值: ${LABEL_KEY}=${CURRENT_LABEL_VALUE}，将更新为: ${LABEL_KEY}=${LABEL_VALUE}"
    else
      echo "   📝 当前无此 label，将添加: ${LABEL_KEY}=${LABEL_VALUE}"
    fi
    
    if [ "$DRY_RUN" = true ]; then
      echo "   🔍 [预览] 将执行: kubectl patch deployment ${deploy} -n ${NAMESPACE} --type='merge' -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"${LABEL_KEY}\":\"${LABEL_VALUE}\"}}}}}}'"
      echo "   🔍 [预览] 将触发滚动更新，重新创建 pods"
      echo "   ✅ ${deploy} 预览完成"
    else
      # 添加 label 到 pod template
      echo "   添加/更新 label 到 pod template..."
      kubectl patch deployment "${deploy}" -n "${NAMESPACE}" --type='merge' \
        -p "{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"${LABEL_KEY}\":\"${LABEL_VALUE}\"}}}}}"

      if [ $? -eq 0 ]; then
        echo "   ✅ ${deploy} label 添加/更新成功"
        
        # 等待滚动更新完成
        echo "   等待滚动更新完成..."
        kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=300s

        if [ $? -eq 0 ]; then
          echo "   ✅ ${deploy} 滚动更新完成"
        else
          echo "   ⚠️  ${deploy} 滚动更新超时，请手动检查"
        fi
      else
        echo "   ❌ ${deploy} label 添加/更新失败"
        continue
      fi
    fi
  fi

  echo ""
done

echo "=========================================="
echo "🔍 验证结果："

# 验证 deployment 和 pods 的 label 状态
for deploy in "${DEPLOY_ARRAY[@]}"; do
  deploy=$(echo "$deploy" | xargs)
  if kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "📋 Deployment ${deploy}:"
    
    # 检查 deployment pod template 中的 label
    TEMPLATE_LABEL_VALUE=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath="{.spec.template.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")
    if [ "$TEMPLATE_LABEL_VALUE" = "$LABEL_VALUE" ]; then
      echo "   ✅ Pod template label: ${LABEL_KEY}=${TEMPLATE_LABEL_VALUE}"
    else
      echo "   ❌ Pod template label: ${LABEL_KEY}=${TEMPLATE_LABEL_VALUE:-"未设置"}"
    fi
    
    # 检查实际运行的 pods
    PODS_WITH_LABEL=$(kubectl get pods -n "${NAMESPACE}" -l "app=${deploy},${LABEL_KEY}=${LABEL_VALUE}" --no-headers 2>/dev/null | wc -l)
    TOTAL_PODS=$(kubectl get pods -n "${NAMESPACE}" -l "app=${deploy}" --no-headers 2>/dev/null | wc -l)
    
    if [ "$PODS_WITH_LABEL" -gt 0 ]; then
      echo "   ✅ 运行中的 pods: ${PODS_WITH_LABEL}/${TOTAL_PODS} 个 pods 带有 ${LABEL_KEY}=${LABEL_VALUE}"
    else
      echo "   ⚠️  运行中的 pods: 0/${TOTAL_PODS} 个 pods 带有 ${LABEL_KEY}=${LABEL_VALUE}"
    fi
    
    echo ""
  fi
done

echo "=========================================="
echo "📊 总结："
TOTAL_DEPLOYMENTS=${#DEPLOY_ARRAY[@]}
SUCCESSFUL_DEPLOYMENTS=0

for deploy in "${DEPLOY_ARRAY[@]}"; do
  deploy=$(echo "$deploy" | xargs)
  if kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    TEMPLATE_LABEL_VALUE=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath="{.spec.template.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")
    if [ "$TEMPLATE_LABEL_VALUE" = "$LABEL_VALUE" ]; then
      ((SUCCESSFUL_DEPLOYMENTS++))
    fi
  fi
done

echo "✅ 成功配置: ${SUCCESSFUL_DEPLOYMENTS}/${TOTAL_DEPLOYMENTS} 个 deployments"
echo "🏷️  Label: ${LABEL_KEY}=${LABEL_VALUE}"
echo "📦 Namespace: ${NAMESPACE}"

if [ "$SUCCESSFUL_DEPLOYMENTS" -eq "$TOTAL_DEPLOYMENTS" ]; then
  echo ""
  echo "🎉 所有 deployment 都已成功配置 label！"
  echo "💡 现在这些 pods 应该能够访问目标 namespace 的服务了"
else
  echo ""
  echo "⚠️  部分 deployment 配置失败，请检查上面的错误信息"
fi

echo ""
echo "✅ 脚本执行完成！"
