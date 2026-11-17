#!/bin/bash
#
# 一键创建 Cloud SQL PSC 的跨 Region DR 链路
#
#   europe-west2:  Endpoint A  -> SA A -> Cloud SQL A (primary)   [已存在，不动]
#   europe-west1:  Endpoint B  -> SA B -> Cloud SQL B (DR 副本)   [本脚本创建]
#
# 用法：
#   export PRODUCER_PROJECT_ID=...
#   export CONSUMER_PROJECT_ID=...
#   ... 其余变量见下方默认值 ...
#   ./setup-dr-psc.sh
#
# 注意：
#   - 脚本假定 Consumer VPC 与 Producer 是跨项目的（PSC 最常见用法）
#   - Consumer VPC 需要在 europe-west1 已有一个"普通子网"用于分配 Endpoint IP
#   - 本脚本只创建 endpoint 侧资源；Cloud SQL 副本关系请用 gcloud sql instances create --master-instance-name 另行建立

set -euo pipefail

# ============ 默认参数（可用环境变量覆盖）============
export PRODUCER_PROJECT_ID="${PRODUCER_PROJECT_ID:-your-db-project}"
export CONSUMER_PROJECT_ID="${CONSUMER_PROJECT_ID:-your-app-project}"
export CONSUMER_VPC="${CONSUMER_VPC:-app-vpc}"

export REGION_A="${REGION_A:-europe-west2}"
export REGION_B="${REGION_B:-europe-west1}"

export SQL_B="${SQL_B:-sql-dr-euw1}"
export SQL_B_VERSION="${SQL_B_VERSION:-MYSQL_8_0}"
export SQL_B_TIER="${SQL_B_TIER:-db-n-2}"

export EP_B_NAME="${EP_B_NAME:-sql-psc-ep-b}"
export EP_B_IP_NAME="${EP_B_IP_NAME:-sql-psc-ip-b}"
export EP_B_SUBNET="${EP_B_SUBNET:-psc-dr-subnet-europe-west1}"
export EP_B_SUBNET_CIDR="${EP_B_SUBNET_CIDR:-10.9.0.0/24}"

export DB_PORT="${DB_PORT:-3306}"

echo "=============================================="
echo " PSC 跨 Region DR 链路创建"
echo "   Producer : ${PRODUCER_PROJECT_ID} (${REGION_B})"
echo "   Consumer : ${CONSUMER_PROJECT_ID} (${REGION_B})"
echo "=============================================="

# ============ 1. Producer：创建 DR 实例 ============
if gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} >/dev/null 2>&1; then
  echo "ℹ️  Cloud SQL ${SQL_B} 已存在，跳过创建"
else
  echo "▶️  创建 Cloud SQL ${SQL_B} (${REGION_B})..."
  gcloud sql instances create ${SQL_B} \
    --project=${PRODUCER_PROJECT_ID} \
    --region=${REGION_B} \
    --database-version=${SQL_B_VERSION} \
    --tier=${SQL_B_TIER} \
    --availability-type=REGIONAL \
    --enable-private-service-connect \
    --allowed-psc-projects=${CONSUMER_PROJECT_ID} \
    --no-assign-ip \
    --enable-bin-log
fi

# ============ 2. Producer：确保 allowed consumer projects 包含 APP 项目 ============
echo "▶️  确认 allowedConsumerProjects 包含 ${CONSUMER_PROJECT_ID}..."
gcloud sql instances patch ${SQL_B} \
  --project=${PRODUCER_PROJECT_ID} \
  --allowed-psc-projects=${CONSUMER_PROJECT_ID} >/dev/null

# ============ 3. 取 SA B 的 URI ============
export SA_B=$(gcloud sql instances describe ${SQL_B} \
  --project=${PRODUCER_PROJECT_ID} \
  --format="value(pscServiceAttachmentLink)")

if [[ -z "${SA_B}" || "${SA_B}" == "None" ]]; then
  echo "❌ 未能获取 Service Attachment URI，请确认实例已开启 PSC 且已就绪"
  exit 1
