# Shell Scripts Collection

Generated on: 2026-01-31 18:14:01
Directory: /Users/lex/git/knowledge/gcp/gce

## `verify-mig-status.sh`

```bash
#!/bin/bash

# ==============================================================================
# Script Name: verify-mig-status.sh
# Description: Verifies the status of Managed Instance Groups (MIG) and their instances.
# Usage: ./verify-mig-status.sh <mig-keyword>
# ==============================================================================

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <mig-keyword>"
    echo -e "${BLUE}Example:${NC} $0 'web-server'"
    exit 1
}

# --- Check Arguments ---
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Error: Missing MIG keyword argument.${NC}"
    show_usage
fi

KEYWORD=$1
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   GCP MIG Status Verification Tool                 ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Keyword:${NC} $KEYWORD"
echo -e ""

# --- 1. Discover MIGs ---
echo -e "${YELLOW}[1/3] Searching for MIGs matching '$KEYWORD'...${NC}"
# Use table for user display
gcloud compute instance-groups managed list --filter="name ~ $KEYWORD" --format="table(name,zone,region,targetSize,status.isStable)"

# Use value(name,zone,region) for script processing - tab separated, no wrapping
MIG_LIST=$(gcloud compute instance-groups managed list --filter="name ~ $KEYWORD" --format="value(name,zone,region)")

if [ -z "$MIG_LIST" ]; then
    echo -e "${RED}❌ No Managed Instance Groups found matching keyword '$KEYWORD'.${NC}"
    exit 1
fi

# --- 2. Iterate through found MIGs ---
while IFS=$'\t' read -r name zone region; do
    [ -z "$name" ] && continue

    # Determine if it's regional or zonal
    if [ -n "$zone" ]; then
        # Zonal MIG
        ZONE_NAME=$(echo "$zone" | awk -F'/' '{print $NF}')
        LOCATION_FLAG="--zone=$ZONE_NAME"
        LOCATION_TYPE="zonal"
        LOCATION="$ZONE_NAME"
    else
        # Regional MIG
        REGION_NAME=$(echo "$region" | awk -F'/' '{print $NF}')
        LOCATION_FLAG="--region=$REGION_NAME"
        LOCATION_TYPE="regional"
        LOCATION="$REGION_NAME"
    fi

    echo -e "\n${BLUE}>>> Analyzing MIG: ${GREEN}$name${BLUE} (Location: $LOCATION, Type: $LOCATION_TYPE)${NC}"

    # Get MIG details
    MIG_DESC=$(gcloud compute instance-groups managed describe "$name" $LOCATION_FLAG --format="json")
    TARGET_TEMPLATE=$(echo "$MIG_DESC" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
    IS_STABLE=$(echo "$MIG_DESC" | jq -r '.status.isStable')
    UPDATE_POLICY=$(echo "$MIG_DESC" | jq -r '.updatePolicy.type')
    
    echo -e "${BLUE}Target Template:${NC} $TARGET_TEMPLATE"
    echo -e "${BLUE}Status Stable:  ${NC} $([ "$IS_STABLE" == "true" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO (Updating...)${NC}")"
    echo -e "${BLUE}Update Policy:  ${NC} $UPDATE_POLICY"

    # --- 3. Instance Level Details ---
    echo -e "\n${YELLOW}[2/3] Fetching instance details...${NC}"
    
    # 获取实例列表和健康状态
    INSTANCE_DATA=$(gcloud compute instance-groups managed list-instances "$name" $LOCATION_FLAG --format="json")
    
    # 打印表头
    printf "${BLUE}%-35s %-12s %-12s %-15s %-30s %-20s${NC}\n" \
        "INSTANCE_NAME" "STATUS" "ACTION" "HEALTH" "TEMPLATE" "UPTIME"
    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    
    # 遍历每个实例
    echo "$INSTANCE_DATA" | jq -c '.[]' | while read -r instance; do
        inst_name=$(echo "$instance" | jq -r '.instance' | awk -F'/' '{print $NF}')
        inst_status=$(echo "$instance" | jq -r '.instanceStatus // "UNKNOWN"')
        inst_action=$(echo "$instance" | jq -r '.currentAction // "NONE"')
        inst_template=$(echo "$instance" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
        
        # 获取健康状态
        inst_health=$(echo "$instance" | jq -r '.instanceHealth[0].detailedHealthState // "N/A"')
        
        # 对于 regional MIG，需要从实例 URL 中提取 zone
        # URL 格式: https://www.googleapis.com/compute/v1/projects/PROJECT/zones/ZONE/instances/INSTANCE
        if [ "$LOCATION_TYPE" == "regional" ]; then
            inst_url=$(echo "$instance" | jq -r '.instance')
            # 使用 sed 提取 zones/ 后面的部分
            inst_zone=$(echo "$inst_url" | sed -n 's|.*/zones/\([^/]*\)/.*|\1|p')
            INST_LOCATION_FLAG="--zone=$inst_zone"
        else
            INST_LOCATION_FLAG="$LOCATION_FLAG"
        fi
        
        # 获取创建时间并计算运行时长
        CREATE_TIME=$(gcloud compute instances describe "$inst_name" $INST_LOCATION_FLAG --format="value(creationTimestamp)")
        
        # 计算运行时长（参考 get_instance_uptime.sh）
        if [ -n "$CREATE_TIME" ]; then
            START_TIME_UTC=$(TZ=UTC date -d"$CREATE_TIME" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
            CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            SECONDS1=$(date -u -d "$CURRENT_TIME" +"%s")
            SECONDS2=$(date -u -d "$START_TIME_UTC" +"%s")
            DIFF_SECONDS=$((SECONDS1 - SECONDS2))
            
            # 计算天、小时、分钟
            DAYS=$((DIFF_SECONDS / 86400))
            HOURS=$(((DIFF_SECONDS % 86400) / 3600))
            MINUTES=$(((DIFF_SECONDS % 3600) / 60))
            
            if [ $DAYS -gt 0 ]; then
                UPTIME="${DAYS}d ${HOURS}h ${MINUTES}m"
            else
                UPTIME="${HOURS}h ${MINUTES}m"
            fi
        else
            UPTIME="N/A"
        fi
        
        # 格式化显示
        # Action 高亮
        if [ "$inst_action" != "NONE" ]; then
            DISP_ACTION="${YELLOW}${inst_action}${NC}"
        else
            DISP_ACTION="${inst_action}"
        fi
        
        # Template 对比
        if [ "$inst_template" != "$TARGET_TEMPLATE" ]; then
            DISP_TEMPLATE="${RED}${inst_template}*${NC}"
        else
            DISP_TEMPLATE="${GREEN}${inst_template}${NC}"
        fi
        
        # Health 状态颜色
        case "$inst_health" in
            "HEALTHY")
                DISP_HEALTH="${GREEN}${inst_health}${NC}"
                ;;
            "UNHEALTHY")
                DISP_HEALTH="${RED}${inst_health}${NC}"
                ;;
            "N/A")
                DISP_HEALTH="${YELLOW}${inst_health}${NC}"
                ;;
            *)
                DISP_HEALTH="${inst_health}"
                ;;
        esac
        
        printf "%-35s %-12s %b %-15s %b %-20s\n" \
            "$inst_name" "$inst_status" "$DISP_ACTION" "$DISP_HEALTH" "$DISP_TEMPLATE" "$UPTIME"
    done
    
    echo ""

done <<< "$MIG_LIST"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}   Verification Complete!                           ${NC}"
echo -e "${BLUE}====================================================${NC}"

```

