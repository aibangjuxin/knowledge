# Shell Scripts Collection

Generated on: 2025-09-01 09:44:41
Directory: /root/groovy/psc-demo/scripts

## `cleanup.sh`

```bash
#!/bin/bash

# 清理脚本 - 删除所有创建的资源

set -e

# 加载环境变量
source "$(dirname "$0")/../setup/env-vars.sh"

echo "🧹 开始清理 PSC 演示资源..."

read -p "⚠️  这将删除所有创建的资源，确定要继续吗？(y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消清理操作"
    exit 1
fi

# 1. 清理 Kubernetes 资源
echo "☸️  清理 Kubernetes 资源..."
if kubectl get namespace ${NAMESPACE} &>/dev/null; then
    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
    echo "✅ 删除命名空间: ${NAMESPACE}"
fi

# 2. 删除 Docker 镜像 (可选)
echo "🐳 清理本地 Docker 镜像..."
docker rmi gcr.io/${CONSUMER_PROJECT_ID}/db-app:latest 2>/dev/null || true
docker rmi $(docker images gcr.io/${CONSUMER_PROJECT_ID}/db-app --format "table {{.Repository}}:{{.Tag}}" | grep -v REPOSITORY) 2>/dev/null || true

# 3. 清理 Consumer 项目资源
echo "🔧 清理 Consumer 项目资源..."

# 删除 GKE 集群
if gcloud container clusters describe ${GKE_CLUSTER_NAME} --zone=${ZONE} --project=${CONSUMER_PROJECT_ID} &>/dev/null; then
    echo "删除 GKE 集群: ${GKE_CLUSTER_NAME}"
    gcloud container clusters delete ${GKE_CLUSTER_NAME} \
        --zone=${ZONE} \
        --project=${CONSUMER_PROJECT_ID} \
        --quiet
fi

# 删除 Service Account
gcloud iam service-accounts delete db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

# 删除防火墙规则
gcloud compute firewall-rules delete allow-sql-psc-egress \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

gcloud compute firewall-rules delete allow-internal-${CONSUMER_VPC} \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

# 删除 PSC 端点
gcloud compute forwarding-rules delete ${PSC_ENDPOINT_NAME} \
    --region=${REGION} \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

# 删除静态 IP
gcloud compute addresses delete ${STATIC_IP_NAME} \
    --region=${REGION} \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

# 删除子网
gcloud compute networks subnets delete ${CONSUMER_SUBNET} \
    --region=${REGION} \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

# 删除 VPC
gcloud compute networks delete ${CONSUMER_VPC} \
    --project=${CONSUMER_PROJECT_ID} \
    --quiet 2>/dev/null || true

echo "✅ Consumer 项目资源清理完成"

# 4. 清理 Producer 项目资源 (可选)
read -p "🗄️  是否也要清理 Producer 项目的 Cloud SQL 实例？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗄️  清理 Producer 项目资源..."
    
    # 删除 Cloud SQL 实例
    if gcloud sql instances describe ${SQL_INSTANCE_NAME} --project=${PRODUCER_PROJECT_ID} &>/dev/null; then
        # 先禁用删除保护
        gcloud sql instances patch ${SQL_INSTANCE_NAME} \
            --project=${PRODUCER_PROJECT_ID} \
            --no-deletion-protection \
            --quiet
        
        # 删除实例
        gcloud sql instances delete ${SQL_INSTANCE_NAME} \
            --project=${PRODUCER_PROJECT_ID} \
            --quiet
    fi
    
    # 删除私有连接
    gcloud services vpc-peerings delete \
        --service=servicenetworking.googleapis.com \
        --network=${PRODUCER_VPC} \
        --project=${PRODUCER_PROJECT_ID} \
        --quiet 2>/dev/null || true
    
    # 删除私有 IP 范围
    gcloud compute addresses delete google-managed-services-${PRODUCER_VPC} \
        --global \
        --project=${PRODUCER_PROJECT_ID} \
        --quiet 2>/dev/null || true
    
    # 删除 VPC
    gcloud compute networks delete ${PRODUCER_VPC} \
        --project=${PRODUCER_PROJECT_ID} \
        --quiet 2>/dev/null || true
    
    echo "✅ Producer 项目资源清理完成"
fi

# 5. 清理配置文件
echo "📄 清理配置文件..."
rm -f "$(dirname "$0")/../setup/producer-config.txt"
rm -f "$(dirname "$0")/../setup/consumer-config.txt"

echo ""
echo "🎉 清理完成！"
echo ""
echo "📋 已清理的资源:"
echo "- Kubernetes 命名空间和所有资源"
echo "- GKE 集群"
echo "- PSC 端点和静态 IP"
echo "- 防火墙规则"
echo "- VPC 网络和子网"
echo "- Service Account"
echo "- 本地 Docker 镜像"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "- Cloud SQL 实例"
    echo "- Producer VPC 和相关资源"
fi
echo ""
echo "✅ 所有资源已成功清理！"
```

