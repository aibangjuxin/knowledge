# Shell Scripts Collection

Generated on: 2026-02-12 12:37:56
Directory: /Users/lex/git/knowledge/dns/docs/private-access

## `create-private-access.sh`

```bash
#!/bin/bash

# GCP Cloud DNS Zone 迁移脚本
# 用途: 从 private-access Zone 导出记录并创建新的环境特定 Zone

# ============================================
# 环境配置
# ============================================

declare -A env_info

env_info=(
  ["dev-cn"]="project=aibang-teng-sit-api-dev cluster=dev-cn-cluster-123789 region=europe-west2 https_proxy=10.72.21.119:3128 private_network=aibang-teng-sit-api-dev-cinternal-vpc3"
  ["lex-in"]="project=aibang-teng-sit-kongs-dev cluster=lex-in-cluster-123456 region=europe-west2 https_proxy=10.72.25.50:3128 private_network=aibang-teng-sit-kongs-dev-cinternal-vpc1"
)

environment=""
project=""
region=""
private_network=""
source_zone="private-access"
target_zone=""

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# 函数定义
# ============================================

# 显示帮助信息
show_help() {
    cat <<EOF
${GREEN}========================================${NC}
${GREEN}GCP Cloud DNS Zone 迁移工具${NC}
${GREEN}========================================${NC}

用法: $(basename $0) -e ENVIRONMENT [选项]

必需参数:
  -e ENVIRONMENT   环境标识 (格式: {env}-{region})
                   可用环境: ${!env_info[@]}

可选参数:
  -s SOURCE_ZONE   源 Zone 名称 (默认: private-access)
  -h               显示此帮助信息

示例:
  $(basename $0) -e dev-cn
  $(basename $0) -e lex-in -s custom-zone

功能说明:
  1. 列出当前项目的所有 DNS Zones
  2. 从源 Zone (private-access) 导出所有记录
  3. 获取源 Zone 绑定的网络信息
  4. 创建新的 Zone: {env}-{region}-private-access
  5. 绑定相同的网络到新 Zone
  6. 导入记录到新 Zone
  7. 对比验证新旧 Zone 的记录

EOF
}

# 解析命令行参数
parse_args() {
    while getopts "e:s:h" opt; do
        case $opt in
            e)
                environment="$OPTARG"
                ;;
            s)
                source_zone="$OPTARG"
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

    # 检查必需参数
    if [ -z "$environment" ]; then
        echo -e "${RED}错误: 必须指定环境参数 -e${NC}" >&2
        show_help
        exit 1
    fi
}

# 解析环境信息
parse_environment() {
    local env_string="${env_info[$environment]}"
    
    if [ -z "$env_string" ]; then
        echo -e "${RED}错误: 未找到环境 '$environment' 的配置${NC}"
        echo -e "${YELLOW}可用环境: ${!env_info[@]}${NC}"
        exit 1
    fi
    
    # 解析环境字符串
    for item in $env_string; do
        key=$(echo "$item" | cut -d'=' -f1)
        value=$(echo "$item" | cut -d'=' -f2-)
        
        case $key in
            project)
                project="$value"
                ;;
            region)
                region="$value"
                ;;
            private_network)
                private_network="$value"
                ;;
        esac
    done
    
    # 生成目标 Zone 名称
    target_zone="${environment}-private-access"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}环境配置信息${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "环境标识: ${BLUE}$environment${NC}"
    echo -e "项目 ID: ${BLUE}$project${NC}"
    echo -e "区域: ${BLUE}$region${NC}"
    echo -e "私有网络: ${BLUE}$private_network${NC}"
    echo -e "源 Zone: ${BLUE}$source_zone${NC}"
    echo -e "目标 Zone: ${BLUE}$target_zone${NC}"
    echo ""
}

# 检查必要的命令是否存在
check_dependencies() {
    local missing_deps=()
    
    for cmd in gcloud jq; do
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
    echo -e "${BLUE}设置 GCP 项目: $project${NC}"
    gcloud config set project "$project" --quiet
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 无法设置项目 $project${NC}"
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
        return 1
    fi
    return 0
}

# 获取 Zone 绑定的网络
get_zone_networks() {
    local zone=$1
    
    echo -e "${BLUE}获取 Zone '$zone' 绑定的网络...${NC}" >&2
    
    local networks=$(gcloud dns managed-zones describe "$zone" \
        --format='value(privateVisibilityConfig.networks[].networkUrl)' 2>/dev/null)
    
    if [ -z "$networks" ]; then
        echo -e "${YELLOW}警告: Zone '$zone' 未绑定任何网络${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}绑定的网络:${NC}" >&2
    # 处理分号分隔的网络 URL
    IFS=';' read -ra network_array <<< "$networks"
    for network in "${network_array[@]}"; do
        # 去除可能的空格
        network=$(echo "$network" | xargs)
        if [ -n "$network" ]; then
            local network_name=$(basename "$network")
            echo -e "  - ${CYAN}$network_name${NC}" >&2
        fi
    done
    
    # 只输出网络 URL 到 stdout（不带颜色代码）
    echo "$networks"
}

# 导出 Zone 的所有记录
export_zone_records() {
    local zone=$1
    local export_file="/tmp/${zone}-records-$(date +%Y%m%d-%H%M%S).json"
    
    echo -e "\n${BLUE}导出 Zone '$zone' 的所有记录...${NC}" >&2
    
    gcloud dns record-sets list \
        --zone="$zone" \
        --format=json > "$export_file"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 导出记录失败${NC}" >&2
        return 1
    fi
    
    local record_count=$(jq '. | length' "$export_file")
    echo -e "${GREEN}✓ 成功导出 $record_count 条记录到: $export_file${NC}" >&2
    
    # 显示记录摘要
    echo -e "\n${CYAN}记录类型统计:${NC}" >&2
    jq -r '.[] | .type' "$export_file" | sort | uniq -c | while read count type; do
        echo -e "  ${type}: ${BLUE}$count${NC}" >&2
    done
    
    # 只输出文件路径到 stdout（不带颜色代码）
    echo "$export_file"
}

# 显示记录详情
show_records() {
    local zone=$1
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Zone '$zone' 的所有记录:${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    gcloud dns record-sets list \
        --zone="$zone" \
        --format='table[box](name, type, ttl, rrdatas)'
}

# 从 Zone 解绑网络
unbind_zone_networks() {
    local zone=$1
    local networks=$2
    
    echo -e "\n${YELLOW}========================================${NC}" >&2
    echo -e "${YELLOW}从 Zone '$zone' 解绑网络${NC}" >&2
    echo -e "${YELLOW}========================================${NC}" >&2
    
    if [ -z "$networks" ]; then
        echo -e "${YELLOW}警告: 没有需要解绑的网络${NC}" >&2
        return 0
    fi
    
    # 处理分号分隔的网络 URL
    IFS=';' read -ra network_array <<< "$networks"
    local networks_to_remove=""
    
    for network in "${network_array[@]}"; do
        network=$(echo "$network" | xargs)
        if [ -n "$network" ]; then
            local network_name=$(basename "$network")
            echo -e "${CYAN}准备解绑网络: $network_name${NC}" >&2
            
            if [ -z "$networks_to_remove" ]; then
                networks_to_remove="$network"
            else
                networks_to_remove="$networks_to_remove,$network"
            fi
        fi
    done
    
    if [ -n "$networks_to_remove" ]; then
        echo -e "${BLUE}执行解绑操作...${NC}" >&2
        
        # 使用 gcloud 更新命令移除网络绑定
        if gcloud dns managed-zones update "$zone" \
            --networks="" \
            --quiet 2>&1; then
            echo -e "${GREEN}✓ 成功从 Zone '$zone' 解绑所有网络${NC}" >&2
            return 0
        else
            echo -e "${RED}✗ 解绑网络失败${NC}" >&2
            return 1
        fi
    fi
}

# 创建新的 DNS Zone
create_zone() {
    local zone_name=$1
    local dns_name=$2
    local networks=$3
    
    echo -e "\n${BLUE}创建新的 DNS Zone: $zone_name${NC}" >&2
    
    # 检查 Zone 是否已存在
    if check_zone_exists "$zone_name"; then
        echo -e "${YELLOW}警告: Zone '$zone_name' 已存在${NC}" >&2
        read -p "是否要删除并重新创建? (y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}删除现有 Zone...${NC}" >&2
            gcloud dns managed-zones delete "$zone_name" --quiet
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误: 删除 Zone 失败${NC}" >&2
                return 1
            fi
        else
            echo -e "${YELLOW}跳过创建，使用现有 Zone${NC}" >&2
            return 0
        fi
    fi
    
    # 构建网络参数 - 处理分号分隔的网络 URL
    local network_args=""
    IFS=';' read -ra network_array <<< "$networks"
    for network in "${network_array[@]}"; do
        # 去除可能的空格
        network=$(echo "$network" | xargs)
        if [ -n "$network" ]; then
            network_args="$network_args --networks=$network"
        fi
    done
    
    echo -e "${BLUE}网络参数: $network_args${NC}" >&2
    
    # 创建 Zone
    gcloud dns managed-zones create "$zone_name" \
        --description="Private access zone for $environment" \
        --dns-name="$dns_name" \
        --visibility=private \
        $network_args
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 成功创建 Zone '$zone_name'${NC}" >&2
        return 0
    else
        echo -e "${RED}✗ 创建 Zone 失败${NC}" >&2
        return 1
    fi
}

# 导入记录到新 Zone（批量导入优化版）
import_records() {
    local source_file=$1
    local target_zone=$2
    
    echo -e "\n${BLUE}导入记录到 Zone '$target_zone'...${NC}"
    
    # 统计总记录数
    local total_records=$(jq '. | length' "$source_file")
    echo -e "${CYAN}总记录数: $total_records${NC}"
    
    # 过滤掉 NS 和 SOA 记录，这些是 Zone 自动生成的
    local filtered_file="/tmp/${target_zone}-filtered-$(date +%Y%m%d-%H%M%S).json"
    jq '[.[] | select(.type != "NS" and .type != "SOA")]' "$source_file" > "$filtered_file"
    
    local filtered_count=$(jq '. | length' "$filtered_file")
    echo -e "${CYAN}需要导入的记录数（已过滤 NS/SOA）: $filtered_count${NC}"
    
    # 将 JSON 转换为 YAML 格式（gcloud dns import 需要 YAML 格式）
    local yaml_file="/tmp/${target_zone}-import-$(date +%Y%m%d-%H%M%S).yaml"
    
    echo -e "${BLUE}转换记录格式为 YAML...${NC}"
    
    # 使用 jq 将 JSON 转换为 YAML 格式
    # gcloud dns 期望的 YAML 格式示例:
    # - name: example.com.
    #   type: A
    #   ttl: 300
    #   rrdatas:
    #   - 1.2.3.4
    
    jq -r '.[] | 
        "- name: " + .name + "\n" +
        "  type: " + .type + "\n" +
        "  ttl: " + (.ttl | tostring) + "\n" +
        "  rrdatas:\n" +
        (.rrdatas | map("  - " + .) | join("\n"))
    ' "$filtered_file" > "$yaml_file"
    
    if [ ! -s "$yaml_file" ]; then
        echo -e "${YELLOW}警告: 没有需要导入的记录${NC}"
        rm -f "$filtered_file" "$yaml_file"
        return 0
    fi
    
    echo -e "${GREEN}✓ YAML 文件已生成: $yaml_file${NC}"
    
    # 使用 gcloud dns record-sets import 批量导入
    echo -e "${BLUE}开始批量导入记录...${NC}"
    
    if gcloud dns record-sets import "$yaml_file" \
        --zone="$target_zone" \
        --delete-all-existing 2>&1 | tee /tmp/import-log.txt; then
        
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}批量导入完成${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo -e "导入的记录数: ${GREEN}$filtered_count${NC}"
        echo -e "YAML 文件: ${BLUE}$yaml_file${NC}"
        
        # 清理临时文件
        rm -f "$filtered_file"
        
        return 0
    else
        echo -e "\n${RED}========================================${NC}"
        echo -e "${RED}批量导入失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo -e "${YELLOW}保留文件以供调试:${NC}"
        echo -e "  - 过滤后的 JSON: ${BLUE}$filtered_file${NC}"
        echo -e "  - YAML 导入文件: ${BLUE}$yaml_file${NC}"
        echo -e "  - 导入日志: ${BLUE}/tmp/import-log.txt${NC}"
        
        return 1
    fi
}

# 对比两个 Zone 的记录
compare_zones() {
    local source_zone=$1
    local target_zone=$2
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}对比 Zone 记录${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    local source_file="/tmp/${source_zone}-compare.json"
    local target_file="/tmp/${target_zone}-compare.json"
    
    # 导出两个 Zone 的记录
    gcloud dns record-sets list --zone="$source_zone" --format=json | \
        jq '[.[] | select(.type != "NS" and .type != "SOA") | {name, type, ttl, rrdatas}]' > "$source_file"
    
    gcloud dns record-sets list --zone="$target_zone" --format=json | \
        jq '[.[] | select(.type != "NS" and .type != "SOA") | {name, type, ttl, rrdatas}]' > "$target_file"
    
    local source_count=$(jq '. | length' "$source_file")
    local target_count=$(jq '. | length' "$target_file")
    
    echo -e "源 Zone ($source_zone) 记录数: ${BLUE}$source_count${NC}"
    echo -e "目标 Zone ($target_zone) 记录数: ${BLUE}$target_count${NC}"
    
    if [ "$source_count" -eq "$target_count" ]; then
        echo -e "${GREEN}✓ 记录数量一致${NC}"
    else
        echo -e "${YELLOW}⚠ 记录数量不一致${NC}"
    fi
    
    # 清理临时文件
    rm -f "$source_file" "$target_file"
}

# ============================================
# 主程序
# ============================================

main() {
    # 解析参数
    parse_args "$@"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GCP Cloud DNS Zone 迁移工具${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    # 检查依赖
    check_dependencies
    
    # 解析环境信息
    parse_environment
    
    # 设置项目
    set_project
    
    # 列出所有 Zones
    list_zones
    
    # 检查源 Zone 是否存在
    if ! check_zone_exists "$source_zone"; then
        echo -e "${RED}错误: 源 Zone '$source_zone' 不存在${NC}"
        exit 1
    fi
    
    # 显示源 Zone 的记录
    show_records "$source_zone"
    
    # 获取源 Zone 的网络绑定
    source_networks=$(get_zone_networks "$source_zone")
    if [ -z "$source_networks" ]; then
        echo -e "${YELLOW}警告: 源 Zone 未绑定网络，将使用配置中的网络${NC}"
        source_networks="https://www.googleapis.com/compute/v1/projects/$project/global/networks/$private_network"
    fi
    
    # 导出源 Zone 的记录
    export_file=$(export_zone_records "$source_zone")
    if [ -z "$export_file" ]; then
        echo -e "${RED}错误: 导出记录失败${NC}"
        exit 1
    fi
    
    # 获取源 Zone 的 DNS 名称
    source_dns_name=$(gcloud dns managed-zones describe "$source_zone" --format='value(dnsName)')
    
    # 统计网络数量
    IFS=';' read -ra network_check_array <<< "$source_networks"
    local network_count=0
    for net in "${network_check_array[@]}"; do
        net=$(echo "$net" | xargs)
        if [ -n "$net" ]; then
            ((network_count++))
        fi
    done
    
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}重要提示${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "由于 GCP DNS 限制，同一个 DNS 名称（${BLUE}$source_dns_name${NC}）"
    echo -e "在同一个网络中只能被一个 Private Zone 绑定。"
    echo -e ""
    echo -e "检测到源 Zone 绑定了 ${GREEN}$network_count${NC} 个网络："
    IFS=';' read -ra network_display_array <<< "$source_networks"
    for net in "${network_display_array[@]}"; do
        net=$(echo "$net" | xargs)
        if [ -n "$net" ]; then
            local net_name=$(basename "$net")
            echo -e "  - ${CYAN}$net_name${NC}"
        fi
    done
    echo -e ""
    echo -e "接下来将执行以下操作："
    echo -e "  1. 从源 Zone ${BLUE}'$source_zone'${NC} 解绑 ${GREEN}所有${NC} 网络"
    echo -e "  2. 创建新 Zone ${BLUE}'$target_zone'${NC}"
    echo -e "  3. 将 ${GREEN}相同的 $network_count 个${NC} 网络绑定到新 Zone"
    echo -e ""
    read -p "是否继续? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
    
    # 从源 Zone 解绑网络
    if ! unbind_zone_networks "$source_zone" "$source_networks"; then
        echo -e "${RED}错误: 解绑网络失败${NC}"
        exit 1
    fi
    
    # 创建新 Zone
    if ! create_zone "$target_zone" "$source_dns_name" "$source_networks"; then
        echo -e "${RED}错误: 创建 Zone 失败${NC}"
        echo -e "${YELLOW}尝试恢复源 Zone 的网络绑定...${NC}"
        
        # 尝试恢复原来的网络绑定
        IFS=';' read -ra network_array <<< "$source_networks"
        local restore_args=""
        for network in "${network_array[@]}"; do
            network=$(echo "$network" | xargs)
            if [ -n "$network" ]; then
                restore_args="$restore_args --networks=$network"
            fi
        done
        
        gcloud dns managed-zones update "$source_zone" $restore_args --quiet
        echo -e "${YELLOW}已尝试恢复源 Zone 的网络绑定${NC}"
        exit 1
    fi
    
    # 导入记录
    import_records "$export_file" "$target_zone"
    
    # 显示新 Zone 的记录
    show_records "$target_zone"
    
    # 对比验证
    compare_zones "$source_zone" "$target_zone"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}迁移完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "导出文件保存在: ${BLUE}$export_file${NC}"
    echo -e "源 Zone: ${BLUE}$source_zone${NC}"
    echo -e "新 Zone: ${BLUE}$target_zone${NC}"
    echo ""
}

# 运行主程序
main "$@"

```