## `verify-gcp-and-gke-status.sh`

```bash
#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Step 0: GCE Forwarding Rules ===${NC}"
echo "Listing forwarding rules..."
gcloud compute forwarding-rules list

echo ""
read -p "Enter a Forwarding Rule name to describe (or press Enter to skip): " fr_name

if [ -n "$fr_name" ]; then
    echo -e "${YELLOW}Describing Forwarding Rule: $fr_name${NC}"
    gcloud compute forwarding-rules describe "$fr_name"
else
    echo "Skipping description."
fi

echo ""
echo -e "${GREEN}=== Step 1: Managed Instance Groups (MIGs) ===${NC}"
echo "Listing managed instance groups..."
gcloud compute instance-groups managed list

echo ""
echo -e "${GREEN}=== Step 2: Filter MIGs and check Autoscaler ===${NC}"
read -p "Enter a keyword to filter Instance Group names (or press Enter to skip filtering): " mig_keyword

if [ -n "$mig_keyword" ]; then
    echo -e "${YELLOW}Filtering for MIGs containing '$mig_keyword' and showing autoscaler info...${NC}"
    # Fetch JSON, filter by name containing keyword (using gcloud filter or jq), then extract autoscaler
    # Using gcloud filter for efficiency
    gcloud compute instance-groups managed list --filter="name ~ $mig_keyword" --format="json" | jq '.[] | {name: .name, autoscaler: .autoscaler}'
else
    echo "Skipping filtering."
fi

echo ""
echo -e "${GREEN}=== Step 3: DNS Managed Zones ===${NC}"
echo "Listing managed zones..."
# Get list of zones (name only) for selection
zones=$(gcloud dns managed-zones list --format="value(name)")
# Display with index
i=1
declare -a zone_array
for zone in $zones; do
    echo "[$i] $zone"
    zone_array[$i]=$zone
    ((i++))
done

echo ""
echo -e "${GREEN}=== Step 4: Select DNS Zone to List Record Sets ===${NC}"
if [ ${#zone_array[@]} -eq 0 ]; then
    echo "No DNS zones found."
else
    read -p "Select a zone number (1-$((i-1))) to list record sets: " zone_choice
    selected_zone=${zone_array[$zone_choice]}

    if [ -n "$selected_zone" ]; then
        echo -e "${YELLOW}Listing record sets for zone: $selected_zone${NC}"
        gcloud dns record-sets list --zone="$selected_zone"
    else
        echo -e "${RED}Invalid selection.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Step 5: Kubernetes Namespaces ===${NC}"
echo "Listing namespaces..."
namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')

# Display with index
j=1
declare -a ns_array
for ns in $namespaces; do
    echo "[$j] $ns"
    ns_array[$j]=$ns
    ((j++))
done

echo ""
echo -e "${GREEN}=== Step 6: Select Namespace to List Resources ===${NC}"
if [ ${#ns_array[@]} -eq 0 ]; then
    echo "No namespaces found."
else
    read -p "Select a namespace number (1-$((j-1))) to list all resources: " ns_choice
    selected_ns=${ns_array[$ns_choice]}

    if [ -n "$selected_ns" ]; then
        echo -e "${YELLOW}Listing all resources in namespace: $selected_ns${NC}"
        kubectl get all -n "$selected_ns"
    else
        echo -e "${RED}Invalid selection.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Verification Complete ===${NC}"

```

