#!/bin/bash

# GCP Cloud DNS 记录批量添加脚本
# 用途: 自动解析域名并将 CNAME 和 A 记录添加到指定的 Cloud DNS Zone

# ============================================
# 配置区域
# ============================================

# GCP 项目 ID
PROJECT_ID="your-project-id"

# 默认 DNS Zone 名称
DEFAULT_ZONE_NAME="private-access"

# 需要添加的域名列表
DOMAINS=(
    "www.example.com"
    "api.example.com"
    "login.microsoft.com"
    "graph.microsoft.com"
)

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# 函数定义
# ============================================

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename $0) [选项]

选项:
  -p PROJECT_ID    指定 GCP 项目 ID (默认: $PROJECT_ID)
  -z ZONE_NAME     指定 DNS Zone 名称 (默认: $DEFAULT_ZONE_NAME)
  -h               显示此帮助信息

示例:
  $(basename $0)                                    # 使用默认配置
  $(basename $0) -p my-project -z my-zone          # 指定项目和 Zone
  $(basename $0) -z custom-zone                    # 只指定 Zone

说明:
  脚本会自动解析域名列表中的所有域名，提取 CNAME 和 A 记录，
  并将它们添加到指定的 Cloud DNS Zone 中。

EOF
}

# 解析命令行参数
parse_args() {
    while getopts "p:z:h" opt; do
        case $opt in
            p)
                PROJECT_ID="$OPTARG"
                ;;
            z)
                ZONE_NAME="$OPTARG"
                ;;
            h)
                show_help
                exit 0
                ;;
            \?)
                echo -e "${RED}错误: 无效选项 -$OPTARG${NC}" >&2
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查必要的命令是否存在
check_dependencies() {
    local missing_deps=()
    
    for cmd in gcloud host; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}错误: 缺少必要的命令: ${missing_deps[*]}${NC}"
        echo "请安装缺失的工具后重试"
        exit 1
    fi
}

# 设置 GCP 项目
set_project() {
    echo -e "${BLUE}设置 GCP 项目: $PROJECT_ID${NC}"
    gcloud config set project "$PROJECT_ID" --quiet
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 无法设置项目 $PROJECT_ID${NC}"
        exit 1
    fi
}

# 列出所有 DNS Zones
list_zones() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}当前项目的 DNS Zones:${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    gcloud dns managed-zones list \
        --format='table[box](dnsName, creationTime:sort=1, name, privateVisibilityConfig.networks.networkUrl.basename(), description)'
    
    echo ""
}

# 检查 Zone 是否存在
check_zone_exists() {
    local zone=$1
    
    if ! gcloud dns managed-zones describe "$zone" &> /dev/null; then
        echo -e "${RED}错误: DNS Zone '$zone' 不存在${NC}"
        echo "可用的 Zones:"
        gcloud dns managed-zones list --format="value(name)"
        exit 1
    fi
}

# 解析域名获取所有记录
resolve_domain() {
    local domain=$1
    local -n cnames_ref=$2
    local -n a_record_ref=$3
    
    echo -e "${BLUE}解析域名: $domain${NC}"
    
    # 使用 host 命令解析
    local host_output=$(host "$domain" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}  警告: 无法解析 $domain${NC}"
        return 1
    fi
    
    # 提取 CNAME 记录
    local cname_chain=()
    local current_domain="$domain"
    
    while true; do
        local cname=$(echo "$host_output" | grep "is an alias for" | awk '{print $NF}' | sed 's/\.$//')
        
        if [ -z "$cname" ]; then
            break
        fi
        
        cname_chain+=("$current_domain -> $cname")
        echo -e "  ${GREEN}CNAME:${NC} $current_domain -> $cname"
        
        current_domain="$cname"
        host_output=$(host "$cname" 2>&1)
    done
    
    # 提取 A 记录
    local ip_address=$(echo "$host_output" | grep "has address" | awk '{print $NF}' | head -1)
    
    if [ -n "$ip_address" ]; then
        echo -e "  ${GREEN}A Record:${NC} $current_domain -> $ip_address"
        a_record_ref="$current_domain $ip_address"
    else
        echo -e "${YELLOW}  警告: 未找到 A 记录${NC}"
        return 1
    fi
    
    # 返回 CNAME 链
    cnames_ref=("${cname_chain[@]}")
    
    return 0
}

