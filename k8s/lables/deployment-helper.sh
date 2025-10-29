#!/bin/bash

# 辅助脚本：查看 deployment 状态和手动重启
# 使用方法：
#   ./deployment-helper.sh list -n namespace          # 列出所有 deployment
#   ./deployment-helper.sh check -n namespace -l key=value  # 检查带特定 label 的 pods
#   ./deployment-helper.sh restart -n namespace -d deployment  # 重启指定 deployment

set -e

COMMAND=""
NAMESPACE=""
LABEL=""
DEPLOYMENT=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        list|check|restart)
            COMMAND="$1"
            shift
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -l|--label)
            LABEL="$2"
            shift 2
            ;;
        -d|--deployment)
            DEPLOYMENT="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法:"
            echo "  $0 list -n <namespace>                    # 列出所有 deployment"
            echo "  $0 check -n <namespace> -l <key=value>    # 检查带特定 label 的 pods"
            echo "  $0 restart -n <namespace> -d <deployment> # 重启指定 deployment"
            echo ""
            echo "示例:"
            echo "  $0 list -n my-namespace"
            echo "  $0 check -n my-namespace -l lex=enabled"
            echo "  $0 restart -n my-namespace -d my-app"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

if [ -z "$COMMAND" ] || [ -z "$NAMESPACE" ]; then
    echo "❌ 缺少必要参数，使用 -h 查看帮助"
    exit 1
fi

case $COMMAND in
    "list")
        echo "📋 Namespace '${NAMESPACE}' 中的所有 deployments:"
        echo "=========================================="
        kubectl get deployments -n "${NAMESPACE}" -o wide
        ;;
        
    "check")
        if [ -z "$LABEL" ]; then
            echo "❌ check 命令需要 -l 参数"
            exit 1
        fi
        
        echo "🔍 检查带有 label '${LABEL}' 的 pods:"
        echo "=========================================="
        kubectl get pods -n "${NAMESPACE}" -l "${LABEL}" --show-labels
        
        echo ""
        echo "📊 统计信息:"
        POD_COUNT=$(kubectl get pods -n "${NAMESPACE}" -l "${LABEL}" --no-headers | wc -l)
        echo "找到 ${POD_COUNT} 个带有 label '${LABEL}' 的 pods"
        ;;
        
    "restart")
        if [ -z "$DEPLOYMENT" ]; then
            echo "❌ restart 命令需要 -d 参数"
            exit 1
        fi
        
        echo "🔄 重启 deployment '${DEPLOYMENT}':"
        echo "=========================================="
        kubectl rollout restart deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"
        
        echo "等待重启完成..."
        kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s
        
        if [ $? -eq 0 ]; then
            echo "✅ Deployment '${DEPLOYMENT}' 重启完成"
        else
            echo "⚠️  Deployment '${DEPLOYMENT}' 重启超时，请手动检查"
        fi
        ;;
esac