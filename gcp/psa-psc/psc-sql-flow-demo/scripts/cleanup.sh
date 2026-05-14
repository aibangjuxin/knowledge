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