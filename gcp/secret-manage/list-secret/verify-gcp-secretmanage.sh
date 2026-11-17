#!/bin/bash
# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查必要参数
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <deployment-name> <namespace>"
    exit 1
fi

DEPLOYMENT_NAME=$1
NAMESPACE=$2
PROJECT_ID=$(gcloud config get-value project)

echo -e "${BLUE}开始验证 Deployment ${DEPLOYMENT_NAME} 的权限链路...${NC}\n"

# 1. 获取 Deployment 使用的 ServiceAccount
echo -e "${GREEN}1. 获取 Deployment 的 ServiceAccount...${NC}"
KSA=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.serviceAccountName}')
if [ -z "$KSA" ]; then
    KSA="default"
fi
echo "Kubernetes ServiceAccount: ${KSA}"

# 2. 获取 KSA 绑定的 GCP ServiceAccount 这就是专用的rt sa 
echo -e "\n${GREEN}2. 获取 KSA 绑定的 GCP ServiceAccount...${NC}"
GCP_SA=$(kubectl get serviceaccount ${KSA} -n ${NAMESPACE} -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}')
if [ -z "$GCP_SA" ]; then
    echo "未找到绑定的 GCP ServiceAccount"
    exit 1
fi
echo "GCP ServiceAccount: ${GCP_SA}"

# 3. 获取 GCP SA 的 IAM 角色
echo -e "\n${GREEN}3. 检查 GCP ServiceAccount 的 IAM 角色...${NC}"
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format='table(bindings.role)' \
    --filter="bindings.members:${GCP_SA}"

echo -e "\n${GREEN}list iam service account iam-policy ...${NC}"
gcloud iam service-accounts get-iam-policy ${GCP_SA} --project=${PROJECT_ID}


#reference 3. 创建RT GSA并赋予权限
#gcloud iam service-accounts create ${SPACE}-${REGION}-${API_NAME}-rt-sa \
#    --display-name="${SPACE} ${REGION} ${API_NAME} Runtime Service Account"

#gcloud projects add-iam-policy-binding ${PROJECT_ID} \
#    --member="serviceAccount:${SPACE}-${REGION}-${API_NAME}-rt-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
#    --role="roles/secretmanager.secretAccessor"

# 4. 检查 Secret Manager 权限
echo -e "\n${GREEN}4. 检查 Secret Manager 的权限...${NC}"
echo -e "\n${GREEN}4.1. 列出 Secret Manager 中的所有 Secret...${NC}"
gcloud secrets list --filter="name~${SECRET_NAME}" --format="table(name)"

echo -e "\n${GREEN}4.2 get api name...${NC}"
API_NAME_WITH_VERSION=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.metadata.labels.app}')

echo "API_NAME_WITH_VERSION: ${API_NAME_WITH_VERSION}"


# 去除版本号
API_NAME=$(echo ${API_NAME_WITH_VERSION} | sed -E 's/-[0-9]+-[0-9]+-[0-9]+$//')
echo "API name without version: ${API_NAME}"
#获取包含API_NAME的Secret名称
SECRET_NAME=$(gcloud secrets list --filter="name~${API_NAME}" --format="value(name)")

#SECRET_NAME="${KSA}-secret"
echo "查找 Secret: ${SECRET_NAME}"

# 获取 Secret 的 IAM secretmanager.secretAccessor 策略

# 1. 获取完整的 IAM 策略（默认格式）
echo "获取 Secret 的 IAM 策略"
gcloud secrets get-iam-policy ${SECRET_NAME}

# 2. 获取 JSON 格式的完整策略
echo "获取 Secret 的 JSON 格式的完整策略"
gcloud secrets get-iam-policy ${SECRET_NAME} --format=json

# 3. 获取表格格式的策略（更易读）
echo "获取 Secret 的表格格式的策略"
gcloud secrets get-iam-policy ${SECRET_NAME} --format='table(bindings.role,bindings.members[])'

echo "获取 Secret 的表格格式的策略（更易读）"
gcloud secrets get-iam-policy ${SECRET_NAME} --format=json | \
jq -r '.bindings[] | select(.role=="roles/secretmanager.secretAccessor") | .members[]'

# 5. 验证 Workload Identity 绑定
echo -e "list iam service accounts"
gcloud iam service-accounts get-iam-policy  ${GCP_SA}
echo -e "\n${GREEN}5. 验证 Workload Identity 绑定...${NC}"
gcloud iam service-accounts get-iam-policy ${GCP_SA} \
    --format=json | \
    jq -r '.bindings[] | select(.role=="roles/iam.workloadIdentityUser") | .members[]'

echo -e "\n${BLUE}验证完成${NC}"