## `rolling-replace-instance-groups.sh`

```bash
#!/bin/bash
# rolling-replace-instance-groups.sh
# 滚动替换匹配关键字的 MIG 实例组脚本

set -e

# ============================================
# 配置区域
# ============================================
PROJECT_ID="${PROJECT_ID:-}"
KEYWORD="${KEYWORD:-}"

# 滚动替换配置
MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-0}"    # 不允许不可用的实例
MAX_SURGE="${MAX_SURGE:-3}"                # 允许超出目标数的实例数
MIN_READY="${MIN_READY:-10s}"              # 新实例准备就绪的最短时间

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# 辅助函数
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

滚动替换匹配关键字的 MIG 实例组

选项:
    -p, --project PROJECT_ID        GCP 项目 ID (必需)
    -k, --keyword KEYWORD           实例组名称关键字 (必需)
    -u, --max-unavailable NUM       最大不可用实例数 (默认: 0)
    -s, --max-surge NUM             最大超出实例数 (默认: 3)
    -r, --min-ready TIME            最小就绪时间 (默认: 10s)
    --dry-run                       模拟运行，不实际执行
    -h, --help                      显示此帮助信息

示例:
    # 替换名称包含 "squid" 的所有实例组
    $0 --project my-project --keyword squid

    # 自定义滚动替换参数
    $0 -p my-project -k squid -u 1 -s 5 -r 30s

    # 模拟运行
    $0 --project my-project --keyword squid --dry-run

说明:
    --max-unavailable: 滚动替换期间允许不可用的最大实例数
                       设置为 0 确保高可用性
    
    --max-surge:       滚动替换期间允许超出目标数的最大实例数
                       设置为 3 表示可以临时增加 3 个实例
    
    --min-ready:       新实例被视为就绪的最短等待时间
                       设置为 10s 表示实例需在 10 秒内变为就绪状态

EOF
    exit 0
}

# 检查必要的命令
check_prerequisites() {
    log_info "检查必要的命令..."
    
    local missing_commands=()
    
    for cmd in gcloud jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "缺少必要的命令: ${missing_commands[*]}"
        log_error "请安装缺失的命令后重试"
        exit 1
    fi
    
    log_success "所有必要命令已安装"
}

# 验证 gcloud 认证
check_gcloud_auth() {
    log_info "验证 gcloud 认证状态..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "未检测到活动的 gcloud 认证"
        log_error "请运行: gcloud auth login"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
    log_success "已认证账户: $active_account"
}

# 验证项目存在
check_project() {
    local project=$1
    log_info "验证项目 [$project] 是否存在..."
    
    if ! gcloud projects describe "$project" &> /dev/null; then
        log_error "项目 [$project] 不存在或无权访问"
        exit 1
    fi
    
    log_success "项目 [$project] 验证通过"
}

# 获取匹配关键字的实例组列表
get_instance_groups() {
    local keyword=$1
    local project=$2
    
    log_info "查找名称包含 [$keyword] 的实例组..."
    
    local instance_groups
    instance_groups=$(gcloud compute instance-groups managed list \
        --project="$project" \
        --filter="name~$keyword" \
        --format="json" 2>/dev/null)
    
    if [ -z "$instance_groups" ] || [ "$instance_groups" = "[]" ]; then
        log_error "未找到匹配关键字 [$keyword] 的实例组"
        exit 1
    fi
    
    echo "$instance_groups"
}

# 显示实例组信息
display_instance_groups() {
    local instance_groups=$1
    
    log_info "找到以下实例组:"
    echo ""
    echo "--------------------------------------------------------------------------------------------------------"
    printf "%-40s %-20s %-15s %-10s\n" "名称" "位置" "类型" "实例数"
    echo "--------------------------------------------------------------------------------------------------------"
    
    echo "$instance_groups" | jq -r '.[] | "\(.name)|\(.zone // .region)|\(if .zone then "zonal" else "regional" end)|\(.targetSize)"' | \
    while IFS='|' read -r name location type size; do
        printf "%-40s %-20s %-15s %-10s\n" "$name" "$location" "$type" "$size"
    done
    
    echo "--------------------------------------------------------------------------------------------------------"
    echo ""
}

# 获取实例组当前状态
get_instance_group_status() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    
    local location_flag
    if [ "$location_type" = "zonal" ]; then
        location_flag="--zone=$location"
    else
        location_flag="--region=$location"
    fi
    
    gcloud compute instance-groups managed describe "$name" \
        $location_flag \
        --project="$project" \
        --format="json" 2>/dev/null
}

# 检查实例组是否稳定
check_instance_group_stable() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    
    local status
    status=$(get_instance_group_status "$name" "$location" "$location_type" "$project")
    
    local is_stable
    is_stable=$(echo "$status" | jq -r '.status.isStable // false')
    
    if [ "$is_stable" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# 等待实例组稳定
wait_for_stable() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    local max_wait=${5:-600}  # 默认最多等待 10 分钟
    
    log_info "等待实例组 [$name] 稳定..."
    
    local elapsed=0
    local check_interval=15
    
    while [ $elapsed -lt $max_wait ]; do
        if check_instance_group_stable "$name" "$location" "$location_type" "$project"; then
            log_success "实例组 [$name] 已稳定"
            return 0
        fi
        
        echo -n "."
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo ""
    log_warning "实例组 [$name] 稳定检查超时 (${max_wait}s)"
    return 1
}

# 执行滚动替换
rolling_replace() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    local max_unavailable=$5
    local max_surge=$6
    local min_ready=$7
    local dry_run=$8
    
    log_step "开始滚动替换实例组: $name"
    
    local location_flag
    if [ "$location_type" = "zonal" ]; then
        location_flag="--zone=$location"
    else
        location_flag="--region=$location"
    fi
    
    if [ "$dry_run" = "true" ]; then
        log_warning "[DRY RUN] 模拟执行滚动替换:"
        log_warning "  实例组: $name"
        log_warning "  位置: $location ($location_type)"
        log_warning "  max-unavailable: $max_unavailable"
        log_warning "  max-surge: $max_surge"
        log_warning "  min-ready: $min_ready"
        return 0
    fi
    
    # 执行滚动替换
    log_info "执行命令: gcloud compute instance-groups managed rolling-action replace $name"
    log_info "  参数: --max-unavailable=$max_unavailable --max-surge=$max_surge --min-ready=$min_ready"
    
    if gcloud compute instance-groups managed rolling-action replace "$name" \
        --max-unavailable="$max_unavailable" \
        --max-surge="$max_surge" \
        --min-ready="$min_ready" \
        $location_flag \
        --project="$project" 2>&1; then
        
        log_success "实例组 [$name] 滚动替换命令已提交"
        return 0
    else
        log_error "实例组 [$name] 滚动替换失败"
        return 1
    fi
}

# 处理所有实例组
process_instance_groups() {
    local instance_groups=$1
    local project=$2
    local max_unavailable=$3
    local max_surge=$4
    local min_ready=$5
    local dry_run=$6
    
    local total
    total=$(echo "$instance_groups" | jq '. | length')
    local current=0
    local success=0
    local failed=0
    local failed_groups=()
    
    log_info "========================================="
    log_info "开始处理 $total 个实例组"
    log_info "========================================="
    
    echo "$instance_groups" | jq -c '.[]' | while read -r group; do
        current=$((current + 1))
        
        local name
        local location
        local location_type
        
        name=$(echo "$group" | jq -r '.name')
        
        # 判断是 zonal 还是 regional
        if echo "$group" | jq -e '.zone' > /dev/null 2>&1; then
            location=$(echo "$group" | jq -r '.zone')
            location_type="zonal"
        else
            location=$(echo "$group" | jq -r '.region')
            location_type="regional"
        fi
        
        log_info ""
        log_info "========================================="
        log_info "[$current/$total] 处理实例组: $name"
        log_info "位置: $location ($location_type)"
        log_info "========================================="
        
        # 检查初始状态
        if [ "$dry_run" != "true" ]; then
            if ! check_instance_group_stable "$name" "$location" "$location_type" "$project"; then
                log_warning "实例组 [$name] 当前不稳定，等待稳定后再操作..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" 300; then
                    log_error "实例组 [$name] 初始状态不稳定，跳过"
                    failed=$((failed + 1))
                    failed_groups+=("$name")
                    continue
                fi
            fi
        fi
        
        # 执行滚动替换
        if rolling_replace "$name" "$location" "$location_type" "$project" \
            "$max_unavailable" "$max_surge" "$min_ready" "$dry_run"; then
            
            # 等待操作完成
            if [ "$dry_run" != "true" ]; then
                log_info "等待滚动替换完成..."
                if wait_for_stable "$name" "$location" "$location_type" "$project" 1800; then
                    success=$((success + 1))
                    log_success "实例组 [$name] 滚动替换完成"
                else
                    log_warning "实例组 [$name] 滚动替换可能仍在进行中"
                    log_warning "请手动检查状态"
                fi
            else
                success=$((success + 1))
            fi
        else
            failed=$((failed + 1))
            failed_groups+=("$name")
        fi
        
        # 在处理下一个实例组前稍作等待
        if [ $current -lt $total ] && [ "$dry_run" != "true" ]; then
            log_info "等待 30 秒后处理下一个实例组..."
            sleep 30
        fi
    done
    
    # 输出总结
    log_info ""
    log_info "========================================="
    log_info "处理完成"
    log_info "========================================="
    log_success "成功: $success 个实例组"
    
    if [ $failed -gt 0 ]; then
        log_error "失败: $failed 个实例组"
        log_error "失败列表: ${failed_groups[*]}"
        return 1
    fi
    
    return 0
}

# ============================================
# 主程序
# ============================================

main() {
    local DRY_RUN=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -k|--keyword)
                KEYWORD="$2"
                shift 2
                ;;
            -u|--max-unavailable)
                MAX_UNAVAILABLE="$2"
                shift 2
                ;;
            -s|--max-surge)
                MAX_SURGE="$2"
                shift 2
                ;;
            -r|--min-ready)
                MIN_READY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                ;;
        esac
    done
    
    # 验证必需参数
    if [ -z "$PROJECT_ID" ]; then
        log_error "缺少必需参数: --project"
        show_usage
    fi
    
    if [ -z "$KEYWORD" ]; then
        log_error "缺少必需参数: --keyword"
        show_usage
    fi
    
    # 显示配置
    log_info "========================================="
    log_info "配置信息"
    log_info "========================================="
    log_info "项目 ID: $PROJECT_ID"
    log_info "关键字: $KEYWORD"
    log_info "最大不可用: $MAX_UNAVAILABLE"
    log_info "最大超出: $MAX_SURGE"
    log_info "最小就绪: $MIN_READY"
    [ "$DRY_RUN" = "true" ] && log_warning "模式: DRY RUN (模拟运行)"
    log_info "========================================="
    echo ""
    
    # 检查前置条件
    check_prerequisites
    check_gcloud_auth
    check_project "$PROJECT_ID"
    
    # 获取实例组列表
    local instance_groups
    instance_groups=$(get_instance_groups "$KEYWORD" "$PROJECT_ID")
    
    # 显示实例组信息
    display_instance_groups "$instance_groups"
    
    # 确认操作
    if [ "$DRY_RUN" != "true" ]; then
        local total
        total=$(echo "$instance_groups" | jq '. | length')
        
        log_warning ""
        log_warning "⚠️  警告: 此操作将对 $total 个实例组执行滚动替换"
        log_warning "⚠️  所有实例将被逐步替换为新实例"
        log_warning ""
        read -p "确认继续? (输入 'yes' 确认): " CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 处理所有实例组
    if process_instance_groups "$instance_groups" "$PROJECT_ID" \
        "$MAX_UNAVAILABLE" "$MAX_SURGE" "$MIN_READY" "$DRY_RUN"; then
        
        log_success ""
        log_success "========================================="
        log_success "所有实例组处理完成！"
        log_success "========================================="
        exit 0
    else
        log_error ""
        log_error "========================================="
        log_error "部分实例组处理失败，请检查日志"
        log_error "========================================="
        exit 1
    fi
}

# 执行主程序
main "$@"

```

