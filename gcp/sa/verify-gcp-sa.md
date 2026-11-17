- script 
```bash
chmod +x verify-sa-dependencies.sh
./verify-sa-dependencies.sh your-sa@your-project.iam.gserviceaccount.com
```
- for deployment add new lables
```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 检查必要参数
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <gcp-service-account-email>"
    echo "Example: $0 my-sa@my-project.iam.gserviceaccount.com"
    exit 1
fi

GCP_SA=$1
PROJECT_ID=$(echo $GCP_SA | cut -d'@' -f2 | cut -d'.' -f1)

echo -e "${BLUE}开始检查 GCP Service Account: ${GCP_SA} 的依赖关系...${NC}\n"

# 1. 检查 SA 是否存在
echo -e "${GREEN}1. 验证 Service Account 是否存在...${NC}"
if ! gcloud iam service-accounts describe ${GCP_SA} --project=${PROJECT_ID} &>/dev/null; then
    echo -e "${RED}Service Account 不存在！${NC}"
    exit 1
fi
echo "✅ Service Account 存在"

# 2. 检查 SA 的 IAM 角色（项目级别）
echo -e "\n${GREEN}2. 检查项目级别的 IAM 角色...${NC}"
echo "项目: ${PROJECT_ID}"
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format='table(bindings.role)' \
    --filter="bindings.members:${GCP_SA}"

# 3. 检查 SA 自身的 IAM 策略（用于 Workload Identity）
echo -e "\n${GREEN}3. 检查 Service Account 的 IAM 策略（Workload Identity 绑定）...${NC}"
gcloud iam service-accounts get-iam-policy ${GCP_SA} \
    --project=${PROJECT_ID} \
    --format='table(bindings.role,bindings.members[])'

# 4. 检查关联的 Kubernetes Service Accounts
echo -e "\n${GREEN}4. 检查关联的 Kubernetes Service Accounts...${NC}"
# 获取所有命名空间
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
for ns in ${NAMESPACES}; do
    # 查找带有对应 annotation 的 KSA
    KSAs=$(kubectl get serviceaccount -n ${ns} -o json | jq -r --arg GCP_SA "${GCP_SA}" \
        '.items[] | select(.metadata.annotations."iam.gke.io/gcp-service-account" == $GCP_SA) | .metadata.name')
    if [ ! -z "$KSAs" ]; then
        for ksa in ${KSAs}; do
            echo -e "发现关联的 KSA: ${BLUE}${ksa}${NC} in namespace ${ns}"
            
            # 检查使用这个 KSA 的 Pods
            echo "检查使用该 KSA 的 Pods:"
            kubectl get pods -n ${ns} \
                --field-selector=spec.serviceAccountName=${ksa} \
                -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
                
            # 检查使用这个 KSA 的 Deployments
            echo "检查使用该 KSA 的 Deployments:"
            kubectl get deployments -n ${ns} -o json | \
                jq -r --arg KSA "$ksa" '.items[] | 
                    select(.spec.template.spec.serviceAccountName == $KSA) | 
                    .metadata.name'
        done
    fi
done

# 5. 检查 Secret Manager 相关权限
echo -e "\n${GREEN}5. 检查 Secret Manager 访问权限...${NC}"
echo "列出该 SA 可以访问的 Secrets:"
gcloud secrets list \
    --filter="NOT name:locations" \
    --format="table(name)" \
    --project=${PROJECT_ID}
# 5.1 add a new logic get-iam-policy for the secret
# 5.2 add a new logic get-iam-policy for the secret
echo "检查该 SA 可以访问的 Secret 的 IAM 策略:"
echo "please copy the secret name from the above list"
read secret
gcloud secrets get-iam-policy ${secret} \
    --project=${PROJECT_ID}

# 6. 检查其他常见资源的 IAM 绑定
echo -e "\n${GREEN}6. 检查其他资源的 IAM 绑定...${NC}"

: << END
# 检查 Cloud Storage 存储桶
echo "检查 Storage 存储桶权限:"
gsutil ls -p ${PROJECT_ID} 2>/dev/null | while read bucket; do
    gsutil iam get ${bucket} 2>/dev/null | \
        grep -q "${GCP_SA}" && echo "发现权限绑定在: ${bucket}"
done

# 检查 Cloud Run 服务
echo "检查 Cloud Run 服务权限:"
gcloud run services list --project=${PROJECT_ID} --format="table(name)" 2>/dev/null | \
while read service; do
    if [ "${service}" != "NAME" ]; then
        gcloud run services get-iam-policy ${service} --project=${PROJECT_ID} 2>/dev/null | \
            grep -q "${GCP_SA}" && echo "发现权限绑定在: ${service}"
    fi
done
END

echo -e "\n${BLUE}检查完成！${NC}"
echo -e "${RED}警告：删除此 Service Account 将影响以上所有关联的资源和服务！${NC}"
```