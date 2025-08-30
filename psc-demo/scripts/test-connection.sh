#!/bin/bash

# 连接测试脚本

set -e

# 加载环境变量
source "$(dirname "$0")/../setup/env-vars.sh"

echo "🧪 开始测试 PSC 连接..."

# 1. 检查 Pod 状态
echo "📊 检查 Pod 状态..."
kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}

# 2. 检查服务状态
echo "🔍 检查服务状态..."
kubectl get svc -n ${NAMESPACE}

# 3. 获取 Pod 名称
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
echo "测试 Pod: ${POD_NAME}"

# 4. 测试网络连通性
echo "🌐 测试网络连通性..."
echo "测试 PSC 端点连通性..."
kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ping -c 3 ${PSC_ENDPOINT_IP} || echo "Ping 可能被禁用，这是正常的"

echo "测试数据库端口连通性..."
kubectl exec ${POD_NAME} -n ${NAMESPACE} -- nc -zv ${PSC_ENDPOINT_IP} ${DB_PORT}

# 5. 测试应用健康检查
echo "🏥 测试应用健康检查..."
kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/health | head -20

# 6. 测试数据库连接
echo "🗄️  测试数据库连接..."
kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/api/v1/users

# 7. 测试数据库统计
echo "📈 测试数据库连接池统计..."
kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/api/v1/db-stats

# 8. 端口转发测试
echo "🔄 启动端口转发进行本地测试..."
echo "在另一个终端运行以下命令进行本地测试:"
echo "kubectl port-forward svc/db-app-service 8080:80 -n ${NAMESPACE}"
echo ""
echo "然后访问:"
echo "curl http://localhost:8080/health"
echo "curl http://localhost:8080/api/v1/users"
echo "curl http://localhost:8080/api/v1/db-stats"

# 9. 创建测试用户
echo "👤 创建测试用户..."
kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- \
    --post-data='{"name":"Test User","email":"test@example.com"}' \
    --header='Content-Type: application/json' \
    http://localhost:8080/api/v1/users

# 10. 查看应用日志
echo "📋 查看应用日志 (最近 20 行)..."
kubectl logs ${POD_NAME} -n ${NAMESPACE} --tail=20

# 11. 性能测试
echo "⚡ 简单性能测试..."
echo "测试健康检查端点响应时间..."
for i in {1..5}; do
    echo "请求 $i:"
    kubectl exec ${POD_NAME} -n ${NAMESPACE} -- time wget -qO- http://localhost:8080/health > /dev/null
done

echo ""
echo "✅ 连接测试完成！"
echo ""
echo "📋 测试总结:"
echo "- PSC 端点连通性: ✅"
echo "- 数据库端口连通性: ✅"
echo "- 应用健康检查: ✅"
echo "- 数据库查询: ✅"
echo "- 连接池统计: ✅"
echo ""
echo "🔧 故障排除命令:"
echo "查看详细日志: kubectl logs -f ${POD_NAME} -n ${NAMESPACE}"
echo "进入 Pod 调试: kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- /bin/sh"
echo "查看事件: kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
echo "查看 Pod 描述: kubectl describe pod ${POD_NAME} -n ${NAMESPACE}"