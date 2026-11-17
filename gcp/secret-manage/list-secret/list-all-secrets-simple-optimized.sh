#!/bin/bash

################################################################################
# GCP Secret Manager 权限审计脚本 - 简化最优版本
# 功能：使用最简单的方式快速审计所有 Secret
# 使用：bash list-all-secrets-simple-optimized.sh [project-id]
################################################################################

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}错误: 无法获取项目 ID${NC}"
    echo "使用方法: $0 [project-id]"
    exit 1
fi

echo "========================================="
echo -e "${BLUE}GCP Secret Manager 权限审计 (简化最优版本)${NC}"
echo "========================================="
echo "项目 ID: ${PROJECT_ID}"
echo "时间: $(date)"
echo "========================================="

OUTPUT_DIR="secret-audit-simple-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUTPUT_DIR}"
START_TIME=$(date +%s)

################################################################################
# 1. 批量获取所有 Secret 信息
################################################################################
echo -e "\n${GREEN}[1/3] 批量获取 Secret 信息...${NC}"

gcloud secrets list --project="${PROJECT_ID}" --format="json" > "${OUTPUT_DIR}/secrets-list.json"
SECRET_COUNT=$(jq '. | length' "${OUTPUT_DIR}/secrets-list.json")

if [ "$SECRET_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}未找到任何 Secret${NC}"
    exit 0
fi

echo -e "找到 ${CYAN}${SECRET_COUNT}${NC} 个 Secret"

################################################################################
# 2. 并行获取 IAM 策略
################################################################################
echo -e "\n${GREEN}[2/3] 并行获取 IAM 策略...${NC}"

get_iam_policy() {
    local SECRET_NAME=$1
    local PROJECT_ID=$2
    local OUTPUT_DIR=$3
    gcloud secrets get-iam-policy "${SECRET_NAME}" --project="${PROJECT_ID}" --format=json 2>/dev/null || echo "{}"
}

export -f get_iam_policy
export PROJECT_ID OUTPUT_DIR

jq -r '.[].name | split("/") | .[-1]' "${OUTPUT_DIR}/secrets-list.json" | \
    if command -v parallel &> /dev/null; then
        parallel --jobs 20 --bar "get_iam_policy {} $PROJECT_ID $OUTPUT_DIR > ${OUTPUT_DIR}/iam-{}.json"
    else
        xargs -P 20 -I {} bash -c "get_iam_policy {} $PROJECT_ID $OUTPUT_DIR > ${OUTPUT_DIR}/iam-{}.json"
    fi

echo -e "${GREEN}✓ IAM 策略获取完成${NC}"

################################################################################
# 3. 合并数据
################################################################################
echo -e "\n${GREEN}[3/3] 合并数据并生成报告...${NC}"

# 直接拼接 JSON
echo "[" > "${OUTPUT_DIR}/secrets-permissions.json"

jq -r '.[].name | split("/") | .[-1]' "${OUTPUT_DIR}/secrets-list.json" | {
    FIRST=true
    while read -r SECRET_NAME; do
        [ "$FIRST" = false ] && echo "," >> "${OUTPUT_DIR}/secrets-permissions.json"
        FIRST=false
        
        jq --arg name "$SECRET_NAME" --slurpfile iam "${OUTPUT_DIR}/iam-${SECRET_NAME}.json" '
            .[] | select(.name | endswith($name)) | 
            . as $info | $iam[0] as $iam |
            {
                secretName: (.name | split("/") | .[-1]),
                fullName: .name,
                createTime: .createTime,
                bindings: [$iam.bindings[]? | {role: .role, members: [.members[] | {type: (if startswith("group:") then "Group" elif startswith("serviceAccount:") then "ServiceAccount" elif startswith("user:") then "User" elif startswith("domain:") then "Domain" else "Other" end), id: (if startswith("group:") then .[6:] elif startswith("serviceAccount:") then .[15:] elif startswith("user:") then .[5:] elif startswith("domain:") then .[7:] else . end), fullMember: .}]}],
                summary: {groups: ([$iam.bindings[]?.members[]? | select(startswith("group:"))] | length), serviceAccounts: ([$iam.bindings[]?.members[]? | select(startswith("serviceAccount:"))] | length), users: ([$iam.bindings[]?.members[]? | select(startswith("user:"))] | length), others: ([$iam.bindings[]?.members[]? | select(startswith("domain:") or (startswith("group:") or startswith("serviceAccount:") or startswith("user:")) | not)] | length)}
            }
        ' "${OUTPUT_DIR}/secrets-list.json" >> "${OUTPUT_DIR}/secrets-permissions.json"
    done
}

echo "" >> "${OUTPUT_DIR}/secrets-permissions.json"
echo "]" >> "${OUTPUT_DIR}/secrets-permissions.json"

# 生成 CSV
echo "Secret Name,Role,Member Type,Member Email/ID,Created Time" > "${OUTPUT_DIR}/secrets-permissions.csv"
jq -r '.[] | .secretName as $secret | .createTime as $time | if (.bindings | length) == 0 then [$secret, "N/A", "N/A", "N/A", $time] | @csv else .bindings[] | .role as $role | .members[] | [$secret, $role, .type, .id, $time] | @csv end' "${OUTPUT_DIR}/secrets-permissions.json" >> "${OUTPUT_DIR}/secrets-permissions.csv"

# 计算统计
TOTAL_GROUPS=$(jq '[.[] | .summary.groups] | add' "${OUTPUT_DIR}/secrets-permissions.json")
TOTAL_SAS=$(jq '[.[] | .summary.serviceAccounts] | add' "${OUTPUT_DIR}/secrets-permissions.json")
TOTAL_USERS=$(jq '[.[] | .summary.users] | add' "${OUTPUT_DIR}/secrets-permissions.json")
TOTAL_OTHERS=$(jq '[.[] | .summary.others] | add' "${OUTPUT_DIR}/secrets-permissions.json")

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# 生成汇总报告
cat > "${OUTPUT_DIR}/summary.txt" << EOF
=========================================
GCP Secret Manager 权限审计报告
=========================================
项目 ID: ${PROJECT_ID}
生成时间: $(date)
Secret 总数: ${SECRET_COUNT}
处理耗时: ${ELAPSED} 秒
=========================================

权限绑定统计:
  Groups: ${TOTAL_GROUPS}
  ServiceAccounts: ${TOTAL_SAS}
  Users: ${TOTAL_USERS}
  Others: ${TOTAL_OTHERS}

EOF

# 清理临时文件
rm -f "${OUTPUT_DIR}"/iam-*.json

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}审计完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "性能统计:"
echo "  总耗时: ${ELAPSED} 秒"
echo "  平均速度: $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒/Secret"
echo ""
echo "生成的文件:"
echo "  📄 汇总报告: ${OUTPUT_DIR}/summary.txt"
echo "  📊 CSV 文件: ${OUTPUT_DIR}/secrets-permissions.csv"
echo "  📦 JSON 文件: ${OUTPUT_DIR}/secrets-permissions.json"
echo ""
echo "输出目录: ${OUTPUT_DIR}"
echo ""

cat "${OUTPUT_DIR}/summary.txt"