# 创建 DNS 记录事务文件
create_dns_transaction() {
    local zone=$1
    local domain=$2
    local -n cnames=$3
    local a_record=$4
    
    # 开始事务
    echo -e "\n${BLUE}为 $domain 创建 DNS 记录...${NC}"
    
    # 创建临时事务文件
    local transaction_file="/tmp/dns-transaction-$(date +%s).yaml"
    
    cat > "$transaction_file" << EOF
---
additions:
EOF
    
    # 添加 CNAME 记录
    for cname_entry in "${cnames[@]}"; do
        local source=$(echo "$cname_entry" | awk '{print $1}')
        local target=$(echo "$cname_entry" | awk '{print $3}')
        
        # 确保以 . 结尾
        [[ "$source" != *. ]] && source="${source}."
        [[ "$target" != *. ]] && target="${target}."
        
        cat >> "$transaction_file" << EOF
- kind: dns#resourceRecordSet
  name: "$source"
  rrdatas:
  - "$target"
  ttl: 300
  type: CNAME
EOF
        
        echo -e "  ${GREEN}添加 CNAME:${NC} $source -> $target"
    done
    
    # 添加 A 记录
    if [ -n "$a_record" ]; then
        local a_domain=$(echo "$a_record" | awk '{print $1}')
        local a_ip=$(echo "$a_record" | awk '{print $2}')
        
        [[ "$a_domain" != *. ]] && a_domain="${a_domain}."
        
        cat >> "$transaction_file" << EOF
- kind: dns#resourceRecordSet
  name: "$a_domain"
  rrdatas:
  - "$a_ip"
  ttl: 300
  type: A
EOF
        
        echo -e "  ${GREEN}添加 A Record:${NC} $a_domain -> $a_ip"
    fi
    
    echo "$transaction_file"
}

# 导入 DNS 记录
import_dns_records() {
    local zone=$1
    local transaction_file=$2
    
    echo -e "\n${BLUE}导入 DNS 记录到 Zone: $zone${NC}"
    
    gcloud dns record-sets import "$transaction_file" \
        --zone="$zone" \
        --zone-file-format 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 成功导入 DNS 记录${NC}"
        rm -f "$transaction_file"
        return 0
    else
        echo -e "${RED}✗ 导入失败${NC}"
        echo "事务文件保存在: $transaction_file"
        return 1
    fi
}

# 验证记录是否添加成功
verify_records() {
    local zone=$1
    local domain=$2
    
    echo -e "\n${BLUE}验证 $domain 的 DNS 记录...${NC}"
    
    # 查询该域名相关的所有记录
    gcloud dns record-sets list \
        --zone="$zone" \
        --filter="name:$domain" \
        --format="table[box](name, type, ttl, rrdatas)"
    
    echo ""
}

# ============================================
# 主程序
# ============================================

main() {
    # 解析参数
    parse_args "$@"
    
    # 使用默认 Zone 如果未指定
    ZONE_NAME="${ZONE_NAME:-$DEFAULT_ZONE_NAME}"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GCP Cloud DNS 记录批量添加工具${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "项目 ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "DNS Zone: ${BLUE}$ZONE_NAME${NC}"
    echo -e "域名数量: ${BLUE}${#DOMAINS[@]}${NC}"
    echo ""
    
    # 检查依赖
    check_dependencies
    
    # 设置项目
    set_project
    
    # 列出所有 Zones
    list_zones
    
    # 检查 Zone 是否存在
    check_zone_exists "$ZONE_NAME"
    
    # 统计变量
    local total_domains=${#DOMAINS[@]}
    local success_count=0
    local fail_count=0
    
    # 处理每个域名
    for domain in "${DOMAINS[@]}"; do
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}处理域名: $domain${NC}"
        echo -e "${GREEN}========================================${NC}"
        
        # 解析域名
        local cnames=()
        local a_record=""
        
        if resolve_domain "$domain" cnames a_record; then
            # 创建事务文件
            local transaction_file=$(create_dns_transaction "$ZONE_NAME" "$domain" cnames "$a_record")
            
            # 导入记录
            if import_dns_records "$ZONE_NAME" "$transaction_file"; then
                ((success_count++))
                
                # 验证记录
                verify_records "$ZONE_NAME" "$domain"
            else
                ((fail_count++))
            fi
        else
            ((fail_count++))
        fi
    done
    
    # 显示汇总
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}处理完成${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "总域名数: ${BLUE}$total_domains${NC}"
    echo -e "成功: ${GREEN}$success_count${NC}"
    echo -e "失败: ${RED}$fail_count${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # 显示最终的所有记录
    echo -e "\n${BLUE}Zone '$ZONE_NAME' 中的所有记录:${NC}"
    gcloud dns record-sets list \
        --zone="$ZONE_NAME" \
        --format="table[box](name, type, ttl, rrdatas)"
}

# 运行主程序
main "$@"
