#!/bin/bash

################################################################################
# GCP Secret Manager 权限审计脚本 - 最优化版本
# 功能：使用批量 API 调用和智能缓存快速审计所有 Secret
# 特点：
#   1. 批量获取所有 Secret 的 IAM 策略（一次性）
#   2. 使用 jq 进行高效的 JSON 处理
#   3. 最小化 API 调用次数
#   4. 内存友好的流式处理
# 使用：bash list-all-secrets-optimized.sh [project-id]
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 获取项目 ID
PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}错误: 无法获取项目 ID${NC}"
    echo "使用方法: $0 [project-id]"
    exit 1
fi

echo "========================================="
echo -e "${BLUE}GCP Secret Manager 权限审计 (最优化版本)${NC}"
echo "========================================="
echo "项目 ID: ${PROJECT_ID}"
echo "时间: $(date)"
echo "========================================="

# 创建输出目录
OUTPUT_DIR="secret-audit-optimized-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUTPUT_DIR}"

START_TIME=$(date +%s)

################################################################################
# 1. 批量获取所有 Secret 信息
################################################################################
echo -e "\n${GREEN}[1/4] 批量获取 Secret 信息...${NC}"

# 一次性获取所有 Secret 的基本信息（包括创建时间）
gcloud secrets list \
    --project="${PROJECT_ID}" \
    --format="json" > "${OUTPUT_DIR}/secrets-list.json"

SECRET_COUNT=$(jq '. | length' "${OUTPUT_DIR}/secrets-list.json")

