#!/bin/bash

# Consumer 项目设置脚本 - 创建 GKE 集群和 PSC 端点

set -e

# 加载环境变量
source "$(dirname "$0")/env-vars.sh"

# 读取 Producer 配置
if [ -f "$(dirname "$0")/producer-config.txt" ]; then
    source "$(dirname "$0")/producer-config.txt"
else
    echo "❌ 请先运行 setup-producer.sh"
    exit 1
fi

echo "🚀 开始设置 Consumer 项目: ${CONSUMER_PROJECT_ID}"

# 1. 启用必要的 API
echo "📡 启用必要的 API..."
gcloud services enable compute.googleapis.com --project=${CONSUMER_PROJECT_ID}
gcloud services enable container.googleapis.com --project=${CONSUMER_PROJECT_ID}
gcloud services enable privateconnect.googleapis.com --project=${CONSUMER_PROJECT_ID}

# 2. 创建 VPC 网络和子网
echo "🌐 创建 Consumer VPC 网络..."
if ! gcloud compute networks describe ${CONSUMER_VPC} --project=${CONSUMER_PROJECT_ID} &>/dev/null; then
    gcloud compute networks create ${CONSUMER_VPC} \
        --project=${CONSUMER_PROJECT_ID} \
        --subnet-mode=custom
    echo "✅ VPC ${CONSUMER_VPC} 创建成功"
else
    echo "ℹ️  VPC ${CONSUMER_VPC} 已存在"
fi

# 创建 GKE 子网
if ! gcloud compute networks subnets describe ${CONSUMER_SUBNET} --region=${REGION} --project=${CONSUMER_PROJECT_ID} &>/dev/null; then
    gcloud compute networks subnets create ${CONSUMER_SUBNET} \
        --project=${CONSUMER_PROJECT_ID} \
        --network=${CONSUMER_VPC} \
        --range=10.1.0.0/16 \
        --region=${REGION} \
        --secondary-range=pods=10.2.0.0/16,services=10.3.0.0/16
    echo "✅ 子网 ${CONSUMER_SUBNET} 创建成功"
else
    echo "ℹ️  子网 ${CONSUMER_SUBNET} 已存在"
fi

# 3. 创建静态 IP 地址
echo "📍 创建 PSC 静态 IP 地址..."
if ! gcloud compute addresses describe ${STATIC_IP_NAME} --region=${REGION} --project=${CONSUMER_PROJECT_ID} &>/dev/null; then
    gcloud compute addresses create ${STATIC_IP_NAME} \
        --project=${CONSUMER_PROJECT_ID} \
        --region=${REGION} \
        --subnet=${CONSUMER_SUBNET}
    echo "✅ 静态 IP ${STATIC_IP_NAME} 创建成功"
else
    echo "ℹ️  静态 IP ${STATIC_IP_NAME} 已存在"
fi

# 获取 IP 地址
export PSC_ENDPOINT_IP=$(gcloud compute addresses describe ${STATIC_IP_NAME} \
    --project=${CONSUMER_PROJECT_ID} \
    --region=${REGION} \
    --format="value(address)")

echo "📍 PSC 端点 IP: ${PSC_ENDPOINT_IP}"

# 4. 创建 PSC 端点
echo "🔗 创建 PSC 端点..."
if ! gcloud compute forwarding-rules describe ${PSC_ENDPOINT_NAME} --region=${REGION} --project=${CONSUMER_PROJECT_ID} &>/dev/null; then
    gcloud compute forwarding-rules create ${PSC_ENDPOINT_NAME} \
        --project=${CONSUMER_PROJECT_ID} \
        --region=${REGION} \
        --network=${CONSUMER_VPC} \
        --address=${STATIC_IP_NAME} \
        --target-service-attachment=${SQL_SERVICE_ATTACHMENT} \
        --allow-psc-global-access
    echo "✅ PSC 端点创建成功"
else
    echo "ℹ️  PSC 端点已存在"
fi

# 5. 创建防火墙规则
echo "🔥 创建防火墙规则..."
# 允许访问 Cloud SQL 的出站规则
gcloud compute firewall-rules create allow-sql-psc-egress \
    --project=${CONSUMER_PROJECT_ID} \
    --network=${CONSUMER_VPC} \
    --direction=EGRESS \
    --destination-ranges=${PSC_ENDPOINT_IP}/32 \
    --action=ALLOW \
    --rules=tcp:${DB_PORT} || echo "ℹ️  防火墙规则已存在"

# 允许内部通信
gcloud compute firewall-rules create allow-internal-${CONSUMER_VPC} \
    --project=${CONSUMER_PROJECT_ID} \
    --network=${CONSUMER_VPC} \
    --direction=INGRESS \
    --source-ranges=10.1.0.0/16,10.2.0.0/16,10.3.0.0/16 \
    --action=ALLOW \
    --rules=tcp,udp,icmp || echo "ℹ️  内部通信规则已存在"

# 6. 创建 GKE 集群
echo "☸️  创建 GKE 集群..."
if ! gcloud container clusters describe ${GKE_CLUSTER_NAME} --zone=${ZONE} --project=${CONSUMER_PROJECT_ID} &>/dev/null; then
    gcloud container clusters create ${GKE_CLUSTER_NAME} \
        --project=${CONSUMER_PROJECT_ID} \
        --zone=${ZONE} \
        --network=${CONSUMER_VPC} \
        --subnetwork=${CONSUMER_SUBNET} \
        --cluster-secondary-range-name=pods \
        --services-secondary-range-name=services \
        --enable-ip-alias \
        --enable-workload-identity \
        --num-nodes=2 \
        --machine-type=e2-medium \
        --disk-size=20GB \
        --enable-autorepair \
        --enable-autoupgrade
    echo "✅ GKE 集群创建成功"
else
    echo "ℹ️  GKE 集群已存在"
fi

# 7. 获取集群凭据
echo "🔑 获取集群凭据..."
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${CONSUMER_PROJECT_ID}

# 8. 创建 Google Service Account
echo "👤 创建 Google Service Account..."
gcloud iam service-accounts create db-app-gsa \
    --project=${CONSUMER_PROJECT_ID} \
    --display-name="Database App Service Account" || echo "ℹ️  Service Account 已存在"

# 9. 授予必要的权限
echo "🔐 配置 IAM 权限..."
gcloud projects add-iam-policy-binding ${CONSUMER_PROJECT_ID} \
    --member="serviceAccount:db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"

# 10. 保存配置信息
echo "💾 保存配置信息..."
cat > "$(dirname "$0")/consumer-config.txt" << EOF
# Consumer 项目配置信息
CONSUMER_PROJECT_ID=${CONSUMER_PROJECT_ID}
GKE_CLUSTER_NAME=${GKE_CLUSTER_NAME}
PSC_ENDPOINT_IP=${PSC_ENDPOINT_IP}
PSC_ENDPOINT_NAME=${PSC_ENDPOINT_NAME}
WORKLOAD_IDENTITY_SA=db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com
REGION=${REGION}
ZONE=${ZONE}
EOF

echo "🎉 Consumer 项目设置完成！"
echo "📄 配置信息已保存到: $(dirname "$0")/consumer-config.txt"
echo "📍 PSC 端点 IP: ${PSC_ENDPOINT_IP}"
echo "☸️  GKE 集群: ${GKE_CLUSTER_NAME}"