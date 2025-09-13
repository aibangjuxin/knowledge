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