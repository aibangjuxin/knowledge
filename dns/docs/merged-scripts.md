# Shell Scripts Collection

Generated on: 2026-01-27 16:33:08
Directory: /Users/lex/git/knowledge/dns/docs

## `dnsrecord-del-script.sh`

```bash
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

```

## `dnsrecord-add-script-eng.sh`

```bash
#!/bin/bash

# GCP Cloud DNS Record Batch Addition Script
# Purpose: Automatically resolve domains and add CNAME and A records to the specified Cloud DNS Zone

# ============================================
# Configuration Section
# ============================================

# GCP Project ID
PROJECT_ID="your-project-id"

# Default DNS Zone Name
DEFAULT_ZONE_NAME="private-access"

# Domain list to be added
DOMAINS=(
    "www.example.com"
    "api.example.com"
    "login.microsoft.com"
    "graph.microsoft.com"
)

# ============================================
# Color Definitions
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Function Definitions
# ============================================

# Display help information
show_help() {
    cat << EOF
Usage: $(basename $0) [options]

Options:
  -p PROJECT_ID    Specify GCP Project ID (default: $PROJECT_ID)
  -z ZONE_NAME     Specify DNS Zone Name (default: $DEFAULT_ZONE_NAME)
  -h               Show this help information

Examples:
  $(basename $0)                                    # Use default configuration
  $(basename $0) -p my-project -z my-zone          # Specify project and Zone
  $(basename $0) -z custom-zone                    # Specify Zone only

Description:
  The script automatically resolves all domains in the domain list, extracts CNAME and A records,
  and adds them to the specified Cloud DNS Zone.

EOF
}

# Parse command-line arguments
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
                echo -e "${RED}Error: Invalid option -$OPTARG${NC}" >&2
                show_help
                exit 1
                ;;
        esac
    done
}

# Check if required commands exist
check_dependencies() {
    local missing_deps=()

    for cmd in gcloud host; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required commands: ${missing_deps[*]}${NC}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
}

# Set GCP Project
set_project() {
    echo -e "${BLUE}Setting GCP Project: $PROJECT_ID${NC}"
    gcloud config set project "$PROJECT_ID" --quiet

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Cannot set project $PROJECT_ID${NC}"
        exit 1
    fi
}

# List all DNS Zones
list_zones() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}DNS Zones in Current Project:${NC}"
    echo -e "${GREEN}========================================${NC}"

    gcloud dns managed-zones list \
        --format='table[box](dnsName, creationTime:sort=1, name, privateVisibilityConfig.networks.networkUrl.basename(), description)'

    echo ""
}

# Check if Zone exists
check_zone_exists() {
    local zone=$1

    if ! gcloud dns managed-zones describe "$zone" &> /dev/null; then
        echo -e "${RED}Error: DNS Zone '$zone' does not exist${NC}"
        echo "Available Zones:"
        gcloud dns managed-zones list --format="value(name)"
        exit 1
    fi
}

# Resolve domain to get all records
resolve_domain() {
    local domain=$1
    local -n cnames_ref=$2
    local -n a_record_ref=$3

    echo -e "${BLUE}Resolving domain: $domain${NC}"

    # Use host command to resolve
    local host_output=$(host "$domain" 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}  Warning: Cannot resolve $domain${NC}"
        return 1
    fi

    # Extract CNAME records
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

    # Extract A record
    local ip_address=$(echo "$host_output" | grep "has address" | awk '{print $NF}' | head -1)

    if [ -n "$ip_address" ]; then
        echo -e "  ${GREEN}A Record:${NC} $current_domain -> $ip_address"
        a_record_ref="$current_domain $ip_address"
    else
        echo -e "${YELLOW}  Warning: No A record found${NC}"
        return 1
    fi

    # Return CNAME chain
    cnames_ref=("${cname_chain[@]}")

    return 0
}

# Add DNS records
add_dns_records() {
    local zone=$1
    local domain=$2
    local -n cnames_array=$3
    local a_record=$4

    echo -e "\n${BLUE}Adding DNS records for $domain to Zone: $zone${NC}" >&2

    local success=true

    # Add CNAME records
    for cname_entry in "${cnames_array[@]}"; do
        local source=$(echo "$cname_entry" | awk '{print $1}')
        local target=$(echo "$cname_entry" | awk '{print $3}')

        # Ensure ends with .
        [[ "$source" != *. ]] && source="${source}."
        [[ "$target" != *. ]] && target="${target}."

        echo -e "  ${BLUE}Adding CNAME:${NC} $source -> $target" >&2

        # Check if record already exists
        if gcloud dns record-sets describe "$source" --type=CNAME --zone="$zone" &>/dev/null; then
            echo -e "  ${YELLOW}Record already exists, skipping${NC}" >&2
        else
            if gcloud dns record-sets create "$source" \
                --rrdatas="$target" \
                --type=CNAME \
                --ttl=300 \
                --zone="$zone" &>/dev/null; then
                echo -e "  ${GREEN}✓ Successfully added CNAME${NC}" >&2
            else
                echo -e "  ${RED}✗ Failed to add CNAME${NC}" >&2
                success=false
            fi
        fi
    done

    # Add A record
    if [ -n "$a_record" ]; then
        local a_domain=$(echo "$a_record" | awk '{print $1}')
        local a_ip=$(echo "$a_record" | awk '{print $2}')

        [[ "$a_domain" != *. ]] && a_domain="${a_domain}."

        echo -e "  ${BLUE}Adding A Record:${NC} $a_domain -> $a_ip" >&2

        # Check if record already exists
        if gcloud dns record-sets describe "$a_domain" --type=A --zone="$zone" &>/dev/null; then
            echo -e "  ${YELLOW}Record already exists, skipping${NC}" >&2
        else
            if gcloud dns record-sets create "$a_domain" \
                --rrdatas="$a_ip" \
                --type=A \
                --ttl=300 \
                --zone="$zone" &>/dev/null; then
                echo -e "  ${GREEN}✓ Successfully added A Record${NC}" >&2
            else
                echo -e "  ${RED}✗ Failed to add A Record${NC}" >&2
                success=false
            fi
        fi
    fi

    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Verify if records were added successfully
verify_records() {
    local zone=$1
    local domain=$2

    echo -e "\n${BLUE}Verifying DNS records for $domain...${NC}"

    # Query all records related to this domain
    gcloud dns record-sets list \
        --zone="$zone" \
        --filter="name:$domain" \
        --format="table[box](name, type, ttl, rrdatas)"

    echo ""
}

# ============================================
# Main Program
# ============================================

main() {
    # Parse arguments
    parse_args "$@"

    # Use default Zone if not specified
    ZONE_NAME="${ZONE_NAME:-$DEFAULT_ZONE_NAME}"

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GCP Cloud DNS Record Batch Addition Tool${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "DNS Zone: ${BLUE}$ZONE_NAME${NC}"
    echo -e "Domain Count: ${BLUE}${#DOMAINS[@]}${NC}"
    echo ""

    # Check dependencies
    check_dependencies

    # Set project
    set_project

    # List all Zones
    list_zones

    # Check if Zone exists
    check_zone_exists "$ZONE_NAME"

    # Statistics variables
    local total_domains=${#DOMAINS[@]}
    local success_count=0
    local fail_count=0

    # Process each domain
    for domain in "${DOMAINS[@]}"; do
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Processing domain: $domain${NC}"
        echo -e "${GREEN}========================================${NC}"

        # Resolve domain
        local domain_cnames=()
        local domain_a_record=""

        if resolve_domain "$domain" domain_cnames domain_a_record; then
            # Add DNS records
            if add_dns_records "$ZONE_NAME" "$domain" domain_cnames "$domain_a_record"; then
                ((success_count++))

                # Verify records
                verify_records "$ZONE_NAME" "$domain"
            else
                ((fail_count++))
            fi
        else
            ((fail_count++))
        fi
    done

    # Display summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Processing Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Total Domains: ${BLUE}$total_domains${NC}"
    echo -e "Success: ${GREEN}$success_count${NC}"
    echo -e "Failed: ${RED}$fail_count${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Display all records in the end
    echo -e "\n${BLUE}All records in Zone '$ZONE_NAME':${NC}"
    gcloud dns record-sets list \
        --zone="$ZONE_NAME" \
        --format="table[box](name, type, ttl, rrdatas)"
}

# Run main program
main "$@"
```

