#!/bin/bash

# GCP Cloud DNS 记录批量删除脚本
# 用途: 删除指定域名在 Cloud DNS Zone 中的所有相关记录(CNAME 和 A 记录)

# ============================================
# 配置区域
# ============================================

# GCP 项目 ID
PROJECT_ID="your-project-id"

# 默认 DNS Zone 名称
DEFAULT_ZONE_NAME="private-access"

# 需要删除的域名列表(只需要提供最初的域名)
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
  -n               预览模式,只显示将要删除的记录,不实际删除
  -h               显示此帮助信息

示例:
  $(basename $0)                                    # 使用默认配置
  $(basename $0) -p my-project -z my-zone          # 指定项目和 Zone
  $(basename $0) -n                                # 预览模式
  $(basename $0) -z custom-zone -n                 # 预览指定 Zone 的删除

说明:
  脚本会查询 Cloud DNS Zone 中与域名列表相关的所有记录,
  包括 CNAME 链和 A 记录,并将它们删除。
  删除逻辑基于 Zone 中的实际记录,不依赖当前的 DNS 解析结果。

EOF
}

# 解析命令行参数
parse_args() {
    DRY_RUN=false
    
    while getopts "p:z:nh" opt; do
        case $opt in
            p)
                PROJECT_ID="$OPTARG"
                ;;
            z)
                ZONE_NAME="$OPTARG"
                ;;
            n)
                DRY_RUN=true
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
    
    if ! command -v gcloud &> /dev/null; then
        missing_deps+=(gcloud)
    fi
    
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

