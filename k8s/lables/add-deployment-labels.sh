#!/bin/bash

# 脚本用途：给指定的 deployment 添加 labels，使其 pod 能够访问特定 namespace 的服务
# 使用方法：./add-deployment-labels.sh

set -e

# ===========================================
# 配置区域 - 根据你的需求修改这里
# ===========================================

# 目标 namespace（deployment 所在的 namespace）
NAMESPACE="your-namespace"

# 要添加的 label
LABEL_KEY="lex"
LABEL_VALUE="enabled"

# 需要打标签的 deployment 列表
DEPLOYMENTS=(
    "deployment-1"
    "deployment-2" 
    "deployment-3"
    # 在这里添加更多的 deployment 名称
)

# ===========================================
# 脚本执行部分
# ===========================================

echo "🚀 开始为 deployment 添加 labels..."
echo "Namespace: ${NAMESPACE}"
echo "Label: ${LABEL_KEY}=${LABEL_VALUE}"
echo "Target deployments: ${DEPLOYMENTS[*]}"
echo "=========================================="

# 检查 namespace 是否存在
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "❌ Namespace '${NAMESPACE}' 不存在，请检查配置"
    exit 1
fi

# 为每个 deployment 添加 label
for deploy in "${DEPLOYMENTS[@]}"; do
    echo "📝 处理 deployment: ${deploy}"
    
    # 检查 deployment 是否存在
    if ! kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        echo "⚠️  Deployment '${deploy}' 在 namespace '${NAMESPACE}' 中不存在，跳过"
        continue
    fi
    
    # 使用 kubectl patch 添加 label 到 pod template
    # 这会触发滚动更新，确保新的 pod 带有 label
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
for deploy in "${DEPLOYMENTS[@]}"; do
    if kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        echo "📋 Deployment ${deploy} 的 pods:"
        kubectl get pods -n "${NAMESPACE}" -l app="${deploy}" --show-labels | grep "${LABEL_KEY}=${LABEL_VALUE}" || echo "   ⚠️  未找到带有 ${LABEL_KEY}=${LABEL_VALUE} 的 pods"
        echo ""
    fi
done

echo "✅ 脚本执行完成！"
echo ""
echo "💡 提示："
echo "1. 所有指定的 deployment 已添加 ${LABEL_KEY}=${LABEL_VALUE} label"
echo "2. Pod 已通过滚动更新重新创建，新 pod 带有该 label"
echo "3. 现在这些 pod 应该能够访问目标 namespace 的服务了"
echo ""
echo "🔧 如需手动重启某个 deployment，使用："
echo "   kubectl rollout restart deployment/<deployment-name> -n ${NAMESPACE}"