#!/bin/bash

################################################################################
# GCP Secret Manager - Groups 和 ServiceAccounts 快速查询
# 功能：列出每个 Secret 绑定的 Groups 和 Service Accounts
# 使用：bash list-secrets-groups-sa.sh [project-id]
################################################################################

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 获取项目 ID
PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}

if [ -z "$PROJECT_ID" ]; then
    echo "错误: 无法获取项目 ID"
    echo "使用方法: $0 [project-id]"
    exit 1
fi

echo "========================================="
echo -e "${BLUE}Secret Manager - Groups & ServiceAccounts${NC}"
echo "========================================="
echo "项目: ${PROJECT_ID}"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 获取所有 Secret
SECRETS=$(gcloud secrets list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null)

if [ -z "$SECRETS" ]; then
    echo "未找到任何 Secret"
    exit 0
fi

SECRET_COUNT=$(echo "$SECRETS" | wc -l | tr -d ' ')
echo -e "\n找到 ${CYAN}${SECRET_COUNT}${NC} 个 Secret\n"

# 创建输出文件
OUTPUT_FILE="secrets-groups-sa-$(date +%Y%m%d-%H%M%S).txt"
CSV_FILE="secrets-groups-sa-$(date +%Y%m%d-%H%M%S).csv"

# CSV 表头
echo "Secret Name,Type,Member,Role" > "${CSV_FILE}"

# 统计计数器
TOTAL_GROUPS=0
TOTAL_SAS=0
SECRETS_WITH_GROUPS=0
SECRETS_WITH_SAS=0

# 遍历每个 Secret
while IFS= read -r SECRET_NAME; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 Secret: ${SECRET_NAME}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 获取 IAM 策略
    IAM_POLICY=$(gcloud secrets get-iam-policy "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --format=json 2>/dev/null)
    
    if [ -z "$IAM_POLICY" ] || [ "$IAM_POLICY" = "{}" ]; then
        echo -e "${YELLOW}  ⚠ 未配置 IAM 策略${NC}\n"
        continue
    fi
    
    HAS_GROUP=false
    HAS_SA=false
    
    # 提取 Groups
    GROUPS=$(echo "$IAM_POLICY" | jq -r '.bindings[]? | select(.members[]? | startswith("group:")) | .role as $role | .members[] | select(startswith("group:")) | "\($role)|\(.)"' 2>/dev/null)
    
    if [ -n "$GROUPS" ]; then
        echo -e "${GREEN}  👥 Groups:${NC}"
        HAS_GROUP=true
        while IFS='|' read -r ROLE MEMBER; do
            GROUP_EMAIL="${MEMBER#group:}"
            echo "    - ${GROUP_EMAIL}"
            echo "      角色: ${ROLE}"
            echo "\"${SECRET_NAME}\",\"Group\",\"${GROUP_EMAIL}\",\"${ROLE}\"" >> "${CSV_FILE}"
            ((TOTAL_GROUPS++))
        done <<< "$GROUPS"
        echo ""
    fi
    
    # 提取 ServiceAccounts
    SAS=$(echo "$IAM_POLICY" | jq -r '.bindings[]? | select(.members[]? | startswith("serviceAccount:")) | .role as $role | .members[] | select(startswith("serviceAccount:")) | "\($role)|\(.)"' 2>/dev/null)
    
    if [ -n "$SAS" ]; then
        echo -e "${BLUE}  🤖 ServiceAccounts:${NC}"
        HAS_SA=true
        while IFS='|' read -r ROLE MEMBER; do
            SA_EMAIL="${MEMBER#serviceAccount:}"
            echo "    - ${SA_EMAIL}"
            echo "      角色: ${ROLE}"
            echo "\"${SECRET_NAME}\",\"ServiceAccount\",\"${SA_EMAIL}\",\"${ROLE}\"" >> "${CSV_FILE}"
            ((TOTAL_SAS++))
        done <<< "$SAS"
        echo ""
    fi
    
    # 更新统计
    [ "$HAS_GROUP" = true ] && ((SECRETS_WITH_GROUPS++))
    [ "$HAS_SA" = true ] && ((SECRETS_WITH_SAS++))
    
    # 如果既没有 Groups 也没有 ServiceAccounts
    if [ -z "$GROUPS" ] && [ -z "$SAS" ]; then
        echo -e "${YELLOW}  ⚠ 未找到 Groups 或 ServiceAccounts${NC}\n"
    fi
    
done <<< "$SECRETS" | tee "${OUTPUT_FILE}"

# 生成汇总
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}汇总统计${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "Secret 总数: ${SECRET_COUNT}"
echo "包含 Groups 的 Secret: ${SECRETS_WITH_GROUPS}"
echo "包含 ServiceAccounts 的 Secret: ${SECRETS_WITH_SAS}"
echo "Groups 总数: ${TOTAL_GROUPS}"
echo "ServiceAccounts 总数: ${TOTAL_SAS}"
echo ""

# 生成唯一的 Groups 列表
echo -e "${GREEN}所有唯一的 Groups:${NC}"
UNIQUE_GROUPS=$(tail -n +2 "${CSV_FILE}" | grep ",Group," | cut -d',' -f3 | tr -d '"' | sort -u)
if [ -n "$UNIQUE_GROUPS" ]; then
    echo "$UNIQUE_GROUPS" | nl
    UNIQUE_GROUP_COUNT=$(echo "$UNIQUE_GROUPS" | wc -l | tr -d ' ')
    echo "唯一 Groups 数量: ${UNIQUE_GROUP_COUNT}"
else
    echo "  (无)"
fi
echo ""

# 生成唯一的 ServiceAccounts 列表
echo -e "${GREEN}所有唯一的 ServiceAccounts:${NC}"
UNIQUE_SAS=$(tail -n +2 "${CSV_FILE}" | grep ",ServiceAccount," | cut -d',' -f3 | tr -d '"' | sort -u)
if [ -n "$UNIQUE_SAS" ]; then
    echo "$UNIQUE_SAS" | nl
    UNIQUE_SA_COUNT=$(echo "$UNIQUE_SAS" | wc -l | tr -d ' ')
    echo "唯一 ServiceAccounts 数量: ${UNIQUE_SA_COUNT}"
else
    echo "  (无)"
fi
echo ""

echo -e "${GREEN}=========================================${NC}"
echo "输出文件:"
echo "  📄 详细报告: ${OUTPUT_FILE}"
echo "  📊 CSV 文件: ${CSV_FILE}"
echo -e "${GREEN}=========================================${NC}"