if [ "$SECRET_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}未找到任何 Secret${NC}"
    exit 0
fi

echo -e "找到 ${CYAN}${SECRET_COUNT}${NC} 个 Secret"

################################################################################
# 2. 批量获取 IAM 策略（使用并行处理）
################################################################################
echo -e "\n${GREEN}[2/4] 批量获取 IAM 策略...${NC}"

# 提取 Secret 名称列表
jq -r '.[].name | split("/") | .[-1]' "${OUTPUT_DIR}/secrets-list.json" > "${OUTPUT_DIR}/secret-names.txt"

# 定义批量获取 IAM 策略的函数
get_iam_policy() {
    local SECRET_NAME=$1
    local PROJECT_ID=$2
    local OUTPUT_DIR=$3
    
    gcloud secrets get-iam-policy "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --format=json 2>/dev/null > "${OUTPUT_DIR}/iam-${SECRET_NAME}.json" || echo "{}" > "${OUTPUT_DIR}/iam-${SECRET_NAME}.json"
}

export -f get_iam_policy
export PROJECT_ID
export OUTPUT_DIR

# 使用并行处理获取所有 IAM 策略
if command -v parallel &> /dev/null; then
    cat "${OUTPUT_DIR}/secret-names.txt" | parallel --jobs 20 --bar get_iam_policy {} "$PROJECT_ID" "$OUTPUT_DIR"
else
    cat "${OUTPUT_DIR}/secret-names.txt" | xargs -P 20 -I {} bash -c 'get_iam_policy "$@"' _ {} "$PROJECT_ID" "$OUTPUT_DIR"
fi

echo -e "${GREEN}✓ IAM 策略获取完成${NC}"

################################################################################
# 3. 合并数据并生成统一的 JSON
################################################################################
echo -e "\n${GREEN}[3/4] 处理和合并数据...${NC}"

# 创建临时目录存储处理后的数据
TEMP_PROCESSED="${OUTPUT_DIR}/processed"
mkdir -p "${TEMP_PROCESSED}"

# 处理每个 Secret 并合并数据
jq -r '.[].name | split("/") | .[-1]' "${OUTPUT_DIR}/secrets-list.json" | while read -r SECRET_NAME; do
    # 获取 Secret 的基本信息
    jq --arg name "$SECRET_NAME" '.[] | select(.name | endswith($name))' "${OUTPUT_DIR}/secrets-list.json" > "${TEMP_PROCESSED}/${SECRET_NAME}-info.json"
    
    # 获取 IAM 策略
    IAM_FILE="${OUTPUT_DIR}/iam-${SECRET_NAME}.json"
    
    if [ -f "$IAM_FILE" ] && [ -s "$IAM_FILE" ]; then
        cp "$IAM_FILE" "${TEMP_PROCESSED}/${SECRET_NAME}-iam.json"
    else
        echo '{}' > "${TEMP_PROCESSED}/${SECRET_NAME}-iam.json"
    fi
    
    # 使用外部 jq 脚本处理并合并数据
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    jq -s -f "${SCRIPT_DIR}/merge-secret-data.jq" \
        "${TEMP_PROCESSED}/${SECRET_NAME}-info.json" \
        "${TEMP_PROCESSED}/${SECRET_NAME}-iam.json" > "${TEMP_PROCESSED}/${SECRET_NAME}-final.json"
done

# 合并所有处理后的 JSON
jq -s '.' "${TEMP_PROCESSED}"/*-final.json > "${OUTPUT_DIR}/secrets-permissions.json"

# 清理临时文件
rm -rf "${TEMP_PROCESSED}"
rm -f "${OUTPUT_DIR}"/iam-*.json "${OUTPUT_DIR}/secret-names.txt

################################################################################
# 4. 生成输出文件
################################################################################
echo -e "\n${GREEN}[4/4] 生成报告...${NC}"

# 生成 CSV 文件
echo "Secret Name,Role,Member Type,Member Email/ID,Created Time" > "${OUTPUT_DIR}/secrets-permissions.csv"

jq -r '
  .[] | 
  .secretName as $secret |
  .createTime as $time |
  if (.bindings | length) == 0 then
    [$secret, "N/A", "N/A", "N/A", $time] | @csv
  else
    .bindings[] | 
    .role as $role |
    .members[] |
    [$secret, $role, .type, .id, $time] | @csv
  end
' "${OUTPUT_DIR}/secrets-permissions.json" >> "${OUTPUT_DIR}/secrets-permissions.csv"

# 计算统计信息
TOTAL_GROUPS=$(jq '[.[] | .summary.groups] | add' "${OUTPUT_DIR}/secrets-permissions.json")
TOTAL_SAS=$(jq '[.[] | .summary.serviceAccounts] | add' "${OUTPUT_DIR}/secrets-permissions.json")
TOTAL_USERS=$(jq '[.[] | .summary.users] | add' "${OUTPUT_DIR}/secrets-permissions.json")
TOTAL_OTHERS=$(jq '[.[] | .summary.others] | add' "${OUTPUT_DIR}/secrets-permissions.json")

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# 生成汇总报告
{
    echo "========================================="
    echo "GCP Secret Manager 权限审计报告 (最优化版本)"
    echo "========================================="
    echo "项目 ID: ${PROJECT_ID}"
    echo "生成时间: $(date)"
    echo "Secret 总数: ${SECRET_COUNT}"
    echo "处理耗时: ${ELAPSED} 秒"
    echo "========================================="
    echo ""
    
    echo "权限绑定统计:"
    echo "  Groups: ${TOTAL_GROUPS}"
    echo "  ServiceAccounts: ${TOTAL_SAS}"
    echo "  Users: ${TOTAL_USERS}"
    echo "  Others: ${TOTAL_OTHERS}"
    echo ""
    
    echo "按角色统计:"
    tail -n +2 "${OUTPUT_DIR}/secrets-permissions.csv" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "  ${role_clean}: ${count}"
    done
    echo ""
    
    echo "所有 Groups 列表:"
    jq -r '.[] | .bindings[]?.members[]? | select(.type == "Group") | .id' "${OUTPUT_DIR}/secrets-permissions.json" | sort -u | while read group; do
        echo "  - ${group}"
    done
    echo ""
    
    echo "所有 ServiceAccounts 列表:"
    jq -r '.[] | .bindings[]?.members[]? | select(.type == "ServiceAccount") | .id' "${OUTPUT_DIR}/secrets-permissions.json" | sort -u | while read sa; do
        echo "  - ${sa}"
    done
    echo ""
    
    echo "性能统计:"
    echo "  总耗时: ${ELAPSED} 秒"
    echo "  平均每个 Secret: $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒"
    echo "  吞吐量: $(echo "scale=2; $SECRET_COUNT / $ELAPSED" | bc) Secret/秒"
    echo ""
    
} | tee "${OUTPUT_DIR}/summary.txt"

# 生成 Markdown 报告
{
    echo "# GCP Secret Manager 权限审计报告 (最优化版本)"
    echo ""
    echo "**项目 ID:** \`${PROJECT_ID}\`  "
    echo "**生成时间:** $(date)  "
    echo "**Secret 总数:** ${SECRET_COUNT}  "
    echo "**处理耗时:** ${ELAPSED} 秒"
    echo ""
    
    echo "## 📊 权限绑定统计"
    echo ""
    echo "| 类型 | 数量 |"
    echo "|------|------|"
    echo "| Groups | ${TOTAL_GROUPS} |"
    echo "| ServiceAccounts | ${TOTAL_SAS} |"
    echo "| Users | ${TOTAL_USERS} |"
    echo "| Others | ${TOTAL_OTHERS} |"
    echo ""
    
    echo "## 🔑 按角色统计"
    echo ""
    echo "| 角色 | 绑定数量 |"
    echo "|------|----------|"
    tail -n +2 "${OUTPUT_DIR}/secrets-permissions.csv" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "| \`${role_clean}\` | ${count} |"
    done
    echo ""
    
    echo "## 👥 所有 Groups"
    echo ""
    GROUP_LIST=$(jq -r '.[] | .bindings[]?.members[]? | select(.type == "Group") | .id' "${OUTPUT_DIR}/secrets-permissions.json" | sort -u)
    if [ -n "$GROUP_LIST" ]; then
        echo "$GROUP_LIST" | while read group; do
            echo "- \`${group}\`"
        done
    else
        echo "*未找到 Groups*"
    fi
    echo ""
    
    echo "## 🤖 所有 ServiceAccounts"
    echo ""
    SA_LIST=$(jq -r '.[] | .bindings[]?.members[]? | select(.type == "ServiceAccount") | .id' "${OUTPUT_DIR}/secrets-permissions.json" | sort -u)
    if [ -n "$SA_LIST" ]; then
        echo "$SA_LIST" | while read sa; do
            echo "- \`${sa}\`"
        done
    else
        echo "*未找到 ServiceAccounts*"
    fi
    echo ""
    
    echo "## ⚡ 性能统计"
    echo ""
    echo "| 指标 | 值 |"
    echo "|------|-----|"
    echo "| 总耗时 | ${ELAPSED} 秒 |"
    echo "| 平均每个 Secret | $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒 |"
    echo "| 吞吐量 | $(echo "scale=2; $SECRET_COUNT / $ELAPSED" | bc) Secret/秒 |"
    echo ""
    
} > "${OUTPUT_DIR}/report.md"

# 生成 HTML 报告
{
    cat << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GCP Secret Manager 权限审计报告 (最优化版本)</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
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
        .header h1 { margin: 0 0 10px 0; }
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
        tr:hover { background-color: #f5f5f5; }
        code {
            background-color: #f3f4f6;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
        }
        .performance {
            background: #f0fdf4;
            border-left: 4px solid #10.721;
            padding: 15px;
            margin: 20px 0;
            border-radius: 4px;
        }
        .performance h3 {
            margin-top: 0;
            color: #10.721;
        }
    </style>
</head>
<body>
EOF

    echo "    <div class=\"header\">"
    echo "        <h1>🔐 GCP Secret Manager 权限审计报告</h1>"
    echo "        <p><strong>项目 ID:</strong> ${PROJECT_ID}</p>"
    echo "        <p><strong>生成时间:</strong> $(date)</p>"
    echo "        <p><strong>版本:</strong> 最优化版本</p>"
    echo "    </div>"
    
    echo "    <div class=\"stats\">"
    echo "        <div class=\"stat-card\"><h3>Secret 总数</h3><div class=\"number\">${SECRET_COUNT}</div></div>"
    echo "        <div class=\"stat-card\"><h3>Groups</h3><div class=\"number\">${TOTAL_GROUPS}</div></div>"
    echo "        <div class=\"stat-card\"><h3>ServiceAccounts</h3><div class=\"number\">${TOTAL_SAS}</div></div>"
    echo "        <div class=\"stat-card\"><h3>Users</h3><div class=\"number\">${TOTAL_USERS}</div></div>"
    echo "    </div>"
    
    echo "    <div class=\"performance\">"
    echo "        <h3>⚡ 性能统计</h3>"
    echo "        <p><strong>处理耗时:</strong> ${ELAPSED} 秒</p>"
    echo "        <p><strong>平均速度:</strong> $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒/Secret</p>"
    echo "        <p><strong>吞吐量:</strong> $(echo "scale=2; $SECRET_COUNT / $ELAPSED" | bc) Secret/秒</p>"
    echo "    </div>"
    
    echo "    <div class=\"section\">"
    echo "        <h2>📊 按角色统计</h2>"
    echo "        <table><thead><tr><th>角色</th><th>绑定数量</th></tr></thead><tbody>"
    tail -n +2 "${OUTPUT_DIR}/secrets-permissions.csv" | cut -d',' -f2 | sort | uniq -c | sort -rn | head -20 | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "                <tr><td><code>${role_clean}</code></td><td>${count}</td></tr>"
    done
    echo "            </tbody></table></div>"
    
    echo "    <div style=\"text-align: center; color: #6b7280; margin-top: 40px;\">"
    echo "        <p>报告生成于: $(date)</p>"
    echo "    </div>"
    echo "</body></html>"
    
} > "${OUTPUT_DIR}/report.html"

################################################################################
# 完成
################################################################################
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}审计完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "性能统计:"
echo "  总耗时: ${ELAPSED} 秒"
echo "  平均速度: $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒/Secret"
echo "  吞吐量: $(echo "scale=2; $SECRET_COUNT / $ELAPSED" | bc) Secret/秒"
echo ""
echo "生成的文件:"
echo "  📄 汇总报告: ${OUTPUT_DIR}/summary.txt"
echo "  📊 CSV 文件: ${OUTPUT_DIR}/secrets-permissions.csv"
echo "  📦 JSON 文件: ${OUTPUT_DIR}/secrets-permissions.json"
echo "  📝 Markdown 报告: ${OUTPUT_DIR}/report.md"
echo "  🌐 HTML 报告: ${OUTPUT_DIR}/report.html"
echo ""
echo "输出目录: ${OUTPUT_DIR}"
echo ""
