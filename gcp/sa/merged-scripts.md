# Shell Scripts Collection

Generated on: 2026-02-07 12:44:31
Directory: /Users/lex/git/knowledge/gcp/sa

## `verify-gce-sa.sh`

```bash
#!/bin/bash

# ==============================================================================
# Script Name: verify-gce-sa.sh
# Description: Verifies the existence, keys, and IAM roles of a GCP Service Account.
# Usage: ./verify-gce-sa.sh {sa-email}
# 1 first verify our onboarding secret manager sa at service level owner (eg: {$env}-{$region}-sm-admin-sa@{$project-id}.iam.gserviceaccount.com)
# eg : verify this onboarding sa need owner role ==> roles/iam.serviceAccountUser
# 2 project_role : roles/iam.securityReviewer
## verify project level role roles/iam.securityReviewer ==> need add onboarding sa to this role {$env}-{$region}-onboarding-sa@{$project-id}.iam.gserviceaccount.com

# Because for secret . we need using onboarding sa eg: {$env}-{$region}-onboarding-sa@{$project-id}.iam.gserviceaccount.com to trigger call secret manager sa to create a new instance 
# the secret manager sa eg: {$env}-{$region}-sm-admin-sa@{$project-id}.iam.gserviceaccount.com
# because we need using sm-admin-sa to create a new instance  ==> so sm-admin-sa need roles/iam.serviceAccountUser
# =================================
=============================================

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <sa-email>"
    echo -e "${BLUE}Example:${NC} $0 dev-us-west1-app-sa@prod-project-123.iam.gserviceaccount.com"
    exit 1
}

# --- Check Arguments ---
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Error: Missing Service Account email argument.${NC}"
    show_usage
fi

SA_EMAIL=$1

# --- Basic Validation ---
if [[ ! "$SA_EMAIL" =~ ^[^@]+@[^.]+\.iam\.gserviceaccount\.com$ ]]; then
    echo -e "${RED}Error: Invalid Service Account email format.${NC}"
    show_usage
fi

# --- Extract Info ---
SA_NAME=$(echo "$SA_EMAIL" | cut -d'@' -f1)
SA_PROJECT_ID=$(echo "$SA_EMAIL" | cut -d'@' -f2 | cut -d'.' -f1)
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   GCP Service Account Verification Tool            ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Target SA:${NC} $SA_EMAIL"
echo -e "${GREEN}Project ID:${NC} $SA_PROJECT_ID"
echo -e ""

# --- 1. Check if the SA exists ---
echo -e "${YELLOW}[1/4] Checking if Service Account exists...${NC}"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$SA_PROJECT_ID" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Service Account '$SA_EMAIL' not found in project '$SA_PROJECT_ID'.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Service Account exists.${NC}"

# --- 2. Check if the SA has any user-managed keys ---
echo -e "\n${YELLOW}[2/4] Checking for user-managed keys...${NC}"
KEYS=$(gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$SA_PROJECT_ID" --filter="keyType=USER_MANAGED" --format="table(name.basename(),validAfterTime,validBeforeTime)")

if [ -z "$(echo "$KEYS" | tail -n +2)" ]; then
    echo -e "${GREEN}✅ No user-managed keys found (Safe).${NC}"
else
    echo -e "${RED}⚠️  User-managed keys detected! (Security Risk)${NC}"
    echo "$KEYS"
fi

# --- 3. Check project-level IAM roles ---
echo -e "\n${YELLOW}[3/4] Checking project-level IAM roles...${NC}"
# Using the command provided by the user
# gcloud projects get-iam-policy {project-id} --flatten="bindings[].members" --filter="bindings.members:{sa-email}" --format="table(bindings.role)"
ROLES=$(gcloud projects get-iam-policy "$SA_PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA_EMAIL" \
    --format="table(bindings.role)" | tail -n +2)

if [ -z "$ROLES" ]; then
    echo -e "${YELLOW}⚠️  No direct project-level roles found for this SA.${NC}"
else
    echo -e "${GREEN}✅ Found roles in project '$SA_PROJECT_ID':${NC}"
    echo "$ROLES" | sed 's/^/  - /'
fi

# --- 4. Check Service Account level IAM policy (Permissions on the SA) ---
echo -e "\n${YELLOW}[4/4] Checking permissions ON this Service Account...${NC}"
SA_IAM=$(gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --project="$SA_PROJECT_ID" --format="table(bindings.role, bindings.members)" | tail -n +2)
SA_IAM_JSON=$(gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --project="$SA_PROJECT_ID" --format="json")

if [ -z "$SA_IAM" ]; then
    echo -e "${GREEN}✅ No special IAM bindings on this SA resource itself.${NC}"
else
    echo -e "${GREEN}✅ Found the following entities with access to this SA:${NC}"
    echo "$SA_IAM"
    echo -e "${GREEN}JSON format:${NC}"
    echo "$SA_IAM_JSON" | jq .
fi

# --- Cross-Project Warning ---
if [ "$SA_PROJECT_ID" != "$CURRENT_PROJECT" ]; then
    echo -e "\n${RED}Note:${NC} This SA is in project ${RED}$SA_PROJECT_ID${NC}, but your current gcloud context is ${RED}$CURRENT_PROJECT${NC}."
fi

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}   Verification Complete!                           ${NC}"
echo -e "${BLUE}====================================================${NC}"
```

