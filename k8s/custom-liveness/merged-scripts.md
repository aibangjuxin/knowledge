# Shell Scripts Collection

Generated on: 2025-12-12 11:34:06
Directory: /Users/lex/git/knowledge/k8s/custom-liveness

## `build-custom-image.sh`

```bash

```

## `deploy-and-test.sh`

```bash
#!/bin/bash

echo "部署Squid代理故障转移系统..."

# 1. 部署基础配置
kubectl apply -f squid-failover-deployment.yaml

# 2. 等待Pod启动
echo "等待Pod启动..."
kubectl wait --for=condition=ready pod -l app=squid-proxy --timeout=120s
kubectl wait --for=condition=ready pod -l app=proxy-selector --timeout=120s

# 3. 检查服务状态
echo "检查服务状态..."
kubectl get pods -l app=squid-proxy
kubectl get pods -l app=proxy-selector

# 4. 测试代理选择器
echo "测试代理选择器..."
kubectl port-forward service/proxy-selector 8080:8080 &
PORT_FORWARD_PID=$!

sleep 5

# 测试获取可用代理
curl -s http://localhost:8080/proxy | jq .

# 测试健康检查
curl -s http://localhost:8080/health | jq .

# 清理端口转发
kill $PORT_FORWARD_PID

echo "部署完成！"

# 5. 显示使用说明
cat << EOF

使用说明：
1. 查看代理状态：
   kubectl port-forward service/proxy-selector 8080:8080
   curl http://localhost:8080/proxy

2. 测试故障转移：
   # 停止主代理
   kubectl scale deployment squid-proxy-primary --replicas=0
   
   # 再次查看代理状态，应该切换到备用代理
   curl http://localhost:8080/proxy

3. 恢复主代理：
   kubectl scale deployment squid-proxy-primary --replicas=1

4. 查看日志：
   kubectl logs -l app=proxy-selector -f

EOF
```

## `deploy-and-verify.sh`

```bash
#!/bin/bash

echo "=== 部署Squid代理与自定义健康检查 ==="

# 1. 部署YAML
echo "1. 部署配置..."
kubectl apply -f squid-deployment-with-custom-probe.yaml

# 2. 等待Pod启动
echo "2. 等待Pod启动..."
kubectl wait --for=condition=ready pod -l app=squid-proxy --timeout=300s

# 3. 验证ConfigMap是否创建成功
echo "3. 验证ConfigMap..."
kubectl get configmap health-check-script -o yaml

# 4. 验证Pod状态
echo "4. 检查Pod状态..."
kubectl get pods -l app=squid-proxy

# 5. 验证脚本文件是否正确挂载
echo "5. 验证脚本文件挂载..."
POD_NAME=$(kubectl get pods -l app=squid-proxy -o jsonpath='{.items[0].metadata.name}')
echo "Pod名称: $POD_NAME"

# 检查health-checker容器中的文件
echo "检查/app目录内容:"
kubectl exec $POD_NAME -c health-checker -- ls -la /app/

echo "检查health-check.py文件内容:"
kubectl exec $POD_NAME -c health-checker -- head -10 /app/health-check.py

# 6. 检查健康检查服务是否运行
echo "6. 测试健康检查端点..."
kubectl port-forward $POD_NAME 8080:8080 &
PORT_FORWARD_PID=$!

sleep 5

# 测试健康检查端点
echo "测试/health端点:"
curl -s http://localhost:8080/health | jq . || echo "健康检查端点未响应"

echo "测试/ready端点:"
curl -s http://localhost:8080/ready | jq . || echo "就绪检查端点未响应"

# 清理端口转发
kill $PORT_FORWARD_PID 2>/dev/null

# 7. 查看容器日志
echo "7. 查看健康检查容器日志..."
kubectl logs $POD_NAME -c health-checker --tail=20

echo "=== 部署验证完成 ==="
```

## `measure_startup.sh`

```bash
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

```