## `instance-uptime-gemini.sh`

```bash
#!/bin/bash

# 脚本: instance-uptime-gemini.sh
# 用途: 获取GCE实例的时间戳信息并转换为不同时区的时间.
# 用法: ./instance-uptime-gemini.sh <instance-name> <zone>
# 示例: ./instance-uptime-gemini.sh my-instance asia-east2-a

# 1. 参数校验
if [ "$#" -ne 2 ]; then
    echo "错误: 需要提供2个参数."
    echo "用法: $0 <instance-name> <zone>"
    echo "示例: $0 my-instance asia-east2-a"
    exit 1
fi

INSTANCE_NAME=$1
ZONE=$2

# 2. 依赖检查
if ! command -v gcloud &> /dev/null; then
    echo "错误: gcloud 命令未找到. 请确保 Google Cloud SDK 已安装并配置."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "错误: jq 命令未找到. 请使用 'brew install jq' 或 'apt-get install jq' 安装."
    exit 1
fi

# 3. 获取实例信息
echo "正在获取实例 '$INSTANCE_NAME' 在区域 '$ZONE' 的信息..."
INSTANCE_INFO=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format=json 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$INSTANCE_INFO" ]; then
    echo "错误: 无法获取实例信息. 请检查实例名称和区域是否正确."
    exit 1
fi

# 4. 时间转换函数
# $1: 时间戳字符串 (e.g., "2024-01-15T10:30:45.123-08:00")
# $2: 时间点的标签 (e.g., "创建时间")
convert_time() {
    local timestamp=$1
    local label=$2
    
    if [ -z "$timestamp" ] || [ "$timestamp" == "null" ]; then
        printf "| %-15s | %-35s | %-25s | %-25s | %-25s |\n" "$label" "N/A" "N/A" "N/A" "N/A"
        return
    fi
    
    local original_time="$timestamp"
    local date_cmd="date"

    # 检查是否为macOS，并使用gdate（如果存在）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v gdate &>/dev/null; then
            date_cmd="gdate"
        else
            echo "警告: 在macOS上, 建议安装 'gdate' (brew install coreutils) 以获得更强大的日期处理功能." >&2
        fi
    fi

    # 尝试转换时间
    local china_time=$(TZ='Asia/Shanghai' $date_cmd -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local utc_time=$(TZ='UTC' $date_cmd -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local london_time=$(TZ='Europe/London' $date_cmd -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    
    # 如果转换失败，显示错误信息
    if [ -z "$china_time" ]; then
        china_time="解析失败"
        utc_time="解析失败"
        london_time="解析失败"
    fi
    
    printf "| %-15s | %-35s | %-25s | %-25s | %-25s |\n" "$label" "$original_time" "$china_time" "$utc_time" "$london_time"
}

# 5. 提取并显示时间信息
echo "正在提取和转换时间信息..."

CREATION_TIMESTAMP=$(echo "$INSTANCE_INFO" | jq -r '.creationTimestamp // empty')
LAST_START_TIMESTAMP=$(echo "$INSTANCE_INFO" | jq -r '.lastStartTimestamp // empty')
LAST_STOP_TIMESTAMP=$(echo "$INSTANCE_INFO" | jq -r '.lastStopTimestamp // empty')

# 打印表头
echo ""
echo "实例 '$INSTANCE_NAME' 的时间信息:"
printf "+-----------------+-------------------------------------+---------------------------+---------------------------+---------------------------+\n"
printf "| %-15s | %-35s | %-25s | %-25s | %-25s |\n" "时间点" "原始时间" "中国时间 (CST)" "UTC 时间" "伦敦时间 (GMT/BST)"
printf "+-----------------+-------------------------------------+---------------------------+---------------------------+---------------------------+\n"

# 打印每一行数据
convert_time "$CREATION_TIMESTAMP" "创建时间"
convert_time "$LAST_START_TIMESTAMP" "最后启动时间"
convert_time "$LAST_STOP_TIMESTAMP" "最后停止时间"

printf "+-----------------+-------------------------------------+---------------------------+---------------------------+---------------------------+\n"
echo ""
echo "脚本执行完毕."

```

