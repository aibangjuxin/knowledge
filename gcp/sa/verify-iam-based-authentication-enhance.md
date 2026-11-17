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