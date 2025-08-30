#!/bin/bash

# Producer 项目设置脚本 - 创建 Cloud SQL 并启用 PSC

set -e

# 加载环境变量
source "$(dirname "$0")/env-vars.sh"

echo "🚀 开始设置 Producer 项目: ${PRODUCER_PROJECT_ID}"

# 1. 启用必要的 API
echo "📡 启用必要的 API..."
gcloud services enable compute.googleapis.com --project=${PRODUCER_PROJECT_ID}
gcloud services enable sqladmin.googleapis.com --project=${PRODUCER_PROJECT_ID}
gcloud services enable servicenetworking.googleapis.com --project=${PRODUCER_PROJECT_ID}

# 2. 创建 VPC 网络
echo "🌐 创建 Producer VPC 网络..."
if ! gcloud compute networks describe ${PRODUCER_VPC} --project=${PRODUCER_PROJECT_ID} &>/dev/null; then
    gcloud compute networks create ${PRODUCER_VPC} \
        --project=${PRODUCER_PROJECT_ID} \
        --subnet-mode=custom
    echo "✅ VPC ${PRODUCER_VPC} 创建成功"
else
    echo "ℹ️  VPC ${PRODUCER_VPC} 已存在"
fi

# 3. 为 Cloud SQL 分配私有 IP 范围
echo "🔒 配置私有 IP 范围..."
if ! gcloud compute addresses describe google-managed-services-${PRODUCER_VPC} --global --project=${PRODUCER_PROJECT_ID} &>/dev/null; then
    gcloud compute addresses create google-managed-services-${PRODUCER_VPC} \
        --project=${PRODUCER_PROJECT_ID} \
        --global \
        --purpose=VPC_PEERING \
        --prefix-length=16 \
        --network=${PRODUCER_VPC}
    
    # 创建私有连接
    gcloud services vpc-peerings connect \
        --project=${PRODUCER_PROJECT_ID} \
        --service=servicenetworking.googleapis.com \
        --ranges=google-managed-services-${PRODUCER_VPC} \
        --network=${PRODUCER_VPC}
    echo "✅ 私有 IP 范围配置成功"
else
    echo "ℹ️  私有 IP 范围已配置"
fi

# 4. 创建 Cloud SQL 实例
echo "🗄️  创建 Cloud SQL 实例..."
if ! gcloud sql instances describe ${SQL_INSTANCE_NAME} --project=${PRODUCER_PROJECT_ID} &>/dev/null; then
    gcloud sql instances create ${SQL_INSTANCE_NAME} \
        --project=${PRODUCER_PROJECT_ID} \
        --database-version=${SQL_DATABASE_VERSION} \
        --tier=${SQL_TIER} \
        --region=${REGION} \
        --network=${PRODUCER_VPC} \
        --no-assign-ip \
        --root-password=${SQL_ROOT_PASSWORD} \
        --deletion-protection
    
    echo "⏳ 等待 Cloud SQL 实例创建完成..."
    gcloud sql instances describe ${SQL_INSTANCE_NAME} \
        --project=${PRODUCER_PROJECT_ID} \
        --format="value(state)" | grep -q "RUNNABLE"
    echo "✅ Cloud SQL 实例创建成功"
else
    echo "ℹ️  Cloud SQL 实例已存在"
fi

# 5. 启用 Private Service Connect
echo "🔗 启用 Private Service Connect..."
gcloud sql instances patch ${SQL_INSTANCE_NAME} \
    --project=${PRODUCER_PROJECT_ID} \
    --enable-private-service-connect \
    --allowed-psc-projects=${CONSUMER_PROJECT_ID}

# 6. 获取服务附件信息
echo "📋 获取服务附件信息..."
export SQL_SERVICE_ATTACHMENT=$(gcloud sql instances describe ${SQL_INSTANCE_NAME} \
    --project=${PRODUCER_PROJECT_ID} \
    --format="value(pscServiceAttachmentLink)")

echo "✅ Cloud SQL PSC 服务附件: ${SQL_SERVICE_ATTACHMENT}"

# 7. 创建应用数据库和用户
echo "👤 创建应用数据库和用户..."
gcloud sql databases create ${SQL_DATABASE_NAME} \
    --instance=${SQL_INSTANCE_NAME} \
    --project=${PRODUCER_PROJECT_ID} || true

gcloud sql users create ${SQL_USER} \
    --instance=${SQL_INSTANCE_NAME} \
    --project=${PRODUCER_PROJECT_ID} \
    --password=${SQL_USER_PASSWORD} || true

# 8. 保存配置信息
echo "💾 保存配置信息..."
cat > "$(dirname "$0")/producer-config.txt" << EOF
# Producer 项目配置信息
PRODUCER_PROJECT_ID=${PRODUCER_PROJECT_ID}
SQL_INSTANCE_NAME=${SQL_INSTANCE_NAME}
SQL_SERVICE_ATTACHMENT=${SQL_SERVICE_ATTACHMENT}
SQL_DATABASE_NAME=${SQL_DATABASE_NAME}
SQL_USER=${SQL_USER}
REGION=${REGION}
EOF

echo "🎉 Producer 项目设置完成！"
echo "📄 配置信息已保存到: $(dirname "$0")/producer-config.txt"
echo "🔗 服务附件链接: ${SQL_SERVICE_ATTACHMENT}"