## `get_instance_uptime.sh`

```bash
#!/bin/bash
keyword="aibangrt"
instance_list=$(gcloud compute instances list --filter="name~${keyword}*" --format="value(name,ZONE)")

while read -r instances; do
  NAME=$(echo "$instances" | cut -f1)
  zone=$(echo "$instances" | cut -f2)

  # 实例启动时间(本地时区时间)
  START_TIMESTAMP=$(gcloud compute instances describe $NAME --zone $zone --format="value(creationTimestamp)")

  # 本地时间转换为UTC时间
  START_TIME_UTC=$(TZ=UTC date -d"$START_TIMESTAMP" +"%Y-%m-%dT%H:%M:%SZ")

  # 当前UTC时间
  CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 基于UTC时间计算持续时间
  #DURATION=$(date -u -d "$CURRENT_TIME" -d "$START_TIME_UTC" +"%H:%M:%S")
  SECONDS1=$(date -u -d "$CURRENT_TIME" +"%s")
  SECONDS2=$(date -u -d "$START_TIME_UTC" +"%s")
  # 计算差值
  DIFF_SECONDS=$((SECONDS1 - SECONDS2))
  # # 将差值转换为时:分:秒格式
  DIFF_TIME=$(date -u -d "@$DIFF_SECONDS" +"%H:%M:%S")

  echo "Instance $NAME has been running for: $DIFF_TIME"

done <<< "$instance_list"

```