fi
echo "   SA B = ${SA_B}"

# ============ 4. Consumer：europe-west1 普通子网（放 Endpoint IP）============
if gcloud compute networks subnets describe ${EP_B_SUBNET} \
    --project=${CONSUMER_PROJECT_ID} --region=${REGION_B} >/dev/null 2>&1; then
  echo "ℹ️  子网 ${EP_B_SUBNET} 已存在"
else
  echo "▶️  创建普通子网 ${EP_B_SUBNET} (${REGION_B}) ${EP_B_SUBNET_CIDR}..."
  gcloud compute networks subnets create ${EP_B_SUBNET} \
    --project=${CONSUMER_PROJECT_ID} \
    --network=${CONSUMER_VPC} \
    --region=${REGION_B} \
    --range=${EP_B_SUBNET_CIDR}
fi

# ============ 5. Consumer：Static IP ============
if gcloud compute addresses describe ${EP_B_IP_NAME} \
    --project=${CONSUMER_PROJECT_ID} --region=${REGION_B} >/dev/null 2>&1; then
  echo "ℹ️  Static IP ${EP_B_IP_NAME} 已存在"
else
  echo "▶️  创建 Static IP ${EP_B_IP_NAME}..."
  gcloud compute addresses create ${EP_B_IP_NAME} \
    --project=${CONSUMER_PROJECT_ID} \
    --region=${REGION_B} \
    --subnet=${EP_B_SUBNET}
fi

# ============ 6. Consumer：Endpoint B（--allow-psc-global-access 是关键）============
if gcloud compute forwarding-rules describe ${EP_B_NAME} \
    --project=${CONSUMER_PROJECT_ID} --region=${REGION_B} >/dev/null 2>&1; then
  echo "ℹ️  Endpoint ${EP_B_NAME} 已存在，尝试开启 global access..."
  gcloud compute forwarding-rules update ${EP_B_NAME} \
    --project=${CONSUMER_PROJECT_ID} \
    --region=${REGION_B} \
    --allow-psc-global-access >/dev/null
else
  echo "▶️  创建 Endpoint ${EP_B_NAME} (--allow-psc-global-access)..."
  gcloud compute forwarding-rules create ${EP_B_NAME} \
    --project=${CONSUMER_PROJECT_ID} \
    --region=${REGION_B} \
    --network=${CONSUMER_VPC} \
    --address=${EP_B_IP_NAME} \
    --target-service-attachment=${SA_B} \
    --allow-psc-global-access
fi

# ============ 7. Consumer：出站防火墙规则 ============
EP_B_IP=$(gcloud compute addresses describe ${EP_B_IP_NAME} \
  --project=${CONSUMER_PROJECT_ID} --region=${REGION_B} \
  --format="value(address)")
echo "   Endpoint B IP = ${EP_B_IP}"

if gcloud compute firewall-rules describe allow-sql-psc-dr-egress \
    --project=${CONSUMER_PROJECT_ID} >/dev/null 2>&1; then
  echo "ℹ️  防火墙规则 allow-sql-psc-dr-egress 已存在，更新目标..."
  gcloud compute firewall-rules update allow-sql-psc-dr-egress \
    --project=${CONSUMER_PROJECT_ID} \
    --destination-ranges=${EP_B_IP}/32 >/dev/null
else
  echo "▶️  创建出站防火墙规则 allow-sql-psc-dr-egress..."
  gcloud compute firewall-rules create allow-sql-psc-dr-egress \
    --project=${CONSUMER_PROJECT_ID} \
    --network=${CONSUMER_VPC} \
    --direction=EGRESS \
    --destination-ranges=${EP_B_IP}/32 \
    --action=ALLOW \
    --rules=tcp:${DB_PORT}
fi

# ============ 8. 输出校验摘要 ============
echo ""
echo "✅ 创建完成，请运行 verify-dr-psc.sh 校验"
echo "   Endpoint B IP = ${EP_B_IP}"
echo "   下一步：把 APP 的 DB_HOST 切到 ${EP_B_IP}（或改 DNS 记录）"