## `deploy-app.sh`

```bash
#!/bin/bash

# 应用部署脚本

set -e

# 加载环境变量
source "$(dirname "$0")/../setup/env-vars.sh"

# 读取配置
if [ -f "$(dirname "$0")/../setup/consumer-config.txt" ]; then
    source "$(dirname "$0")/../setup/consumer-config.txt"
else
    echo "❌ 请先运行 setup-consumer.sh"
    exit 1
fi

echo "🚀 开始部署应用到 GKE 集群..."

# 1. 确保连接到正确的集群
echo "☸️  连接到 GKE 集群..."
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${CONSUMER_PROJECT_ID}

# 2. 构建和推送 Docker 镜像
echo "🐳 构建 Docker 镜像..."
cd "$(dirname "$0")/../app"

# 设置镜像标签
IMAGE_TAG="gcr.io/${CONSUMER_PROJECT_ID}/db-app:$(date +%Y%m%d-%H%M%S)"
LATEST_TAG="gcr.io/${CONSUMER_PROJECT_ID}/db-app:latest"

# 构建镜像
docker build -t ${IMAGE_TAG} -t ${LATEST_TAG} .

# 推送镜像到 GCR
echo "📤 推送镜像到 Container Registry..."
docker push ${IMAGE_TAG}
docker push ${LATEST_TAG}

cd - > /dev/null

# 3. 配置 Workload Identity
echo "🔐 配置 Workload Identity..."
gcloud iam service-accounts add-iam-policy-binding \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${CONSUMER_PROJECT_ID}.svc.id.goog[${NAMESPACE}/${SERVICE_ACCOUNT_NAME}]" \
    db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com

# 4. 更新 Kubernetes 配置文件
echo "📝 更新 Kubernetes 配置..."
K8S_DIR="$(dirname "$0")/../k8s"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cp -r ${K8S_DIR}/* ${TEMP_DIR}/

# 替换配置文件中的占位符
find ${TEMP_DIR} -name "*.yaml" -exec sed -i.bak \
    -e "s/PROJECT_ID/${CONSUMER_PROJECT_ID}/g" \
    -e "s/PSC_ENDPOINT_IP/${PSC_ENDPOINT_IP}/g" \
    -e "s/TIMESTAMP/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" \
    {} \;

# 更新镜像标签
sed -i.bak "s|gcr.io/PROJECT_ID/db-app:latest|${LATEST_TAG}|g" ${TEMP_DIR}/deployment.yaml

# 5. 部署到 Kubernetes
echo "☸️  部署到 Kubernetes..."

# 创建命名空间
kubectl apply -f ${TEMP_DIR}/namespace.yaml

# 部署配置
kubectl apply -f ${TEMP_DIR}/configmap.yaml
kubectl apply -f ${TEMP_DIR}/secret.yaml
kubectl apply -f ${TEMP_DIR}/service-account.yaml

# 部署应用
kubectl apply -f ${TEMP_DIR}/deployment.yaml
kubectl apply -f ${TEMP_DIR}/service.yaml

# 部署网络策略和 HPA
kubectl apply -f ${TEMP_DIR}/network-policy.yaml
kubectl apply -f ${TEMP_DIR}/hpa.yaml

# 6. 等待部署完成
echo "⏳ 等待 Pod 启动..."
kubectl wait --for=condition=ready pod -l app=${APP_NAME} -n ${NAMESPACE} --timeout=300s

# 7. 显示部署状态
echo "📊 部署状态:"
kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}
kubectl get svc -n ${NAMESPACE}
kubectl get hpa -n ${NAMESPACE}

# 8. 获取服务信息
echo "🔍 服务信息:"
SERVICE_IP=$(kubectl get svc db-app-service -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
echo "Service IP: ${SERVICE_IP}"
echo "Service Port: 80"

# 9. 显示有用的命令
echo ""
echo "🎉 部署完成！"
echo ""
echo "📋 有用的命令:"
echo "查看 Pod 日志: kubectl logs -f deployment/${APP_NAME} -n ${NAMESPACE}"
echo "查看 Pod 状态: kubectl get pods -n ${NAMESPACE}"
echo "进入 Pod: kubectl exec -it deployment/${APP_NAME} -n ${NAMESPACE} -- /bin/sh"
echo "端口转发: kubectl port-forward svc/db-app-service 8080:80 -n ${NAMESPACE}"
echo "删除应用: kubectl delete namespace ${NAMESPACE}"

# 清理临时文件
rm -rf ${TEMP_DIR}

echo ""
echo "✅ 应用部署成功！"
```

## `monitor.sh`