## `verify-iam-based-authentication-enhance.sh`

```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 显示使用方法
show_usage() {
    echo "Usage: $0 <deployment-name> <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 my-app default"
    echo "  $0 user-service production"
    echo ""
    echo "This script verifies if the deployment uses cross-project IAM based authentication"
    exit 1
}

# 检查参数
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Error: Invalid number of arguments${NC}"
    show_usage
fi

DEPLOYMENT_NAME=$1
NAMESPACE=$2
PROJECT_ID=$(gcloud config get-value project)

echo -e "${BLUE}=== 跨项目身份认证验证脚本 ===${NC}"
echo -e "${GREEN}Deployment:${NC} $DEPLOYMENT_NAME"
echo -e "${GREEN}Namespace:${NC} $NAMESPACE"
echo -e "${GREEN}Current GKE Project:${NC} $PROJECT_ID"
echo ""

# 检查 deployment 是否存在
echo -e "${YELLOW}检查 Deployment 是否存在...${NC}"
if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo -e "${YELLOW}Available deployments in namespace '$NAMESPACE':${NC}"
    kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print "  - " $1}' || echo "  No deployments found"
    exit 1
fi
echo -e "${GREEN}✅ Deployment found${NC}"

# 1. 获取 Deployment 使用的 ServiceAccount (KSA)
echo -e "\n${YELLOW}1. 获取 Kubernetes ServiceAccount (KSA)...${NC}"
KSA=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)
if [ -z "$KSA" ]; then
    KSA="default"
    echo -e "${YELLOW}⚠️  使用默认 ServiceAccount: ${KSA}${NC}"
else
    echo -e "${GREEN}✅ ServiceAccount: ${KSA}${NC}"
fi

# 2. 检查 KSA 是否存在
echo -e "\n${YELLOW}2. 检查 KSA 是否存在...${NC}"
if ! kubectl get serviceaccount "$KSA" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ ServiceAccount '$KSA' not found in namespace '$NAMESPACE'${NC}"
    exit 1
fi
echo -e "${GREEN}✅ KSA exists${NC}"

# 3. 获取 KSA 绑定的 GCP ServiceAccount
echo -e "\n${YELLOW}3. 检查 GCP ServiceAccount 绑定...${NC}"
GCP_SA=$(kubectl get serviceaccount "$KSA" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null)

if [ -z "$GCP_SA" ]; then
    echo -e "${RED}❌ 未找到 GCP ServiceAccount 绑定${NC}"
    echo -e "${YELLOW}KSA '$KSA' 没有配置 iam.gke.io/gcp-service-account annotation${NC}"
    echo -e "${YELLOW}这意味着使用的是默认的 GKE 节点服务账户，不是 IAM based authentication${NC}"
    exit 1
fi

echo -e "${GREEN}✅ GCP ServiceAccount: ${GCP_SA}${NC}"

# 4. 拆分 GCP Service Account 获取项目信息
echo -e "\n${YELLOW}4. 分析 ServiceAccount 项目信息...${NC}"
if [[ ! "$GCP_SA" =~ ^[^@]+@[^.]+\.iam\.gserviceaccount\.com$ ]]; then
    echo -e "${RED}❌ GCP ServiceAccount 格式无效: $GCP_SA${NC}"
    exit 1
fi

SA_PROJECT_ID=$(echo "$GCP_SA" | cut -d'@' -f2 | cut -d'.' -f1)
SA_NAME=$(echo "$GCP_SA" | cut -d'@' -f1)

echo -e "${GREEN}  Service Account Name: ${SA_NAME}${NC}"
echo -e "${GREEN}  Service Account Project: ${SA_PROJECT_ID}${NC}"

# 5. 判断是否为跨项目认证
echo -e "\n${YELLOW}5. 验证跨项目认证配置...${NC}"
if [ "$SA_PROJECT_ID" != "$PROJECT_ID" ]; then
    echo -e "${GREEN}✅ 检测到 IAM based authentication (跨项目认证)${NC}"
    echo -e "${BLUE}  GKE Project: ${PROJECT_ID}${NC}"
    echo -e "${BLUE}  SA Project:  ${SA_PROJECT_ID}${NC}"
    IS_CROSS_PROJECT=true
else
    echo -e "${YELLOW}⚠️  SA 位于同一项目，非跨项目认证${NC}"
    echo -e "${YELLOW}  Project: ${PROJECT_ID}${NC}"
    IS_CROSS_PROJECT=false
fi

# 6. 验证 Workload Identity 绑定（仅跨项目时）
if [ "$IS_CROSS_PROJECT" = true ]; then
    echo -e "\n${YELLOW}6. 验证 Workload Identity 绑定...${NC}"
    
    # 检查 SA 是否存在
    if ! gcloud iam service-accounts describe "$GCP_SA" --project="$SA_PROJECT_ID" >/dev/null 2>&1; then
        echo -e "${RED}❌ GCP ServiceAccount '$GCP_SA' 在项目 '$SA_PROJECT_ID' 中不存在${NC}"
        exit 1
    fi
    
    # 检查 Workload Identity 绑定
    EXPECTED_MEMBER="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA}]"
    
    echo -e "${YELLOW}  检查 Workload Identity User 绑定...${NC}"
    WI_BINDINGS=$(gcloud iam service-accounts get-iam-policy "$GCP_SA" --project="$SA_PROJECT_ID" --format=json 2>/dev/null | \
        jq -r '.bindings[]? | select(.role=="roles/iam.workloadIdentityUser") | .members[]?' 2>/dev/null)
    
    if echo "$WI_BINDINGS" | grep -q "$EXPECTED_MEMBER"; then
        echo -e "${GREEN}✅ Workload Identity 绑定正确${NC}"
        echo -e "${GREEN}  绑定: ${EXPECTED_MEMBER}${NC}"
    else
        echo -e "${RED}❌ Workload Identity 绑定缺失或不正确${NC}"
        echo -e "${YELLOW}  期望的绑定: ${EXPECTED_MEMBER}${NC}"
        if [ -n "$WI_BINDINGS" ]; then
            echo -e "${YELLOW}  现有绑定:${NC}"
            echo "$WI_BINDINGS" | sed 's/^/    /'
        else
            echo -e "${YELLOW}  没有找到任何 Workload Identity 绑定${NC}"
        fi
        exit 1
    fi
fi

# 7. 检查 SA 权限（简化版）
echo -e "\n${YELLOW}7. 检查 ServiceAccount 权限...${NC}"
echo -e "${YELLOW}  检查项目级别 IAM 角色...${NC}"

SA_ROLES=$(gcloud projects get-iam-policy "$SA_PROJECT_ID" \
    --flatten="bindings[].members" \
    --format='value(bindings.role)' \
    --filter="bindings.members:${GCP_SA}" 2>/dev/null)

if [ -n "$SA_ROLES" ]; then
    echo -e "${GREEN}✅ ServiceAccount 在项目 '$SA_PROJECT_ID' 中有以下角色:${NC}"
    echo "$SA_ROLES" | sed 's/^/    /'
else
    echo -e "${YELLOW}⚠️  ServiceAccount 在项目级别没有直接的 IAM 角色${NC}"
fi

# 8. 生成验证报告
echo -e "\n${BLUE}=== 验证报告 ===${NC}"
echo -e "${GREEN}Deployment:${NC} $DEPLOYMENT_NAME"
echo -e "${GREEN}Namespace:${NC} $NAMESPACE"
echo -e "${GREEN}KSA:${NC} $KSA"
echo -e "${GREEN}GCP SA:${NC} $GCP_SA"
echo -e "${GREEN}GKE Project:${NC} $PROJECT_ID"
echo -e "${GREEN}SA Project:${NC} $SA_PROJECT_ID"

if [ "$IS_CROSS_PROJECT" = true ]; then
    echo -e "${GREEN}认证类型:${NC} ${GREEN}✅ IAM based authentication (跨项目认证)${NC}"
    echo -e "${GREEN}状态:${NC} ${GREEN}✅ 配置正确，支持跨项目身份认证${NC}"
else
    echo -e "${GREEN}认证类型:${NC} ${YELLOW}⚠️  同项目认证${NC}"
    echo -e "${GREEN}状态:${NC} ${YELLOW}⚠️  非跨项目认证机制${NC}"
fi

echo -e "\n${BLUE}验证完成！${NC}"

# 9. 提供后续建议
if [ "$IS_CROSS_PROJECT" = true ]; then
    echo -e "\n${YELLOW}💡 后续可以做的验证:${NC}"
    echo -e "  1. 测试实际的 API 调用权限"
    echo -e "  2. 检查具体资源的访问权限 (Secret Manager, Cloud Storage 等)"
    echo -e "  3. 使用 ephemeral 容器测试元数据服务访问:"
    echo -e "     ${BLUE}kubectl debug <pod-name> -n $NAMESPACE -it --image=curlimages/curl${NC}"
else
    echo -e "\n${YELLOW}💡 如需配置跨项目认证:${NC}"
    echo -e "  1. 在目标项目中创建 ServiceAccount"
    echo -e "  2. 配置 Workload Identity 绑定"
    echo -e "  3. 为 KSA 添加 iam.gke.io/gcp-service-account annotation"
fi
```

## `verify-gke-ksa-iam-authentication.sh`

```bash
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
```

