#!/bin/bash

# 默认 CVE 编号
DEFAULT_CVE="CVE-2025-8941"

# 获取 CVE 参数，如果没有提供则使用默认值
CVE_ID="${1:-$DEFAULT_CVE}"

echo "=== $CVE_ID 状态检查 ==="
echo "检查时间: $(date)"
echo "=========================================="

# 函数：解析状态表格
parse_status_table() {
    local html_content="$1"
    
    echo -e "\n>> Ubuntu 版本修复状态"
    echo "格式: [版本] [代号] - [状态]"
    echo "----------------------------------------"
    
    # 提取表格数据，查找包含版本信息的行
    # 匹配模式：数字.数字 + 版本代号 + 状态
    table_data=$(echo "$html_content" | sed 's/<[^>]*>//g' | grep -E '[0-9]+\.[0-9]+.*LTS|[0-9]+\.[0-9]+.*[a-z]+.*Vulnerable|[0-9]+\.[0-9]+.*[a-z]+.*Fixed')
    
    if [ -n "$table_data" ]; then
        # 处理每一行状态信息
        echo "$table_data" | while IFS= read -r line; do
            if [[ "$line" =~ [0-9]+\.[0-9]+ ]]; then
                # 清理和格式化输出
                clean_line=$(echo "$line" | sed 's/  */ /g' | sed 's/^ *//g')
                
                # 根据状态添加图标
                if echo "$clean_line" | grep -q -i "vulnerable.*deferred"; then
                    echo "🔴 $clean_line"
                elif echo "$clean_line" | grep -q -i "vulnerable"; then
                    echo "⚠️  $clean_line"
                elif echo "$clean_line" | grep -q -i "fixed\|patched"; then
                    echo "✅ $clean_line"
                elif echo "$clean_line" | grep -q -i "not.*affected"; then
                    echo "🟢 $clean_line"
                else
                    echo "❓ $clean_line"
                fi
            fi
        done
    else
        echo "未找到版本状态表格"
    fi
}

# 函数：解析 HTML 并提取关键信息
parse_cve_info() {
    local html_content="$1"
    local cve_id="$2"
    
    echo -e "\n>> CVE 基本信息"
    echo "CVE 编号: $cve_id"
    
    # 提取标题
    title=$(echo "$html_content" | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g' | head -1)
    if [ -n "$title" ]; then
        echo "标题: $title"
    fi
    
    # 提取描述 - 改进的描述提取
    echo -e "\n>> 漏洞描述"
    # 尝试多种方式提取描述
    description=$(echo "$html_content" | sed 's/<[^>]*>//g' | grep -A 5 -i "description\|summary" | head -3 | grep -v "^$")
    if [ -z "$description" ]; then
        # 备用方法：查找段落内容
        description=$(echo "$html_content" | grep -o '<p[^>]*>[^<]*</p>' | sed 's/<[^>]*>//g' | head -2)
    fi
    
    if [ -n "$description" ]; then
        echo "$description"
    else
        echo "未找到详细描述"
    fi
    
    # 提取严重程度和 CVSS
    echo -e "\n>> 风险评估"
    # 查找严重程度
    severity=$(echo "$html_content" | sed 's/<[^>]*>//g' | grep -i -o "severity[^a-zA-Z]*[a-zA-Z]*" | head -1)
    if [ -n "$severity" ]; then
        echo "严重程度: $severity"
    fi
    
    # 查找 CVSS 分数
    cvss=$(echo "$html_content" | sed 's/<[^>]*>//g' | grep -i -o "cvss[^0-9]*[0-9]\+\.[0-9]\+" | head -1)
    if [ -n "$cvss" ]; then
        echo "CVSS 分数: $cvss"
    fi
    
    # 提取发布日期
    echo -e "\n>> 时间信息"
    pub_date=$(echo "$html_content" | sed 's/<[^>]*>//g' | grep -i -o "published[^0-9]*[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" | head -1)
    if [ -n "$pub_date" ]; then
        echo "$pub_date"
    fi
    
    # 提取影响的包名
    echo -e "\n>> 影响的软件包"
    # 查找包名，通常在表格或列表中
    packages=$(echo "$html_content" | sed 's/<[^>]*>//g' | grep -o -E '[a-z0-9-]+' | grep -E '^(lib|pam|ssh|kernel|openssl|apache|nginx|mysql|postgresql)' | head -5 | sort -u)
    if [ -n "$packages" ]; then
        echo "$packages" | while read -r pkg; do
            echo "- $pkg"
        done
    else
        echo "未找到具体软件包信息"
    fi
    
    # 解析状态表格
    parse_status_table "$html_content"
    
    # 总体修复状态分析
    echo -e "\n>> 修复状态总结"
    if echo "$html_content" | grep -i -q "fix.*deferred"; then
        echo "🔴 修复被推迟 - 需要关注后续更新"
    elif echo "$html_content" | grep -i -q "vulnerable"; then
        echo "⚠️  存在漏洞 - 建议尽快更新"
    elif echo "$html_content" | grep -i -q "fixed\|patched"; then
        echo "✅ 已有修复版本可用"
    else
        echo "❓ 修复状态未明确"
    fi
}

# 1. 检查 CVE 详情页面
echo -e "\n>> 获取 CVE 详情"
cve_url="https://ubuntu.com/security/$CVE_ID"
echo "查询地址: $cve_url"

html_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$cve_url")
http_code=$(echo "$html_response" | tail -1 | cut -d: -f2)
html_content=$(echo "$html_response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo "✅ 成功获取 CVE 信息"
    parse_cve_info "$html_content" "$CVE_ID"
elif [ "$http_code" = "404" ]; then
    echo "❌ CVE 不存在或尚未公开 (HTTP 404)"
else
    echo "⚠️  请求失败 (HTTP $http_code)"
fi

# 2. 搜索相关安全公告
echo -e "\n=========================================="
echo ">> 搜索相关安全公告"
search_term=$(echo "$CVE_ID" | cut -d'-' -f3)  # 提取年份后的数字
notices_url="https://ubuntu.com/security/notices?q=$search_term"
echo "搜索地址: $notices_url"

notices_response=$(curl -s "$notices_url")
if echo "$notices_response" | grep -q "$CVE_ID"; then
    echo "✅ 找到相关安全公告"
    # 提取公告链接
    usn_links=$(echo "$notices_response" | grep -o 'href="/security/notices/USN-[^"]*"' | head -3)
    if [ -n "$usn_links" ]; then
        echo "相关公告:"
        echo "$usn_links" | sed 's/href="//g; s/"//g; s|^|https://ubuntu.com|g'
    fi
else
    echo "❌ 未找到相关安全公告"
fi

# 3. 生成总结报告
echo -e "\n=========================================="
echo ">> 检查总结"
echo "CVE 编号: $CVE_ID"
echo "检查完成时间: $(date)"
echo "建议: 请关注官方安全公告获取最新修复信息"

# 使用说明
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "\n使用说明:"
    echo "$0 [CVE-ID]"
    echo "例如: $0 CVE-2024-1234"
    echo "如果不提供参数，默认查询 $DEFAULT_CVE"
fi