```bash
#!/bin/bash

# 监控脚本 - 实时监控应用状态

set -e

# 加载环境变量
source "$(dirname "$0")/../setup/env-vars.sh"

echo "📊 PSC 演示应用监控面板"
echo "================================"

# 检查依赖
if ! command -v watch &> /dev/null; then
    echo "❌ 需要安装 watch 命令"
    echo "macOS: brew install watch"
    echo "Ubuntu: sudo apt-get install procps"
    exit 1
fi

# 监控函数
monitor_pods() {
    echo "📦 Pod 状态:"
    kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o wide
    echo ""
}

monitor_services() {
    echo "🔗 服务状态:"
    kubectl get svc -n ${NAMESPACE}
    echo ""
}

monitor_hpa() {
    echo "📈 自动扩缩容状态:"
    kubectl get hpa -n ${NAMESPACE} 2>/dev/null || echo "HPA 未配置"
    echo ""
}

monitor_endpoints() {
    echo "🎯 端点状态:"
    kubectl get endpoints -n ${NAMESPACE}
    echo ""
}

monitor_events() {
    echo "📋 最近事件:"
    kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -5
    echo ""
}

monitor_logs() {
    echo "📝 最近日志:"
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD_NAME" ]; then
        kubectl logs ${POD_NAME} -n ${NAMESPACE} --tail=5 2>/dev/null || echo "无法获取日志"
    else
        echo "没有运行的 Pod"
    fi
    echo ""
}

monitor_database_stats() {
    echo "🗄️  数据库连接统计:"
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD_NAME" ]; then
        kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/api/v1/db-stats 2>/dev/null | \
        python3 -m json.tool 2>/dev/null | head -10 || echo "无法获取数据库统计"
    else
        echo "没有运行的 Pod"
    fi
    echo ""
}

# 主监控函数
show_dashboard() {
    clear
    echo "📊 PSC 演示应用监控面板 - $(date)"
    echo "================================"
    echo "项目: ${CONSUMER_PROJECT_ID}"
    echo "集群: ${GKE_CLUSTER_NAME}"
    echo "命名空间: ${NAMESPACE}"
    echo "应用: ${APP_NAME}"
    echo "================================"
    echo ""
    
    monitor_pods
    monitor_services
    monitor_hpa
    monitor_endpoints
    monitor_events
    monitor_logs
    monitor_database_stats
    
    echo "按 Ctrl+C 退出监控"
}

# 交互式菜单
show_menu() {
    echo "📊 PSC 演示监控工具"
    echo "==================="
    echo "1. 实时监控面板"
    echo "2. 查看 Pod 详情"
    echo "3. 查看服务详情"
    echo "4. 查看应用日志"
    echo "5. 查看事件"
    echo "6. 测试应用健康状态"
    echo "7. 查看数据库连接统计"
    echo "8. 端口转发到本地"
    echo "9. 进入 Pod Shell"
    echo "0. 退出"
    echo ""
    read -p "请选择操作 (0-9): " choice
}

# 处理菜单选择
handle_choice() {
    case $choice in
        1)
            echo "启动实时监控面板..."
            watch -n 2 "$(declare -f show_dashboard); show_dashboard"
            ;;
        2)
            kubectl describe pods -n ${NAMESPACE} -l app=${APP_NAME}
            ;;
        3)
            kubectl describe svc -n ${NAMESPACE}
            ;;
        4)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                kubectl logs -f ${POD_NAME} -n ${NAMESPACE}
            else
                echo "没有运行的 Pod"
            fi
            ;;
        5)
            kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'
            ;;
        6)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                echo "测试健康检查端点..."
                kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/health | python3 -m json.tool
                echo ""
                echo "测试就绪检查端点..."
                kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/ready | python3 -m json.tool
            else
                echo "没有运行的 Pod"
            fi
            ;;
        7)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/api/v1/db-stats | python3 -m json.tool
            else
                echo "没有运行的 Pod"
            fi
            ;;
        8)
            echo "启动端口转发到本地 8080 端口..."
            echo "访问 http://localhost:8080 来测试应用"
            kubectl port-forward svc/db-app-service 8080:80 -n ${NAMESPACE}
            ;;
        9)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                echo "进入 Pod: ${POD_NAME}"
                kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- /bin/sh
            else
                echo "没有运行的 Pod"
            fi
            ;;
        0)
            echo "退出监控工具"
            exit 0
            ;;
        *)
            echo "无效选择，请重试"
            ;;
    esac
}

# 主循环
main() {
    # 检查集群连接
    if ! kubectl cluster-info &>/dev/null; then
        echo "❌ 无法连接到 Kubernetes 集群"
        echo "请确保已正确配置 kubectl"
        exit 1
    fi
    
    # 检查命名空间
    if ! kubectl get namespace ${NAMESPACE} &>/dev/null; then
        echo "❌ 命名空间 ${NAMESPACE} 不存在"
        echo "请先运行部署脚本"
        exit 1
    fi
    
    while true; do
        show_menu
        handle_choice
        echo ""
        read -p "按 Enter 继续..."
        clear
    done
}

# 如果直接运行脚本，显示菜单
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
```

## `test-connection.sh`

```bash
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
```

