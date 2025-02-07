#!/opt/homebrew/bin/bash

# 检查是否提供了域名参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 www.baidu.com"
    exit 1
fi

# 定义域名和 DNS 服务器列表（使用关联数组）
DOMAIN=$1
declare -A DNS_SERVERS=(
    ["8.8.8.8"]="Google Public DNS"
    ["119.29.29.29"]="腾讯 DNSPod"
    ["114.114.114.114"]="114 DNS"
)

# ANSI 颜色代码
GREEN='\033[32m'
NC='\033[0m'
SEPARATOR="================================================================"

# 对每个 DNS 服务器执行查询
for dns in "${!DNS_SERVERS[@]}"; do
    echo -e "\n${SEPARATOR}"
    echo -e "🔍 使用 DNS 服务器: ${GREEN}${dns}${NC} (${DNS_SERVERS[$dns]})"
    echo "${SEPARATOR}"
    
    # 执行 dig 命令并处理输出
    result=$(dig @"$dns" "$DOMAIN" +noall +answer +authority +additional)
    
    # 检查是否有 ANSWER SECTION
    if [ -n "$result" ]; then
        # 提取并高亮显示 ANSWER SECTION
        answer_section=$(echo "$result" | grep -A 10 "^$DOMAIN")
        if [ -n "$answer_section" ]; then
            echo -e "${GREEN}找到解析记录:${NC}"
            echo -e "${GREEN}${answer_section}${NC}"
        else
            echo "❌ 未找到解析记录"
        fi
    else
        echo "❌ 查询失败或未返回结果"
    fi
done

echo -e "\n${SEPARATOR}"
echo "✅ 查询完成"