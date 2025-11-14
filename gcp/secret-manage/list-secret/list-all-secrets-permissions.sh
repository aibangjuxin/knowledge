#!/bin/bash

################################################################################
# GCP Secret Manager 权限审计脚本
# 功能：列出项目中所有 Secret 及其绑定的 Groups 和 Service Accounts
# 使用：bash list-all-secrets-permissions.sh [project-id]
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 获取项目 ID
if [ "$#" -eq 1 ]; then
    PROJECT_ID=$1
else
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
fi

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}错误: 无法获取项目 ID${NC}"
    echo "使用方法: $0 [project-id]"
    exit 1
fi

echo "========================================="
echo -e "${BLUE}GCP Secret Manager 权限审计${NC}"
echo "========================================="
echo "项目 ID: ${PROJECT_ID}"
echo "时间: $(date)"
echo "========================================="

# 创建输出目录
OUTPUT_DIR="secret-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUTPUT_DIR}"

# 输出文件
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"
DETAIL_FILE="${OUTPUT_DIR}/details.txt"
CSV_FILE="${OUTPUT_DIR}/secrets-permissions.csv"
JSON_FILE="${OUTPUT_DIR}/secrets-permissions.json"

# 初始化 CSV 文件
echo "Secret Name,Role,Member Type,Member Email/ID,Created Time" > "${CSV_FILE}"

# 初始化 JSON 文件
echo "[" > "${JSON_FILE}"

################################################################################
# 1. 获取所有 Secret
################################################################################
echo -e "\n${GREEN}[1/4] 获取所有 Secret...${NC}"

SECRETS=$(gcloud secrets list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null)

if [ -z "$SECRETS" ]; then
    echo -e "${YELLOW}未找到任何 Secret${NC}"
    exit 0
fi

SECRET_COUNT=$(echo "$SECRETS" | wc -l | tr -d ' ')
echo -e "找到 ${CYAN}${SECRET_COUNT}${NC} 个 Secret"

################################################################################
# 2. 遍历每个 Secret 并获取权限
################################################################################
echo -e "\n${GREEN}[2/4] 分析每个 Secret 的权限...${NC}"

FIRST_SECRET=true