## `get_instance_timestamps.sh`

```bash
#!/bin/bash

# 设置输出文件路径（您可以根据需要修改路径，确保在允许的目录内）
OUTPUT_FILE="/Users/lex/git/knowledge/gcp/gce/instance_timestamps.txt"

# 检查是否提供了实例名称和区域，否则使用默认值或提示用户输入
if [ $# -lt 2 ]; then
  echo "使用方法: $0 <实例名称> <区域>"
  echo "示例: $0 my-instance us-central1-a"
  echo "您也可以编辑此脚本，在下方设置默认实例和区域。"
  exit 1
fi

INSTANCE_NAME="$1"
ZONE="$2"

echo "正在获取实例 $INSTANCE_NAME (区域: $ZONE) 的时间戳信息..."

# 获取创建时间
CREATION_TIME=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(creationTimestamp)" 2>/dev/null)
if [ -z "$CREATION_TIME" ]; then
  CREATION_TIME="无法获取（实例不存在或无权限）"
fi

# 获取最后启动时间
LAST_START_TIME=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(lastStartTimestamp)" 2>/dev/null)
if [ -z "$LAST_START_TIME" ]; then
  LAST_START_TIME="无法获取（实例不存在或无权限）"
fi

# 获取最后停止时间
LAST_STOP_TIME=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(lastStopTimestamp)" 2>/dev/null)
if [ -z "$LAST_STOP_TIME" ]; then
  LAST_STOP_TIME="无法获取（实例不存在或从未停止）"
fi

# 将结果输出到控制台
echo "实例: $INSTANCE_NAME (区域: $ZONE)"
echo "  创建时间 (creationTimestamp): $CREATION_TIME"
echo "  最后启动时间 (lastStartTimestamp): $LAST_START_TIME"
echo "  最后停止时间 (lastStopTimestamp): $LAST_STOP_TIME"

# 将结果保存到文件
echo "实例: $INSTANCE_NAME (区域: $ZONE)" >> "$OUTPUT_FILE"
echo "  创建时间 (creationTimestamp): $CREATION_TIME" >> "$OUTPUT_FILE"
echo "  最后启动时间 (lastStartTimestamp): $LAST_START_TIME" >> "$OUTPUT_FILE"
echo "  最后停止时间 (lastStopTimestamp): $LAST_STOP_TIME" >> "$OUTPUT_FILE"
echo "--------------------------------" >> "$OUTPUT_FILE"

echo "结果已保存到 $OUTPUT_FILE"

```

