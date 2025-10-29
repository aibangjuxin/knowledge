# Shell Scripts Collection

Generated on: 2025-10-29 17:57:52
Directory: /Users/lex/git/knowledge/k8s/lables

## `add-deployment-labels-flexible.sh`

```bash
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

```

## `add-deployment-labels.sh`

```bash
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
```

## `deployment-helper.sh`

```bash
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
```