while IFS= read -r SECRET_NAME; do
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Secret: ${SECRET_NAME}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 获取 Secret 创建时间
    CREATE_TIME=$(gcloud secrets describe "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --format="value(createTime)" 2>/dev/null || echo "N/A")
    
    echo "创建时间: ${CREATE_TIME}"
    
    # 获取 IAM 策略
    IAM_POLICY=$(gcloud secrets get-iam-policy "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --format=json 2>/dev/null)
    
    if [ -z "$IAM_POLICY" ] || [ "$IAM_POLICY" = "{}" ]; then
        echo -e "${YELLOW}  ⚠ 未配置 IAM 策略${NC}"
        
        # 写入 CSV
        echo "\"${SECRET_NAME}\",\"N/A\",\"N/A\",\"N/A\",\"${CREATE_TIME}\"" >> "${CSV_FILE}"
        
        # 写入 JSON
        if [ "$FIRST_SECRET" = true ]; then
            FIRST_SECRET=false
        else
            echo "," >> "${JSON_FILE}"
        fi
        
        cat >> "${JSON_FILE}" << EOF
  {
    "secretName": "${SECRET_NAME}",
    "createTime": "${CREATE_TIME}",
    "bindings": []
  }
EOF
        continue
    fi
    
    # 解析 bindings
    BINDINGS=$(echo "$IAM_POLICY" | jq -c '.bindings[]?' 2>/dev/null)
    
    if [ -z "$BINDINGS" ]; then
        echo -e "${YELLOW}  ⚠ 未找到权限绑定${NC}"
        continue
    fi
    
    # 统计计数器
    GROUP_COUNT=0
    SA_COUNT=0
    USER_COUNT=0
    OTHER_COUNT=0
    
    # 写入 JSON
    if [ "$FIRST_SECRET" = true ]; then
        FIRST_SECRET=false
    else
        echo "," >> "${JSON_FILE}"
    fi
    
    echo "  {" >> "${JSON_FILE}"
    echo "    \"secretName\": \"${SECRET_NAME}\"," >> "${JSON_FILE}"
    echo "    \"createTime\": \"${CREATE_TIME}\"," >> "${JSON_FILE}"
    echo "    \"bindings\": [" >> "${JSON_FILE}"
    
    FIRST_BINDING=true
    
    # 遍历每个 binding
    while IFS= read -r BINDING; do
        ROLE=$(echo "$BINDING" | jq -r '.role')
        MEMBERS=$(echo "$BINDING" | jq -r '.members[]')
        
        echo -e "\n  ${MAGENTA}角色: ${ROLE}${NC}"
        
        # 写入 JSON binding
        if [ "$FIRST_BINDING" = true ]; then
            FIRST_BINDING=false
        else
            echo "," >> "${JSON_FILE}"
        fi
        
        echo "      {" >> "${JSON_FILE}"
        echo "        \"role\": \"${ROLE}\"," >> "${JSON_FILE}"
        echo "        \"members\": [" >> "${JSON_FILE}"
        
        FIRST_MEMBER=true
        
        # 遍历每个 member
        while IFS= read -r MEMBER; do
            # 判断 member 类型
            if [[ $MEMBER == group:* ]]; then
                MEMBER_TYPE="Group"
                MEMBER_ID="${MEMBER#group:}"
                echo -e "    ${GREEN}✓ Group:${NC} ${MEMBER_ID}"
                GROUP_COUNT=$((GROUP_COUNT + 1))
                
            elif [[ $MEMBER == serviceAccount:* ]]; then
                MEMBER_TYPE="ServiceAccount"
                MEMBER_ID="${MEMBER#serviceAccount:}"
                echo -e "    ${BLUE}✓ ServiceAccount:${NC} ${MEMBER_ID}"
                SA_COUNT=$((SA_COUNT + 1))
                
            elif [[ $MEMBER == user:* ]]; then
                MEMBER_TYPE="User"
                MEMBER_ID="${MEMBER#user:}"
                echo -e "    ${CYAN}✓ User:${NC} ${MEMBER_ID}"
                USER_COUNT=$((USER_COUNT + 1))
                
            elif [[ $MEMBER == domain:* ]]; then
                MEMBER_TYPE="Domain"
                MEMBER_ID="${MEMBER#domain:}"
                echo -e "    ${YELLOW}✓ Domain:${NC} ${MEMBER_ID}"
                OTHER_COUNT=$((OTHER_COUNT + 1))
                
            else
                MEMBER_TYPE="Other"
                MEMBER_ID="${MEMBER}"
                echo -e "    ${YELLOW}✓ Other:${NC} ${MEMBER_ID}"
                OTHER_COUNT=$((OTHER_COUNT + 1))
            fi
            
            # 写入 CSV
            echo "\"${SECRET_NAME}\",\"${ROLE}\",\"${MEMBER_TYPE}\",\"${MEMBER_ID}\",\"${CREATE_TIME}\"" >> "${CSV_FILE}"
            
            # 写入 JSON member
            if [ "$FIRST_MEMBER" = true ]; then
                FIRST_MEMBER=false
            else
                echo "," >> "${JSON_FILE}"
            fi
            
            echo "          {" >> "${JSON_FILE}"
            echo "            \"type\": \"${MEMBER_TYPE}\"," >> "${JSON_FILE}"
            echo "            \"id\": \"${MEMBER_ID}\"," >> "${JSON_FILE}"
            echo "            \"fullMember\": \"${MEMBER}\"" >> "${JSON_FILE}"
            echo -n "          }" >> "${JSON_FILE}"
            
        done <<< "$MEMBERS"
        
        echo "" >> "${JSON_FILE}"
        echo "        ]" >> "${JSON_FILE}"
        echo -n "      }" >> "${JSON_FILE}"
        
    done <<< "$BINDINGS"
    
    echo "" >> "${JSON_FILE}"
    echo "    ]," >> "${JSON_FILE}"
    echo "    \"summary\": {" >> "${JSON_FILE}"
    echo "      \"groups\": ${GROUP_COUNT}," >> "${JSON_FILE}"
    echo "      \"serviceAccounts\": ${SA_COUNT}," >> "${JSON_FILE}"
    echo "      \"users\": ${USER_COUNT}," >> "${JSON_FILE}"
    echo "      \"others\": ${OTHER_COUNT}" >> "${JSON_FILE}"
    echo "    }" >> "${JSON_FILE}"
    echo -n "  }" >> "${JSON_FILE}"
    
    # 显示统计
    echo -e "\n  ${YELLOW}统计:${NC}"
    echo "    Groups: ${GROUP_COUNT}"
    echo "    ServiceAccounts: ${SA_COUNT}"
    echo "    Users: ${USER_COUNT}"
    echo "    Others: ${OTHER_COUNT}"
    
done <<< "$SECRETS"

# 完成 JSON 文件
echo "" >> "${JSON_FILE}"
echo "]" >> "${JSON_FILE}"

################################################################################
# 3. 生成汇总报告
################################################################################
echo -e "\n${GREEN}[3/4] 生成汇总报告...${NC}"

{
    echo "========================================="
    echo "GCP Secret Manager 权限审计报告"
    echo "========================================="
    echo "项目 ID: ${PROJECT_ID}"
    echo "生成时间: $(date)"
    echo "Secret 总数: ${SECRET_COUNT}"
    echo "========================================="
    echo ""
    
    # 统计各类型成员总数
    TOTAL_GROUPS=$(grep -c ",Group," "${CSV_FILE}" || echo "0")
    TOTAL_SAS=$(grep -c ",ServiceAccount," "${CSV_FILE}" || echo "0")
    TOTAL_USERS=$(grep -c ",User," "${CSV_FILE}" || echo "0")
    TOTAL_OTHERS=$(grep -c ",Other," "${CSV_FILE}" || echo "0")
    TOTAL_DOMAINS=$(grep -c ",Domain," "${CSV_FILE}" || echo "0")
    
    echo "权限绑定统计:"
    echo "  Groups: ${TOTAL_GROUPS}"
    echo "  ServiceAccounts: ${TOTAL_SAS}"
    echo "  Users: ${TOTAL_USERS}"
    echo "  Domains: ${TOTAL_DOMAINS}"
    echo "  Others: ${TOTAL_OTHERS}"
    echo ""
    
    # 按角色统计
    echo "按角色统计:"
    tail -n +2 "${CSV_FILE}" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "  ${role_clean}: ${count}"
    done
    echo ""
    
    # 列出所有 Groups
    echo "========================================="
    echo "所有 Groups 列表:"
    echo "========================================="
    tail -n +2 "${CSV_FILE}" | grep ",Group," | cut -d',' -f3,4 | sort -u | while IFS=',' read type email; do
        email_clean=$(echo "$email" | tr -d '"')
        echo "  - ${email_clean}"
    done
    echo ""
    
    # 列出所有 ServiceAccounts
    echo "========================================="
    echo "所有 ServiceAccounts 列表:"
    echo "========================================="
    tail -n +2 "${CSV_FILE}" | grep ",ServiceAccount," | cut -d',' -f3,4 | sort -u | while IFS=',' read type email; do
        email_clean=$(echo "$email" | tr -d '"')
        echo "  - ${email_clean}"
    done
    echo ""
    
    # 按 Secret 列出详细信息
    echo "========================================="
    echo "按 Secret 详细列表:"
    echo "========================================="
    
    while IFS= read -r SECRET_NAME; do
        echo ""
        echo "Secret: ${SECRET_NAME}"
        echo "----------------------------------------"
        
        # 获取该 Secret 的所有权限
        grep "^\"${SECRET_NAME}\"," "${CSV_FILE}" | while IFS=',' read secret role type member create_time; do
            role_clean=$(echo "$role" | tr -d '"')
            type_clean=$(echo "$type" | tr -d '"')
            member_clean=$(echo "$member" | tr -d '"')
            
            if [ "$type_clean" != "N/A" ]; then
                echo "  [${role_clean}] ${type_clean}: ${member_clean}"
            fi
        done
        
    done <<< "$SECRETS"
    
} | tee "${SUMMARY_FILE}"

################################################################################
# 4. 生成 Markdown 报告
################################################################################
echo -e "\n${GREEN}[4/4] 生成 Markdown 报告...${NC}"

MARKDOWN_FILE="${OUTPUT_DIR}/report.md"

{
    echo "# GCP Secret Manager 权限审计报告"
    echo ""
    echo "**项目 ID:** \`${PROJECT_ID}\`  "
    echo "**生成时间:** $(date)  "
    echo "**Secret 总数:** ${SECRET_COUNT}"
    echo ""
    
    echo "## 📊 权限绑定统计"
    echo ""
    echo "| 类型 | 数量 |"
    echo "|------|------|"
    echo "| Groups | ${TOTAL_GROUPS} |"
    echo "| ServiceAccounts | ${TOTAL_SAS} |"
    echo "| Users | ${TOTAL_USERS} |"
    echo "| Domains | ${TOTAL_DOMAINS} |"
    echo "| Others | ${TOTAL_OTHERS} |"
    echo ""
    
    echo "## 🔑 按角色统计"
    echo ""
    echo "| 角色 | 绑定数量 |"
    echo "|------|----------|"
    tail -n +2 "${CSV_FILE}" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "| \`${role_clean}\` | ${count} |"
    done
    echo ""
    
    echo "## 👥 所有 Groups"
    echo ""
    GROUP_LIST=$(tail -n +2 "${CSV_FILE}" | grep ",Group," | cut -d',' -f4 | tr -d '"' | sort -u)
    if [ -n "$GROUP_LIST" ]; then
        while IFS= read -r group; do
            echo "- \`${group}\`"
        done <<< "$GROUP_LIST"
    else
        echo "*未找到 Groups*"
    fi
    echo ""
    
    echo "## 🤖 所有 ServiceAccounts"
    echo ""
    SA_LIST=$(tail -n +2 "${CSV_FILE}" | grep ",ServiceAccount," | cut -d',' -f4 | tr -d '"' | sort -u)
    if [ -n "$SA_LIST" ]; then
        while IFS= read -r sa; do
            echo "- \`${sa}\`"
        done <<< "$SA_LIST"
    else
        echo "*未找到 ServiceAccounts*"
    fi
    echo ""
    
    echo "## 📋 详细列表"
    echo ""
    
    while IFS= read -r SECRET_NAME; do
        echo "### Secret: \`${SECRET_NAME}\`"
        echo ""
        
        # 获取创建时间
        CREATE_TIME=$(grep "^\"${SECRET_NAME}\"," "${CSV_FILE}" | head -1 | cut -d',' -f5 | tr -d '"')
        echo "**创建时间:** ${CREATE_TIME}"
        echo ""
        
        # 检查是否有权限
        HAS_PERMISSIONS=$(grep "^\"${SECRET_NAME}\"," "${CSV_FILE}" | grep -v ",N/A," | wc -l | tr -d ' ')
        
        if [ "$HAS_PERMISSIONS" -eq 0 ]; then
            echo "*未配置 IAM 策略*"
            echo ""
            continue
        fi
        
        echo "| 角色 | 类型 | 成员 |"
        echo "|------|------|------|"
        
        grep "^\"${SECRET_NAME}\"," "${CSV_FILE}" | grep -v ",N/A," | while IFS=',' read secret role type member create_time; do
            role_clean=$(echo "$role" | tr -d '"')
            type_clean=$(echo "$type" | tr -d '"')
            member_clean=$(echo "$member" | tr -d '"')
            
            echo "| \`${role_clean}\` | ${type_clean} | \`${member_clean}\` |"
        done
        
        echo ""
        
    done <<< "$SECRETS"
    
    echo "---"
    echo ""
    echo "*报告生成于: $(date)*"
    
} > "${MARKDOWN_FILE}"

################################################################################
# 5. 生成 HTML 报告（可选）
################################################################################
HTML_FILE="${OUTPUT_DIR}/report.html"

{
    cat << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GCP Secret Manager 权限审计报告</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 {
            margin: 0 0 10px 0;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .stat-card h3 {
            margin: 0 0 10px 0;
            color: #667eea;
            font-size: 14px;
            text-transform: uppercase;
        }
        .stat-card .number {
            font-size: 32px;
            font-weight: bold;
            color: #333;
        }
        .section {
            background: white;
            padding: 25px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .section h2 {
            margin-top: 0;
            color: #667eea;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #667eea;
            color: white;
            font-weight: 600;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .badge {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge-group {
            background-color: #10.721;
            color: white;
        }
        .badge-sa {
            background-color: #3b82f6;
            color: white;
        }
        .badge-user {
            background-color: #8b5cf6;
            color: white;
        }
        .badge-other {
            background-color: #f59e0b;
            color: white;
        }
        code {
            background-color: #f3f4f6;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
        }
        .secret-item {
            margin-bottom: 30px;
            padding: 20px;
            background-color: #f9fafb;
            border-left: 4px solid #667eea;
            border-radius: 4px;
        }
        .secret-item h3 {
            margin-top: 0;
            color: #1f2937;
        }
        .no-permissions {
            color: #6b7280;
            font-style: italic;
        }
    </style>
</head>
<body>
EOF

    echo "    <div class=\"header\">"
    echo "        <h1>🔐 GCP Secret Manager 权限审计报告</h1>"
    echo "        <p><strong>项目 ID:</strong> ${PROJECT_ID}</p>"
    echo "        <p><strong>生成时间:</strong> $(date)</p>"
    echo "    </div>"
    
    echo "    <div class=\"stats\">"
    echo "        <div class=\"stat-card\">"
    echo "            <h3>Secret 总数</h3>"
    echo "            <div class=\"number\">${SECRET_COUNT}</div>"
    echo "        </div>"
    echo "        <div class=\"stat-card\">"
    echo "            <h3>Groups</h3>"
    echo "            <div class=\"number\">${TOTAL_GROUPS}</div>"
    echo "        </div>"
    echo "        <div class=\"stat-card\">"
    echo "            <h3>ServiceAccounts</h3>"
    echo "            <div class=\"number\">${TOTAL_SAS}</div>"
    echo "        </div>"
    echo "        <div class=\"stat-card\">"
    echo "            <h3>Users</h3>"
    echo "            <div class=\"number\">${TOTAL_USERS}</div>"
    echo "        </div>"
    echo "    </div>"
    
    echo "    <div class=\"section\">"
    echo "        <h2>📊 按角色统计</h2>"
    echo "        <table>"
    echo "            <thead>"
    echo "                <tr><th>角色</th><th>绑定数量</th></tr>"
    echo "            </thead>"
    echo "            <tbody>"
    tail -n +2 "${CSV_FILE}" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "                <tr><td><code>${role_clean}</code></td><td>${count}</td></tr>"
    done
    echo "            </tbody>"
    echo "        </table>"
    echo "    </div>"
    
    echo "    <div class=\"section\">"
    echo "        <h2>📋 所有 Secrets 详细列表</h2>"
    
    while IFS= read -r SECRET_NAME; do
        echo "        <div class=\"secret-item\">"
        echo "            <h3>Secret: <code>${SECRET_NAME}</code></h3>"
        
        HAS_PERMISSIONS=$(grep "^\"${SECRET_NAME}\"," "${CSV_FILE}" | grep -v ",N/A," | wc -l | tr -d ' ')
        
        if [ "$HAS_PERMISSIONS" -eq 0 ]; then
            echo "            <p class=\"no-permissions\">未配置 IAM 策略</p>"
        else
            echo "            <table>"
            echo "                <thead>"
            echo "                    <tr><th>角色</th><th>类型</th><th>成员</th></tr>"
            echo "                </thead>"
            echo "                <tbody>"
            
            grep "^\"${SECRET_NAME}\"," "${CSV_FILE}" | grep -v ",N/A," | while IFS=',' read secret role type member create_time; do
                role_clean=$(echo "$role" | tr -d '"')
                type_clean=$(echo "$type" | tr -d '"')
                member_clean=$(echo "$member" | tr -d '"')
                
                case "$type_clean" in
                    "Group")
                        badge_class="badge-group"
                        ;;
                    "ServiceAccount")
                        badge_class="badge-sa"
                        ;;
                    "User")
                        badge_class="badge-user"
                        ;;
                    *)
                        badge_class="badge-other"
                        ;;
                esac
                
                echo "                    <tr>"
                echo "                        <td><code>${role_clean}</code></td>"
                echo "                        <td><span class=\"badge ${badge_class}\">${type_clean}</span></td>"
                echo "                        <td><code>${member_clean}</code></td>"
                echo "                    </tr>"
            done
            
            echo "                </tbody>"
            echo "            </table>"
        fi
        
        echo "        </div>"
        
    done <<< "$SECRETS"
    
    echo "    </div>"
    
    echo "    <div style=\"text-align: center; color: #6b7280; margin-top: 40px;\">"
    echo "        <p>报告生成于: $(date)</p>"
    echo "    </div>"
    
    echo "</body>"
    echo "</html>"
    
} > "${HTML_FILE}"

################################################################################
# 完成
################################################################################
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}审计完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "生成的文件:"
echo "  📄 汇总报告: ${SUMMARY_FILE}"
echo "  📊 CSV 文件: ${CSV_FILE}"
echo "  📦 JSON 文件: ${JSON_FILE}"
echo "  📝 Markdown 报告: ${MARKDOWN_FILE}"
echo "  🌐 HTML 报告: ${HTML_FILE}"
echo ""
echo "输出目录: ${OUTPUT_DIR}"
echo ""
echo -e "${BLUE}提示:${NC}"
echo "  - 使用 'cat ${SUMMARY_FILE}' 查看汇总报告"
echo "  - 使用 Excel 打开 ${CSV_FILE} 进行数据分析"
echo "  - 在浏览器中打开 ${HTML_FILE} 查看可视化报告"
echo ""
