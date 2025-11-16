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
