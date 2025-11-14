#!/bin/bash

################################################################################
# GCP Secret Manager 权限审计脚本 - 并行版本
# 功能：使用并行处理快速列出项目中所有 Secret 及其权限
# 使用：bash list-all-secrets-permissions-parallel.sh [project-id] [parallel-jobs]
# 性能：对于 350 个 Secret，速度提升约 10-20 倍
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
if [ "$#" -ge 1 ]; then
    PROJECT_ID=$1
else
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
fi

# 获取并行任务数（默认 20）
PARALLEL_JOBS=${2:-20}

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}错误: 无法获取项目 ID${NC}"
    echo "使用方法: $0 [project-id] [parallel-jobs]"
    echo "示例: $0 my-project 20"
    exit 1
fi

# 检查是否安装了 GNU parallel
if ! command -v parallel &> /dev/null; then
    echo -e "${YELLOW}警告: 未安装 GNU parallel，将使用 xargs 并行处理${NC}"
    echo "提示: 安装 GNU parallel 可获得更好的性能和进度显示"
    echo "  macOS: brew install parallel"
    echo "  Ubuntu: sudo apt-get install parallel"
    USE_XARGS=true
else
    USE_XARGS=false
fi

echo "========================================="
echo -e "${BLUE}GCP Secret Manager 权限审计 (并行版本)${NC}"
echo "========================================="
echo "项目 ID: ${PROJECT_ID}"
echo "并行任务数: ${PARALLEL_JOBS}"
echo "时间: $(date)"
echo "========================================="

# 创建输出目录
OUTPUT_DIR="secret-audit-parallel-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUTPUT_DIR}"
TEMP_DIR="${OUTPUT_DIR}/temp"
mkdir -p "${TEMP_DIR}"

# 输出文件
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"
CSV_FILE="${OUTPUT_DIR}/secrets-permissions.csv"
JSON_FILE="${OUTPUT_DIR}/secrets-permissions.json"
MARKDOWN_FILE="${OUTPUT_DIR}/report.md"
HTML_FILE="${OUTPUT_DIR}/report.html"

# 初始化 CSV 文件
echo "Secret Name,Role,Member Type,Member Email/ID,Created Time" > "${CSV_FILE}"

################################################################################
# 1. 获取所有 Secret
################################################################################
echo -e "\n${GREEN}[1/5] 获取所有 Secret...${NC}"

SECRETS=$(gcloud secrets list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null)

if [ -z "$SECRETS" ]; then
    echo -e "${YELLOW}未找到任何 Secret${NC}"
    exit 0
fi

SECRET_COUNT=$(echo "$SECRETS" | wc -l | tr -d ' ')
echo -e "找到 ${CYAN}${SECRET_COUNT}${NC} 个 Secret"

# 将 Secret 列表保存到文件
echo "$SECRETS" > "${TEMP_DIR}/secrets.txt"

################################################################################
# 2. 定义处理单个 Secret 的函数
################################################################################

# 导出函数和变量供并行使用
export PROJECT_ID
export TEMP_DIR

