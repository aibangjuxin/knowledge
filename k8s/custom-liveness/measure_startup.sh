#!/bin/bash
# measure_startup.sh
# 
# 功能：测量 Pod 业务容器的真实启动时间（从容器启动到健康检查返回 200 OK 的耗时）
# 原理：利用 kubectl exec 在容器内部或通过端口转发循环通过 curl 探测健康检查接口
#
# 前提：
# 1. 目标 Pod 已经处于 Running 状态（或者正在启动中）
# 2. 容器内有 curl 命令，或者允许从外部访问 Probe 端口

set -e

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <pod-name> <port> <health-path> [namespace] [scheme]"
    echo "Example: $0 my-api-pod 8080 /health default http"
    exit 1
fi

POD_NAME=$1
PORT=$2
PATH=$3
NAMESPACE=${4:-default}
SCHEME=${5:-http}

echo "🔍 Target: $POD_NAME.$NAMESPACE"
echo "🔍 Probe: $SCHEME://localhost:$PORT$PATH"

# 1. 等待 Pod 进入 Running 状态 (确保主容器已创建)
echo "⏳ Waiting for pod to be Running..."
kubectl wait --for=condition=Ready=False pod/$POD_NAME -n $NAMESPACE --timeout=300s > /dev/null 2>&1 || true

# 获取容器启动的时间戳
# 注意：我们获取的是 containerStatuses[0] (通常是业务容器) 的 state.running.startedAt
# 如果容器还在 ContainerCreating，这里会为空，需要循环等待
CONTAINER_START_TIMESTAMP=""
while [ -z "$CONTAINER_START_TIMESTAMP" ]; do
    CONTAINER_START_TIMESTAMP=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)
    if [ -z "$CONTAINER_START_TIMESTAMP" ]; then
        echo "   ...waiting for container to create..."
        sleep 2
    fi
done

# 将 ISO8601 转为 Unix 时间戳 (适用 Linux/Mac data 命令)
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START_TIMESTAMP" "+%s")
else
    START_TIME_SEC=$(date -d "$CONTAINER_START_TIMESTAMP" "+%s")
fi

echo "🚀 Container Started At: $CONTAINER_START_TIMESTAMP ($START_TIME_SEC)"
echo "⏱️  Start probing health endpoint..."

# 2. 循环探测直到成功
while true; do
    # 使用 kubectl exec 在容器内探测 (如果容器内有 curl)
    # 或者使用 port-forward (更通用，不依赖容器内工具)
    # 这里我们采用 port-forward 的方式，因为它通用性更好，虽然稍微慢一点
    
    # 启动后台 port-forward
    kubectl port-forward pod/$POD_NAME $PORT:$PORT -n $NAMESPACE > /dev/null 2>&1 &
    PF_PID=$!
    
    # 给一点时间让连接建立
    sleep 1
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SCHEME://127.0.0.1:$PORT$PATH" || echo "000")
    
    # 杀掉后台 port-forward
    kill $PF_PID > /dev/null 2>&1 || true
    
    CURRENT_TIME_SEC=$(date +%s)
    ELAPSED=$((CURRENT_TIME_SEC - START_TIME_SEC))
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ Health Check Passed (200 OK)!"
        echo "------------------------------------------------"
        echo "📊 最终结果 (Result):"
        echo "应用程序启动耗时 (App Startup Duration): ${ELAPSED} 秒"
        echo "建议配置 (Recommended Config):"
        echo "  - startupProbe.initialDelaySeconds: 0"
        echo "  - startupProbe.periodSeconds: 10"
        
        # 计算建议的 FailureThreshold (耗时 * 1.5 / 10)
        THRESHOLD=$(echo "scale=0; ($ELAPSED * 1.5 / 10) + 1" | bc)
        echo "  - startupProbe.failureThreshold: $THRESHOLD"
        echo "------------------------------------------------"
        break
    else
        echo "   Still starting... (Elapsed: ${ELAPSED}s, Status: $HTTP_CODE)"
        sleep 2
    fi
done