## `dnsrecord-add-script.sh`

```bash
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

# 添加 DNS 记录
add_dns_records() {
    local zone=$1
    local domain=$2
    local -n cnames_array=$3
    local a_record=$4
    
    echo -e "\n${BLUE}为 $domain 添加 DNS 记录到 Zone: $zone${NC}" >&2
    
    local success=true
    
    # 添加 CNAME 记录
    for cname_entry in "${cnames_array[@]}"; do
        local source=$(echo "$cname_entry" | awk '{print $1}')
        local target=$(echo "$cname_entry" | awk '{print $3}')
        
        # 确保以 . 结尾
        [[ "$source" != *. ]] && source="${source}."
        [[ "$target" != *. ]] && target="${target}."
        
        echo -e "  ${BLUE}添加 CNAME:${NC} $source -> $target" >&2
        
        # 检查记录是否已存在
        if gcloud dns record-sets describe "$source" --type=CNAME --zone="$zone" &>/dev/null; then
            echo -e "  ${YELLOW}记录已存在,跳过${NC}" >&2
        else
            if gcloud dns record-sets create "$source" \
                --rrdatas="$target" \
                --type=CNAME \
                --ttl=300 \
                --zone="$zone" &>/dev/null; then
                echo -e "  ${GREEN}✓ 成功添加 CNAME${NC}" >&2
            else
                echo -e "  ${RED}✗ 添加 CNAME 失败${NC}" >&2
                success=false
            fi
        fi
    done
    
    # 添加 A 记录
    if [ -n "$a_record" ]; then
        local a_domain=$(echo "$a_record" | awk '{print $1}')
        local a_ip=$(echo "$a_record" | awk '{print $2}')
        
        [[ "$a_domain" != *. ]] && a_domain="${a_domain}."
        
        echo -e "  ${BLUE}添加 A Record:${NC} $a_domain -> $a_ip" >&2
        
        # 检查记录是否已存在
        if gcloud dns record-sets describe "$a_domain" --type=A --zone="$zone" &>/dev/null; then
            echo -e "  ${YELLOW}记录已存在,跳过${NC}" >&2
        else
            if gcloud dns record-sets create "$a_domain" \
                --rrdatas="$a_ip" \
                --type=A \
                --ttl=300 \
                --zone="$zone" &>/dev/null; then
                echo -e "  ${GREEN}✓ 成功添加 A Record${NC}" >&2
            else
                echo -e "  ${RED}✗ 添加 A Record 失败${NC}" >&2
                success=false
            fi
        fi
    fi
    
    if [ "$success" = true ]; then
        return 0
    else
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
        local domain_cnames=()
        local domain_a_record=""
        
        if resolve_domain "$domain" domain_cnames domain_a_record; then
            # 添加 DNS 记录
            if add_dns_records "$ZONE_NAME" "$domain" domain_cnames "$domain_a_record"; then
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

```

