#!/bin/bash
# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查必要参数
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <deployment-name> <namespace>"
    exit 1
fi

DEPLOYMENT_NAME=$1
NAMESPACE=$2
# PROJECT_ID是运行GKE Deployment的工程
PROJECT_ID=$(gcloud config get-value project)

echo -e "${BLUE}开始验证 GKE Deployment ${DEPLOYMENT_NAME} 的 KSA IAM based authentication...${NC}\n"

# 1. 获取 Deployment 使用的 ServiceAccount (KSA)
echo -e "${GREEN}1. 获取 Deployment 的 Kubernetes ServiceAccount (KSA)...${NC}"
KSA=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.serviceAccountName}')
if [ -z "$KSA" ]; then
    KSA="default"
fi
echo "Kubernetes ServiceAccount: ${KSA}"

# 2. 获取 KSA 绑定的 GCP ServiceAccount
echo -e "\n${GREEN}2. 获取 KSA 绑定的 GCP ServiceAccount...${NC}"
GCP_SA=$(kubectl get serviceaccount ${KSA} -n ${NAMESPACE} -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}')
if [ -z "$GCP_SA" ]; then
    echo "未找到绑定的 GCP ServiceAccount"
    exit 1
fi
echo "GCP ServiceAccount: ${GCP_SA}"

# 3. 拆分 GCP Service Account 获取项目信息
echo -e "\n${GREEN}3. 拆分 GCP Service Account 获取项目信息...${NC}"
# GCP SA 格式: sa-name@project-id.iam.gserviceaccount.com
SA_PROJECT_ID=$(echo ${GCP_SA} | cut -d'@' -f2 | cut -d'.' -f1)
SA_NAME=$(echo ${GCP_SA} | cut -d'@' -f1)

echo "Service Account Name: ${SA_NAME}"
echo "Service Account Project ID: ${SA_PROJECT_ID}"

# 判断是否为 IAM based authentication (跨项目)
if [ "${SA_PROJECT_ID}" != "${PROJECT_ID}" ]; then
    echo -e "${YELLOW}检测到 IAM based authentication: SA 位于不同项目${NC}"
    echo "GKE Project: ${PROJECT_ID}"
    echo "SA Project: ${SA_PROJECT_ID}"
else
    echo -e "${YELLOW}SA 位于同一项目，非 IAM based authentication${NC}"
fi

# 4. 获取 SA 在其对应项目中的 IAM 角色
echo -e "\n${GREEN}4. 检查 GCP ServiceAccount 在其项目 (${SA_PROJECT_ID}) 中的 IAM 角色...${NC}"
echo -e "${GREEN}4.1. 项目级别的 IAM 角色:${NC}"
gcloud projects get-iam-policy ${SA_PROJECT_ID} \
    --flatten="bindings[].members" \
    --format='table(bindings.role)' \
    --filter="bindings.members:${GCP_SA}"

echo -e "\n${GREEN}4.2. Service Account 级别的 IAM 策略:${NC}"
gcloud iam service-accounts get-iam-policy ${GCP_SA} --project=${SA_PROJECT_ID}

# 5. 如果是 IAM based authentication，检查跨项目权限
if [ "${SA_PROJECT_ID}" != "${PROJECT_ID}" ]; then
    echo -e "\n${GREEN}5. 检查跨项目 IAM based authentication 配置...${NC}"
    
    echo -e "${GREEN}5.1. 检查 SA 在 GKE 项目 (${PROJECT_ID}) 中的权限:${NC}"
    gcloud projects get-iam-policy ${PROJECT_ID} \
        --flatten="bindings[].members" \
        --format='table(bindings.role)' \
        --filter="bindings.members:${GCP_SA}"
    
    echo -e "\n${GREEN}5.2. 验证 Workload Identity 绑定:${NC}"
    gcloud iam service-accounts get-iam-policy ${GCP_SA} --project=${SA_PROJECT_ID} \
        --format=json | \
        jq -r '.bindings[] | select(.role=="roles/iam.workloadIdentityUser") | .members[]'
fi
: << EOF
# 6. 检查 SA 可访问的资源
echo -e "\n${GREEN}6. 检查 SA 可访问的资源...${NC}"

echo -e "${GREEN}6.1. 检查 Secret Manager 权限:${NC}"
# 在 SA 项目中查找 secrets
echo "在 SA 项目 (${SA_PROJECT_ID}) 中的 Secrets:"
gcloud secrets list --project=${SA_PROJECT_ID} --format="table(name,createTime)"

# 如果是跨项目，也检查 GKE 项目中的 secrets
if [ "${SA_PROJECT_ID}" != "${PROJECT_ID}" ]; then
    echo -e "\n在 GKE 项目 (${PROJECT_ID}) 中的 Secrets:"
    gcloud secrets list --project=${PROJECT_ID} --format="table(name,createTime)"
fi

echo -e "\n${GREEN}6.2. 检查 SA 的有效权限测试:${NC}"
echo "可以使用以下命令测试 SA 的实际权限:"
echo "gcloud auth activate-service-account --key-file=<sa-key-file>"
echo "或者在 GKE Pod 中直接测试 API 调用"

echo -e "\n${BLUE}验证完成${NC}"
echo -e "${YELLOW}总结:${NC}"
echo "- GKE Project: ${PROJECT_ID}"
echo "- SA Project: ${SA_PROJECT_ID}"
echo "- KSA: ${KSA}"
echo "- GCP SA: ${GCP_SA}"
if [ "${SA_PROJECT_ID}" != "${PROJECT_ID}" ]; then
    echo "- 认证类型: IAM based authentication (跨项目)"
else
    echo "- 认证类型: 同项目认证"
fi

EOF