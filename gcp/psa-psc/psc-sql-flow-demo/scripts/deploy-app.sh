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