# 查找域名相关的所有记录
find_related_records() {
    local zone=$1
    local domain=$2
    local -n records_ref=$3
    
    echo -e "${BLUE}查找域名相关记录: $domain${NC}" >&2
    
    # 确保域名以 . 结尾
    local search_domain="$domain"
    [[ "$search_domain" != *. ]] && search_domain="${search_domain}."
    
    # 查询所有记录
    local all_records=$(gcloud dns record-sets list \
        --zone="$zone" \
        --format="csv[no-heading](name,type,ttl,rrdatas)" 2>/dev/null)
    
    if [ -z "$all_records" ]; then
        echo -e "${YELLOW}  未找到任何记录${NC}" >&2
        return 1
    fi
    
    # 存储找到的记录
    local found_records=()
    local processed_domains=()
    
    # 递归查找 CNAME 链
    local current_domain="$search_domain"
    local max_depth=10
    local depth=0
    
    while [ $depth -lt $max_depth ]; do
        # 检查是否已处理过这个域名(避免循环)
        if [[ " ${processed_domains[@]} " =~ " ${current_domain} " ]]; then
            break
        fi
        
        processed_domains+=("$current_domain")
        
        # 查找当前域名的记录
        local record=$(echo "$all_records" | grep "^${current_domain}," | head -1)
        
        if [ -z "$record" ]; then
            break
        fi
        
        local record_type=$(echo "$record" | cut -d',' -f2)
        local record_ttl=$(echo "$record" | cut -d',' -f3)
        local record_data=$(echo "$record" | cut -d',' -f4-)
        
        # 移除引号
        record_data=$(echo "$record_data" | sed 's/"//g')
        
        echo -e "  ${GREEN}找到 $record_type 记录:${NC} $current_domain -> $record_data" >&2
        
        # 保存记录信息
        found_records+=("$current_domain|$record_type|$record_ttl|$record_data")
        
        # 如果是 CNAME,继续追踪
        if [ "$record_type" = "CNAME" ]; then
            current_domain="$record_data"
            [[ "$current_domain" != *. ]] && current_domain="${current_domain}."
        elif [ "$record_type" = "A" ]; then
            # 到达 A 记录,结束
            break
        else
            break
        fi
        
        ((depth++))
    done
    
    if [ ${#found_records[@]} -eq 0 ]; then
        echo -e "${YELLOW}  未找到相关记录${NC}" >&2
        return 1
    fi
    
    # 返回找到的记录
    records_ref=("${found_records[@]}")
    return 0
}

# 删除 DNS 记录
delete_dns_records() {
    local zone=$1
    local domain=$2
    local -n records_array=$3
    local dry_run=$4
    
    if [ "$dry_run" = true ]; then
        echo -e "\n${YELLOW}[预览模式] 将要删除以下记录:${NC}" >&2
    else
        echo -e "\n${BLUE}删除 $domain 的 DNS 记录...${NC}" >&2
    fi
    
    local success=true
    local deleted_count=0
    
    # 逆序删除(先删除 A 记录,再删除 CNAME)
    for ((i=${#records_array[@]}-1; i>=0; i--)); do
        local record="${records_array[$i]}"
        
        local record_name=$(echo "$record" | cut -d'|' -f1)
        local record_type=$(echo "$record" | cut -d'|' -f2)
        local record_ttl=$(echo "$record" | cut -d'|' -f3)
        local record_data=$(echo "$record" | cut -d'|' -f4)
        
        echo -e "  ${BLUE}$record_type 记录:${NC} $record_name (TTL: $record_ttl) -> $record_data" >&2
        
        if [ "$dry_run" = true ]; then
            echo -e "    ${YELLOW}[预览] 将删除此记录${NC}" >&2
            ((deleted_count++))
        else
            # 实际删除
            if gcloud dns record-sets delete "$record_name" \
                --type="$record_type" \
                --zone="$zone" \
                --quiet &>/dev/null; then
                echo -e "    ${GREEN}✓ 成功删除${NC}" >&2
                ((deleted_count++))
            else
                echo -e "    ${RED}✗ 删除失败${NC}" >&2
                success=false
            fi
        fi
    done
    
    echo -e "  ${GREEN}处理了 $deleted_count 条记录${NC}" >&2
    
    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# 验证记录是否已删除
verify_deletion() {
    local zone=$1
    local domain=$2
    
    echo -e "\n${BLUE}验证删除结果...${NC}" >&2
    
    local search_domain="$domain"
    [[ "$search_domain" != *. ]] && search_domain="${search_domain}."
    
    local remaining=$(gcloud dns record-sets list \
        --zone="$zone" \
        --filter="name:$search_domain" \
        --format="value(name)" 2>/dev/null)
    
    if [ -z "$remaining" ]; then
        echo -e "${GREEN}✓ 确认所有相关记录已删除${NC}" >&2
    else
        echo -e "${YELLOW}⚠ 仍有相关记录存在:${NC}" >&2
        echo "$remaining" | while read -r name; do
            echo -e "  - $name" >&2
        done
    fi
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
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}GCP Cloud DNS 记录批量删除工具 [预览模式]${NC}"
    else
        echo -e "${GREEN}GCP Cloud DNS 记录批量删除工具${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    echo -e "项目 ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "DNS Zone: ${BLUE}$ZONE_NAME${NC}"
    echo -e "域名数量: ${BLUE}${#DOMAINS[@]}${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "模式: ${YELLOW}预览模式 (不会实际删除)${NC}"
    fi
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
    local total_records_deleted=0
    
    # 处理每个域名
    for domain in "${DOMAINS[@]}"; do
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}处理域名: $domain${NC}"
        echo -e "${GREEN}========================================${NC}"
        
        # 查找相关记录
        local domain_records=()
        
        if find_related_records "$ZONE_NAME" "$domain" domain_records; then
            # 删除记录
            if delete_dns_records "$ZONE_NAME" "$domain" domain_records "$DRY_RUN"; then
                ((success_count++))
                total_records_deleted=$((total_records_deleted + ${#domain_records[@]}))
                
                # 验证删除(仅在非预览模式)
                if [ "$DRY_RUN" = false ]; then
                    verify_deletion "$ZONE_NAME" "$domain"
                fi
            else
                ((fail_count++))
            fi
        else
            echo -e "${YELLOW}域名 $domain 在 Zone 中没有相关记录,跳过${NC}"
            ((success_count++))
        fi
    done
    
    # 显示汇总
    echo -e "\n${GREEN}========================================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}预览完成${NC}"
    else
        echo -e "${GREEN}删除完成${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    echo -e "总域名数: ${BLUE}$total_domains${NC}"
    echo -e "成功处理: ${GREEN}$success_count${NC}"
    echo -e "失败: ${RED}$fail_count${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "将删除记录数: ${YELLOW}$total_records_deleted${NC}"
    else
        echo -e "已删除记录数: ${GREEN}$total_records_deleted${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "\n${YELLOW}这是预览模式,没有实际删除任何记录${NC}"
        echo -e "${YELLOW}如需实际删除,请去掉 -n 参数重新运行${NC}"
    fi
}

# 运行主程序
main "$@"