## `create-private-access-success-one-by-one.sh`

```bash
#!/bin/bash

# GCP Cloud DNS Zone 迁移脚本
# 用途: 从 private-access Zone 导出记录并创建新的环境特定 Zone

# ============================================
# 环境配置
# ============================================

declare -A env_info

env_info=(
  ["dev-cn"]="project=aibang-teng-sit-api-dev cluster=dev-cn-cluster-123789 region=europe-west2 https_proxy=10.72.21.119:3128 private_network=aibang-teng-sit-api-dev-cinternal-vpc3"
  ["lex-in"]="project=aibang-teng-sit-kongs-dev cluster=lex-in-cluster-123456 region=europe-west2 https_proxy=10.72.25.50:3128 private_network=aibang-teng-sit-kongs-dev-cinternal-vpc1"
)

environment=""
project=""
region=""
private_network=""
source_zone="private-access"
target_zone=""

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# 函数定义
# ============================================

# 显示帮助信息
show_help() {
    cat <<EOF
${GREEN}========================================${NC}
${GREEN}GCP Cloud DNS Zone 迁移工具${NC}
${GREEN}========================================${NC}

用法: $(basename $0) -e ENVIRONMENT [选项]

必需参数:
  -e ENVIRONMENT   环境标识 (格式: {env}-{region})
                   可用环境: ${!env_info[@]}

可选参数:
  -s SOURCE_ZONE   源 Zone 名称 (默认: private-access)
  -h               显示此帮助信息

示例:
  $(basename $0) -e dev-cn
  $(basename $0) -e lex-in -s custom-zone

功能说明:
  1. 列出当前项目的所有 DNS Zones
  2. 从源 Zone (private-access) 导出所有记录
  3. 获取源 Zone 绑定的网络信息
  4. 创建新的 Zone: {env}-{region}-private-access
  5. 绑定相同的网络到新 Zone
  6. 导入记录到新 Zone
  7. 对比验证新旧 Zone 的记录

EOF
}

# 解析命令行参数
parse_args() {
    while getopts "e:s:h" opt; do
        case $opt in
            e)
                environment="$OPTARG"
                ;;
            s)
                source_zone="$OPTARG"
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

    # 检查必需参数
    if [ -z "$environment" ]; then
        echo -e "${RED}错误: 必须指定环境参数 -e${NC}" >&2
        show_help
        exit 1
    fi
}

# 解析环境信息
parse_environment() {
    local env_string="${env_info[$environment]}"
    
    if [ -z "$env_string" ]; then
        echo -e "${RED}错误: 未找到环境 '$environment' 的配置${NC}"
        echo -e "${YELLOW}可用环境: ${!env_info[@]}${NC}"
        exit 1
    fi
    
    # 解析环境字符串
    for item in $env_string; do
        key=$(echo "$item" | cut -d'=' -f1)
        value=$(echo "$item" | cut -d'=' -f2-)
        
        case $key in
            project)
                project="$value"
                ;;
            region)
                region="$value"
                ;;
            private_network)
                private_network="$value"
                ;;
        esac
    done
    
    # 生成目标 Zone 名称
    target_zone="${environment}-private-access"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}环境配置信息${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "环境标识: ${BLUE}$environment${NC}"
    echo -e "项目 ID: ${BLUE}$project${NC}"
    echo -e "区域: ${BLUE}$region${NC}"
    echo -e "私有网络: ${BLUE}$private_network${NC}"
    echo -e "源 Zone: ${BLUE}$source_zone${NC}"
    echo -e "目标 Zone: ${BLUE}$target_zone${NC}"
    echo ""
}

# 检查必要的命令是否存在
check_dependencies() {
    local missing_deps=()
    
    for cmd in gcloud jq; do
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
    echo -e "${BLUE}设置 GCP 项目: $project${NC}"
    gcloud config set project "$project" --quiet
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 无法设置项目 $project${NC}"
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
        return 1
    fi
    return 0
}

# 获取 Zone 绑定的网络
get_zone_networks() {
    local zone=$1
    
    echo -e "${BLUE}获取 Zone '$zone' 绑定的网络...${NC}" >&2
    
    local networks=$(gcloud dns managed-zones describe "$zone" \
        --format='value(privateVisibilityConfig.networks[].networkUrl)' 2>/dev/null)
    
    if [ -z "$networks" ]; then
        echo -e "${YELLOW}警告: Zone '$zone' 未绑定任何网络${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}绑定的网络:${NC}" >&2
    # 处理分号分隔的网络 URL
    IFS=';' read -ra network_array <<< "$networks"
    for network in "${network_array[@]}"; do
        # 去除可能的空格
        network=$(echo "$network" | xargs)
        if [ -n "$network" ]; then
            local network_name=$(basename "$network")
            echo -e "  - ${CYAN}$network_name${NC}" >&2
        fi
    done
    
    # 只输出网络 URL 到 stdout（不带颜色代码）
    echo "$networks"
}

# 导出 Zone 的所有记录
export_zone_records() {
    local zone=$1
    local export_file="/tmp/${zone}-records-$(date +%Y%m%d-%H%M%S).json"
    
    echo -e "\n${BLUE}导出 Zone '$zone' 的所有记录...${NC}" >&2
    
    gcloud dns record-sets list \
        --zone="$zone" \
        --format=json > "$export_file"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 导出记录失败${NC}" >&2
        return 1
    fi
    
    local record_count=$(jq '. | length' "$export_file")
    echo -e "${GREEN}✓ 成功导出 $record_count 条记录到: $export_file${NC}" >&2
    
    # 显示记录摘要
    echo -e "\n${CYAN}记录类型统计:${NC}" >&2
    jq -r '.[] | .type' "$export_file" | sort | uniq -c | while read count type; do
        echo -e "  ${type}: ${BLUE}$count${NC}" >&2
    done
    
    # 只输出文件路径到 stdout（不带颜色代码）
    echo "$export_file"
}

# 显示记录详情
show_records() {
    local zone=$1
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Zone '$zone' 的所有记录:${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    gcloud dns record-sets list \
        --zone="$zone" \
        --format='table[box](name, type, ttl, rrdatas)'
}

# 从 Zone 解绑网络
unbind_zone_networks() {
    local zone=$1
    local networks=$2
    
    echo -e "\n${YELLOW}========================================${NC}" >&2
    echo -e "${YELLOW}从 Zone '$zone' 解绑网络${NC}" >&2
    echo -e "${YELLOW}========================================${NC}" >&2
    
    if [ -z "$networks" ]; then
        echo -e "${YELLOW}警告: 没有需要解绑的网络${NC}" >&2
        return 0
    fi
    
    # 处理分号分隔的网络 URL
    IFS=';' read -ra network_array <<< "$networks"
    local networks_to_remove=""
    
    for network in "${network_array[@]}"; do
        network=$(echo "$network" | xargs)
        if [ -n "$network" ]; then
            local network_name=$(basename "$network")
            echo -e "${CYAN}准备解绑网络: $network_name${NC}" >&2
            
            if [ -z "$networks_to_remove" ]; then
                networks_to_remove="$network"
            else
                networks_to_remove="$networks_to_remove,$network"
            fi
        fi
    done
    
    if [ -n "$networks_to_remove" ]; then
        echo -e "${BLUE}执行解绑操作...${NC}" >&2
        
        # 使用 gcloud 更新命令移除网络绑定
        if gcloud dns managed-zones update "$zone" \
            --networks="" \
            --quiet 2>&1; then
            echo -e "${GREEN}✓ 成功从 Zone '$zone' 解绑所有网络${NC}" >&2
            return 0
        else
            echo -e "${RED}✗ 解绑网络失败${NC}" >&2
            return 1
        fi
    fi
}

# 创建新的 DNS Zone
create_zone() {
    local zone_name=$1
    local dns_name=$2
    local networks=$3
    
    echo -e "\n${BLUE}创建新的 DNS Zone: $zone_name${NC}" >&2
    
    # 检查 Zone 是否已存在
    if check_zone_exists "$zone_name"; then
        echo -e "${YELLOW}警告: Zone '$zone_name' 已存在${NC}" >&2
        read -p "是否要删除并重新创建? (y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}删除现有 Zone...${NC}" >&2
            gcloud dns managed-zones delete "$zone_name" --quiet
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误: 删除 Zone 失败${NC}" >&2
                return 1
            fi
        else
            echo -e "${YELLOW}跳过创建，使用现有 Zone${NC}" >&2
            return 0
        fi
    fi
    
    # 构建网络参数 - 处理分号分隔的网络 URL
    local network_args=""
    IFS=';' read -ra network_array <<< "$networks"
    for network in "${network_array[@]}"; do
        # 去除可能的空格
        network=$(echo "$network" | xargs)
        if [ -n "$network" ]; then
            network_args="$network_args --networks=$network"
        fi
    done
    
    echo -e "${BLUE}网络参数: $network_args${NC}" >&2
    
    # 创建 Zone
    gcloud dns managed-zones create "$zone_name" \
        --description="Private access zone for $environment" \
        --dns-name="$dns_name" \
        --visibility=private \
        $network_args
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 成功创建 Zone '$zone_name'${NC}" >&2
        return 0
    else
        echo -e "${RED}✗ 创建 Zone 失败${NC}" >&2
        return 1
    fi
}

# 导入记录到新 Zone
import_records() {
    local source_file=$1
    local target_zone=$2
    
    echo -e "\n${BLUE}导入记录到 Zone '$target_zone'...${NC}"
    
    local total_records=$(jq '. | length' "$source_file")
    local imported=0
    local skipped=0
    local failed=0
    
    # 读取记录并导入
    jq -c '.[]' "$source_file" | while read record; do
        local name=$(echo "$record" | jq -r '.name')
        local type=$(echo "$record" | jq -r '.type')
        local ttl=$(echo "$record" | jq -r '.ttl')
        local rrdatas=$(echo "$record" | jq -r '.rrdatas | join(",")')
        
        # 跳过 NS 和 SOA 记录（这些是自动生成的）
        if [[ "$type" == "NS" || "$type" == "SOA" ]]; then
            ((skipped++))
            continue
        fi
        
        echo -e "  ${CYAN}导入:${NC} $name ($type)"
        
        # 检查记录是否已存在
        if gcloud dns record-sets describe "$name" --type="$type" --zone="$target_zone" &> /dev/null; then
            echo -e "    ${YELLOW}记录已存在，跳过${NC}"
            ((skipped++))
        else
            # 创建记录
            if gcloud dns record-sets create "$name" \
                --rrdatas="$rrdatas" \
                --type="$type" \
                --ttl="$ttl" \
                --zone="$target_zone" &> /dev/null; then
                echo -e "    ${GREEN}✓ 成功${NC}"
                ((imported++))
            else
                echo -e "    ${RED}✗ 失败${NC}"
                ((failed++))
            fi
        fi
    done
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}导入完成${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "总记录数: ${BLUE}$total_records${NC}"
    echo -e "已导入: ${GREEN}$imported${NC}"
    echo -e "跳过: ${YELLOW}$skipped${NC}"
    echo -e "失败: ${RED}$failed${NC}"
}

# 对比两个 Zone 的记录
compare_zones() {
    local source_zone=$1
    local target_zone=$2
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}对比 Zone 记录${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    local source_file="/tmp/${source_zone}-compare.json"
    local target_file="/tmp/${target_zone}-compare.json"
    
    # 导出两个 Zone 的记录
    gcloud dns record-sets list --zone="$source_zone" --format=json | \
        jq '[.[] | select(.type != "NS" and .type != "SOA") | {name, type, ttl, rrdatas}]' > "$source_file"
    
    gcloud dns record-sets list --zone="$target_zone" --format=json | \
        jq '[.[] | select(.type != "NS" and .type != "SOA") | {name, type, ttl, rrdatas}]' > "$target_file"
    
    local source_count=$(jq '. | length' "$source_file")
    local target_count=$(jq '. | length' "$target_file")
    
    echo -e "源 Zone ($source_zone) 记录数: ${BLUE}$source_count${NC}"
    echo -e "目标 Zone ($target_zone) 记录数: ${BLUE}$target_count${NC}"
    
    if [ "$source_count" -eq "$target_count" ]; then
        echo -e "${GREEN}✓ 记录数量一致${NC}"
    else
        echo -e "${YELLOW}⚠ 记录数量不一致${NC}"
    fi
    
    # 清理临时文件
    rm -f "$source_file" "$target_file"
}

# ============================================
# 主程序
# ============================================

main() {
    # 解析参数
    parse_args "$@"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GCP Cloud DNS Zone 迁移工具${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    # 检查依赖
    check_dependencies
    
    # 解析环境信息
    parse_environment
    
    # 设置项目
    set_project
    
    # 列出所有 Zones
    list_zones
    
    # 检查源 Zone 是否存在
    if ! check_zone_exists "$source_zone"; then
        echo -e "${RED}错误: 源 Zone '$source_zone' 不存在${NC}"
        exit 1
    fi
    
    # 显示源 Zone 的记录
    show_records "$source_zone"
    
    # 获取源 Zone 的网络绑定
    source_networks=$(get_zone_networks "$source_zone")
    if [ -z "$source_networks" ]; then
        echo -e "${YELLOW}警告: 源 Zone 未绑定网络，将使用配置中的网络${NC}"
        source_networks="https://www.googleapis.com/compute/v1/projects/$project/global/networks/$private_network"
    fi
    
    # 导出源 Zone 的记录
    export_file=$(export_zone_records "$source_zone")
    if [ -z "$export_file" ]; then
        echo -e "${RED}错误: 导出记录失败${NC}"
        exit 1
    fi
    
    # 获取源 Zone 的 DNS 名称
    source_dns_name=$(gcloud dns managed-zones describe "$source_zone" --format='value(dnsName)')
    
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}重要提示${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "由于 GCP DNS 限制，同一个 DNS 名称（${BLUE}$source_dns_name${NC}）"
    echo -e "在同一个网络中只能被一个 Private Zone 绑定。"
    echo -e ""
    echo -e "接下来将执行以下操作："
    echo -e "  1. 从源 Zone ${BLUE}'$source_zone'${NC} 解绑网络"
    echo -e "  2. 创建新 Zone ${BLUE}'$target_zone'${NC}"
    echo -e "  3. 将网络绑定到新 Zone"
    echo -e ""
    read -p "是否继续? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
    
    # 从源 Zone 解绑网络
    if ! unbind_zone_networks "$source_zone" "$source_networks"; then
        echo -e "${RED}错误: 解绑网络失败${NC}"
        exit 1
    fi
    
    # 创建新 Zone
    if ! create_zone "$target_zone" "$source_dns_name" "$source_networks"; then
        echo -e "${RED}错误: 创建 Zone 失败${NC}"
        echo -e "${YELLOW}尝试恢复源 Zone 的网络绑定...${NC}"
        
        # 尝试恢复原来的网络绑定
        IFS=';' read -ra network_array <<< "$source_networks"
        local restore_args=""
        for network in "${network_array[@]}"; do
            network=$(echo "$network" | xargs)
            if [ -n "$network" ]; then
                restore_args="$restore_args --networks=$network"
            fi
        done
        
        gcloud dns managed-zones update "$source_zone" $restore_args --quiet
        echo -e "${YELLOW}已尝试恢复源 Zone 的网络绑定${NC}"
        exit 1
    fi
    
    # 导入记录
    import_records "$export_file" "$target_zone"
    
    # 显示新 Zone 的记录
    show_records "$target_zone"
    
    # 对比验证
    compare_zones "$source_zone" "$target_zone"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}迁移完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "导出文件保存在: ${BLUE}$export_file${NC}"
    echo -e "源 Zone: ${BLUE}$source_zone${NC}"
    echo -e "新 Zone: ${BLUE}$target_zone${NC}"
    echo ""
}

# 运行主程序
main "$@"

```

