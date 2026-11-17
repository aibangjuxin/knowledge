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