process_secret() {
    local SECRET_NAME=$1
    local OUTPUT_FILE="${TEMP_DIR}/${SECRET_NAME}.json"
    
    # 获取 Secret 创建时间
    CREATE_TIME=$(gcloud secrets describe "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --format="value(createTime)" 2>/dev/null || echo "N/A")
    
    # 获取 IAM 策略
    IAM_POLICY=$(gcloud secrets get-iam-policy "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --format=json 2>/dev/null)
    
    # 构建 JSON 输出
    if [ -z "$IAM_POLICY" ] || [ "$IAM_POLICY" = "{}" ]; then
        # 无 IAM 策略
        cat > "${OUTPUT_FILE}" << EOF
{
  "secretName": "${SECRET_NAME}",
  "createTime": "${CREATE_TIME}",
  "bindings": [],
  "summary": {
    "groups": 0,
    "serviceAccounts": 0,
    "users": 0,
    "others": 0
  }
}
EOF
    else
        # 有 IAM 策略，解析并统计
        echo "$IAM_POLICY" | jq --arg name "$SECRET_NAME" --arg time "$CREATE_TIME" '
        {
          secretName: $name,
          createTime: $time,
          bindings: [
            .bindings[]? | {
              role: .role,
              members: [
                .members[]? | {
                  type: (
                    if startswith("group:") then "Group"
                    elif startswith("serviceAccount:") then "ServiceAccount"
                    elif startswith("user:") then "User"
                    elif startswith("domain:") then "Domain"
                    else "Other"
                    end
                  ),
                  id: (
                    if startswith("group:") then .[6:]
                    elif startswith("serviceAccount:") then .[15:]
                    elif startswith("user:") then .[5:]
                    elif startswith("domain:") then .[7:]
                    else .
                    end
                  ),
                  fullMember: .
                }
              ]
            }
          ],
          summary: {
            groups: ([.bindings[]?.members[]? | select(startswith("group:"))] | length),
            serviceAccounts: ([.bindings[]?.members[]? | select(startswith("serviceAccount:"))] | length),
            users: ([.bindings[]?.members[]? | select(startswith("user:"))] | length),
            others: ([.bindings[]?.members[]? | select(startswith("domain:") or (startswith("group:") or startswith("serviceAccount:") or startswith("user:")) | not)] | length)
          }
        }
        ' > "${OUTPUT_FILE}"
    fi
}

export -f process_secret

################################################################################
# 3. 并行处理所有 Secret
################################################################################
echo -e "\n${GREEN}[2/5] 并行分析 Secret 权限...${NC}"
echo "使用 ${PARALLEL_JOBS} 个并行任务"

START_TIME=$(date +%s)

if [ "$USE_XARGS" = true ]; then
    # 使用 xargs 并行处理
    cat "${TEMP_DIR}/secrets.txt" | xargs -P "${PARALLEL_JOBS}" -I {} bash -c 'process_secret "$@"' _ {}
else
    # 使用 GNU parallel 并行处理（带进度条）
    cat "${TEMP_DIR}/secrets.txt" | parallel --jobs "${PARALLEL_JOBS}" --bar process_secret {}
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo -e "${GREEN}✓ 完成！耗时: ${ELAPSED} 秒${NC}"
echo "平均每个 Secret: $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒"

################################################################################
# 4. 合并结果
################################################################################
echo -e "\n${GREEN}[3/5] 合并结果...${NC}"

# 合并所有 JSON 文件
echo "[" > "${JSON_FILE}"
FIRST=true
for json_file in "${TEMP_DIR}"/*.json; do
    if [ -f "$json_file" ]; then
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "${JSON_FILE}"
        fi
        cat "$json_file" >> "${JSON_FILE}"
    fi
done
echo "]" >> "${JSON_FILE}"

# 从 JSON 生成 CSV
echo -e "${GREEN}生成 CSV 文件...${NC}"
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
' "${JSON_FILE}" >> "${CSV_FILE}"

################################################################################
# 5. 生成报告
################################################################################
echo -e "\n${GREEN}[4/5] 生成报告...${NC}"

# 统计各类型成员总数
TOTAL_GROUPS=$(jq '[.[] | .summary.groups] | add' "${JSON_FILE}")
TOTAL_SAS=$(jq '[.[] | .summary.serviceAccounts] | add' "${JSON_FILE}")
TOTAL_USERS=$(jq '[.[] | .summary.users] | add' "${JSON_FILE}")
TOTAL_OTHERS=$(jq '[.[] | .summary.others] | add' "${JSON_FILE}")

# 生成汇总报告
{
    echo "========================================="
    echo "GCP Secret Manager 权限审计报告 (并行版本)"
    echo "========================================="
    echo "项目 ID: ${PROJECT_ID}"
    echo "生成时间: $(date)"
    echo "Secret 总数: ${SECRET_COUNT}"
    echo "处理耗时: ${ELAPSED} 秒"
    echo "并行任务数: ${PARALLEL_JOBS}"
    echo "========================================="
    echo ""
    
    echo "权限绑定统计:"
    echo "  Groups: ${TOTAL_GROUPS}"
    echo "  ServiceAccounts: ${TOTAL_SAS}"
    echo "  Users: ${TOTAL_USERS}"
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
    jq -r '.[] | .bindings[]?.members[]? | select(.type == "Group") | .id' "${JSON_FILE}" | sort -u | while read group; do
        echo "  - ${group}"
    done
    echo ""
    
    # 列出所有 ServiceAccounts
    echo "========================================="
    echo "所有 ServiceAccounts 列表:"
    echo "========================================="
    jq -r '.[] | .bindings[]?.members[]? | select(.type == "ServiceAccount") | .id' "${JSON_FILE}" | sort -u | while read sa; do
        echo "  - ${sa}"
    done
    echo ""
    
    # 性能统计
    echo "========================================="
    echo "性能统计:"
    echo "========================================="
    echo "总耗时: ${ELAPSED} 秒"
    echo "平均每个 Secret: $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒"
    echo "吞吐量: $(echo "scale=2; $SECRET_COUNT / $ELAPSED" | bc) Secret/秒"
    echo ""
    
} | tee "${SUMMARY_FILE}"

# 生成 Markdown 报告
{
    echo "# GCP Secret Manager 权限审计报告 (并行版本)"
    echo ""
    echo "**项目 ID:** \`${PROJECT_ID}\`  "
    echo "**生成时间:** $(date)  "
    echo "**Secret 总数:** ${SECRET_COUNT}  "
    echo "**处理耗时:** ${ELAPSED} 秒  "
    echo "**并行任务数:** ${PARALLEL_JOBS}"
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
    tail -n +2 "${CSV_FILE}" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "| \`${role_clean}\` | ${count} |"
    done
    echo ""
    
    echo "## 👥 所有 Groups"
    echo ""
    GROUP_LIST=$(jq -r '.[] | .bindings[]?.members[]? | select(.type == "Group") | .id' "${JSON_FILE}" | sort -u)
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
    SA_LIST=$(jq -r '.[] | .bindings[]?.members[]? | select(.type == "ServiceAccount") | .id' "${JSON_FILE}" | sort -u)
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
    echo "| 并行任务数 | ${PARALLEL_JOBS} |"
    echo ""
    
    echo "## 📋 详细列表"
    echo ""
    echo "> 提示: 由于 Secret 数量较多，详细列表请查看 CSV 或 JSON 文件"
    echo ""
    echo "- CSV 文件: \`${CSV_FILE}\`"
    echo "- JSON 文件: \`${JSON_FILE}\`"
    echo ""
    
} > "${MARKDOWN_FILE}"

# 生成简化的 HTML 报告
{
    cat << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GCP Secret Manager 权限审计报告 (并行版本)</title>
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
        code {
            background-color: #f3f4f6;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
        }
        .list-item {
            padding: 8px;
            margin: 4px 0;
            background-color: #f9fafb;
            border-radius: 4px;
        }
    </style>
</head>
<body>
EOF

    echo "    <div class=\"header\">"
    echo "        <h1>🔐 GCP Secret Manager 权限审计报告</h1>"
    echo "        <p><strong>项目 ID:</strong> ${PROJECT_ID}</p>"
    echo "        <p><strong>生成时间:</strong> $(date)</p>"
    echo "        <p><strong>版本:</strong> 并行处理版本</p>"
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
    
    echo "    <div class=\"performance\">"
    echo "        <h3>⚡ 性能统计</h3>"
    echo "        <p><strong>处理耗时:</strong> ${ELAPSED} 秒</p>"
    echo "        <p><strong>平均速度:</strong> $(echo "scale=2; $ELAPSED / $SECRET_COUNT" | bc) 秒/Secret</p>"
    echo "        <p><strong>吞吐量:</strong> $(echo "scale=2; $SECRET_COUNT / $ELAPSED" | bc) Secret/秒</p>"
    echo "        <p><strong>并行任务数:</strong> ${PARALLEL_JOBS}</p>"
    echo "    </div>"
    
    echo "    <div class=\"section\">"
    echo "        <h2>📊 按角色统计</h2>"
    echo "        <table>"
    echo "            <thead>"
    echo "                <tr><th>角色</th><th>绑定数量</th></tr>"
    echo "            </thead>"
    echo "            <tbody>"
    tail -n +2 "${CSV_FILE}" | cut -d',' -f2 | sort | uniq -c | sort -rn | head -20 | while read count role; do
        role_clean=$(echo "$role" | tr -d '"')
        echo "                <tr><td><code>${role_clean}</code></td><td>${count}</td></tr>"
    done
    echo "            </tbody>"
    echo "        </table>"
    echo "    </div>"
    
    echo "    <div class=\"section\">"
    echo "        <h2>📋 数据文件</h2>"
    echo "        <p>由于 Secret 数量较多，完整数据请查看以下文件：</p>"
    echo "        <ul>"
    echo "            <li><code>${CSV_FILE}</code> - CSV 格式，可用 Excel 打开</li>"
    echo "            <li><code>${JSON_FILE}</code> - JSON 格式，可用于程序处理</li>"
    echo "            <li><code>${SUMMARY_FILE}</code> - 文本格式汇总报告</li>"
    echo "        </ul>"
    echo "    </div>"
    
    echo "    <div style=\"text-align: center; color: #6b7280; margin-top: 40px;\">"
    echo "        <p>报告生成于: $(date)</p>"
    echo "    </div>"
    
    echo "</body>"
    echo "</html>"
    
} > "${HTML_FILE}"

################################################################################
# 6. 清理临时文件
################################################################################
echo -e "\n${GREEN}[5/5] 清理临时文件...${NC}"
rm -rf "${TEMP_DIR}"

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
echo -e "${YELLOW}性能优化建议:${NC}"
echo "  - 当前并行任务数: ${PARALLEL_JOBS}"
echo "  - 增加并行任务数可提升速度: $0 ${PROJECT_ID} 30"
echo "  - 建议范围: 10-50（取决于网络和 API 配额）"
echo ""
