# Shell Scripts Collection

Generated on: 2025-11-16 11:16:33
Directory: /Users/lex/git/knowledge/monitor/gce-disk

## `rolling-recreate-instances.sh`

```bash
#!/bin/bash
# rolling-recreate-instances.sh
# 滚动重建 MIG 实例脚本 - 避免服务中断

set -e

# ============================================
# 配置区域
# ============================================
PROJECT_ID="${PROJECT_ID:-your-project-id}"
MIG_NAME="${MIG_NAME:-squid-proxy-mig}"
ZONE="${ZONE:-us-central1-a}"

# 滚动更新配置
BATCH_SIZE=1                    # 每批次重建的实例数量
WAIT_TIME=300                   # 每批次之间等待时间（秒），默认 5 分钟
HEALTH_CHECK_INTERVAL=30        # 健康检查间隔（秒）
MAX_WAIT_TIME=600               # 单个实例最大等待时间（秒），默认 10 分钟

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

滚动重建 MIG 中的实例，避免服务中断

选项:
    -p, --project PROJECT_ID        GCP 项目 ID
    -m, --mig MIG_NAME              MIG 名称
    -z, --zone ZONE                 Zone 名称
    -b, --batch-size SIZE           每批次重建实例数量 (默认: 1)
    -w, --wait-time SECONDS         批次间等待时间/秒 (默认: 300)
    -i, --instances INSTANCE_LIST   指定要重建的实例列表（逗号分隔）
    -a, --all                       重建所有实例
    -d, --disk-threshold PERCENT    只重建磁盘使用率超过阈值的实例
    --dry-run                       模拟运行，不实际执行
    -h, --help                      显示此帮助信息

示例:
    # 重建指定的实例
    $0 -i instance-1,instance-2,instance-3

    # 重建所有实例，每批 2 个，等待 10 分钟
    $0 --all --batch-size 2 --wait-time 600

    # 只重建磁盘使用率超过 80% 的实例
    $0 --disk-threshold 80

    # 模拟运行
    $0 --all --dry-run

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

# 获取 MIG 中的所有实例
get_all_instances() {
    log_info "获取 MIG [$MIG_NAME] 中的所有实例..."
    
    local instances
    instances=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --format="value(instance)" 2>/dev/null)
    
    if [ -z "$instances" ]; then
        log_error "未找到任何实例"
        exit 1
    fi
    
    echo "$instances"
}

# 获取磁盘使用率超过阈值的实例
get_high_disk_instances() {
    local threshold=$1
    log_info "查询磁盘使用率超过 ${threshold}% 的实例..."
    
    # 这里需要通过 Cloud Monitoring API 查询
    # 简化版本：返回所有实例（实际使用时需要集成 Monitoring API）
    log_warning "磁盘使用率查询功能需要集成 Cloud Monitoring API"
    log_warning "当前返回所有实例，请手动确认"
    
    get_all_instances
}

# 检查实例状态
check_instance_status() {
    local instance_name=$1
    
    gcloud compute instances describe "$instance_name" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --format="value(status)" 2>/dev/null || echo "UNKNOWN"
}

# 等待实例达到 RUNNING 状态
wait_for_instance_running() {
    local instance_name=$1
    local max_wait=$2
    local elapsed=0
    
    log_info "等待实例 [$instance_name] 启动..."
    
    while [ $elapsed -lt $max_wait ]; do
        local status
        status=$(check_instance_status "$instance_name")
        
        if [ "$status" = "RUNNING" ]; then
            log_success "实例 [$instance_name] 已启动"
            return 0
        fi
        
        echo -n "."
        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done
    
    echo ""
    log_error "实例 [$instance_name] 启动超时"
    return 1
}

# 获取 MIG 当前实例数量
get_mig_current_size() {
    gcloud compute instance-groups managed describe "$MIG_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --format="value(targetSize)" 2>/dev/null
}

# 等待 MIG 稳定
wait_for_mig_stable() {
    log_info "等待 MIG 稳定..."
    
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status
        status=$(gcloud compute instance-groups managed describe "$MIG_NAME" \
            --zone="$ZONE" \
            --project="$PROJECT_ID" \
            --format="value(status.isStable)" 2>/dev/null)
        
        if [ "$status" = "True" ]; then
            log_success "MIG 已稳定"
            return 0
        fi
        
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo ""
    log_warning "MIG 稳定检查超时，继续执行"
    return 0
}

# 重建单个实例
recreate_instance() {
    local instance_name=$1
    local dry_run=$2
    
    log_info "准备重建实例: $instance_name"
    
    if [ "$dry_run" = "true" ]; then
        log_warning "[DRY RUN] 模拟重建实例: $instance_name"
        return 0
    fi
    
    # 执行重建
    if gcloud compute instance-groups managed recreate-instances "$MIG_NAME" \
        --instances="$instance_name" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" 2>&1; then
        
        log_success "实例 [$instance_name] 重建命令已提交"
        return 0
    else
        log_error "实例 [$instance_name] 重建失败"
        return 1
    fi
}

# 滚动重建实例列表
rolling_recreate() {
    local instances=("$@")
    local total=${#instances[@]}
    local current=0
    local failed=()
    
    log_info "========================================="
    log_info "开始滚动重建"
    log_info "总实例数: $total"
    log_info "批次大小: $BATCH_SIZE"
    log_info "批次间隔: ${WAIT_TIME}s"
    log_info "========================================="
    
    # 按批次处理
    for ((i=0; i<total; i+=BATCH_SIZE)); do
        local batch_num=$((i/BATCH_SIZE + 1))
        local batch_instances=("${instances[@]:i:BATCH_SIZE}")
        
        log_info ""
        log_info "========================================="
        log_info "批次 $batch_num / $(((total + BATCH_SIZE - 1) / BATCH_SIZE))"
        log_info "实例: ${batch_instances[*]}"
        log_info "========================================="
        
        # 重建当前批次的实例
        for instance in "${batch_instances[@]}"; do
            current=$((current + 1))
            log_info "[$current/$total] 重建实例: $instance"
            
            if ! recreate_instance "$instance" "$DRY_RUN"; then
                failed+=("$instance")
                log_error "实例 [$instance] 重建失败，继续处理下一个"
                continue
            fi
        done
        
        # 等待 MIG 稳定
        if [ "$DRY_RUN" != "true" ]; then
            wait_for_mig_stable
        fi
        
        # 如果不是最后一批，等待指定时间
        if [ $((i + BATCH_SIZE)) -lt $total ]; then
            log_info "等待 ${WAIT_TIME}s 后处理下一批次..."
            
            if [ "$DRY_RUN" != "true" ]; then
                local remaining=$WAIT_TIME
                while [ $remaining -gt 0 ]; do
                    echo -ne "\r剩余等待时间: ${remaining}s "
                    sleep 10
                    remaining=$((remaining - 10))
                done
                echo ""
            fi
        fi
    done
    
    # 输出总结
    log_info ""
    log_info "========================================="
    log_info "滚动重建完成"
    log_info "========================================="
    log_success "成功重建: $((total - ${#failed[@]})) 个实例"
    
    if [ ${#failed[@]} -gt 0 ]; then
        log_error "失败实例: ${#failed[@]} 个"
        log_error "失败列表: ${failed[*]}"
        return 1
    fi
    
    return 0
}

# ============================================
# 主程序
# ============================================

main() {
    local INSTANCE_LIST=""
    local RECREATE_ALL=false
    local DISK_THRESHOLD=""
    DRY_RUN=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -m|--mig)
                MIG_NAME="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -b|--batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            -w|--wait-time)
                WAIT_TIME="$2"
                shift 2
                ;;
            -i|--instances)
                INSTANCE_LIST="$2"
                shift 2
                ;;
            -a|--all)
                RECREATE_ALL=true
                shift
                ;;
            -d|--disk-threshold)
                DISK_THRESHOLD="$2"
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
    
    # 显示配置
    log_info "========================================="
    log_info "配置信息"
    log_info "========================================="
    log_info "项目 ID: $PROJECT_ID"
    log_info "MIG 名称: $MIG_NAME"
    log_info "Zone: $ZONE"
    log_info "批次大小: $BATCH_SIZE"
    log_info "等待时间: ${WAIT_TIME}s"
    [ "$DRY_RUN" = "true" ] && log_warning "模式: DRY RUN (模拟运行)"
    log_info "========================================="
    
    # 检查前置条件
    check_prerequisites
    
    # 确定要重建的实例列表
    local instances_array=()
    
    if [ -n "$INSTANCE_LIST" ]; then
        # 使用指定的实例列表
        IFS=',' read -ra instances_array <<< "$INSTANCE_LIST"
        log_info "使用指定的实例列表: ${instances_array[*]}"
        
    elif [ -n "$DISK_THRESHOLD" ]; then
        # 查询磁盘使用率超过阈值的实例
        mapfile -t instances_array < <(get_high_disk_instances "$DISK_THRESHOLD")
        log_info "找到 ${#instances_array[@]} 个磁盘使用率超过 ${DISK_THRESHOLD}% 的实例"
        
    elif [ "$RECREATE_ALL" = true ]; then
        # 获取所有实例
        mapfile -t instances_array < <(get_all_instances)
        log_info "将重建所有 ${#instances_array[@]} 个实例"
        
    else
        log_error "必须指定以下选项之一: -i, -a, -d"
        show_usage
    fi
    
    # 检查实例列表
    if [ ${#instances_array[@]} -eq 0 ]; then
        log_error "没有找到需要重建的实例"
        exit 1
    fi
    
    # 显示实例列表
    log_info ""
    log_info "待重建实例列表:"
    for instance in "${instances_array[@]}"; do
        log_info "  - $instance"
    done
    
    # 确认操作
    if [ "$DRY_RUN" != "true" ]; then
        log_warning ""
        log_warning "⚠️  警告: 此操作将重建 ${#instances_array[@]} 个实例"
        log_warning "⚠️  每个实例将被删除并重新创建"
        log_warning ""
        read -p "确认继续? (输入 'yes' 确认): " CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 执行滚动重建
    if rolling_recreate "${instances_array[@]}"; then
        log_success ""
        log_success "========================================="
        log_success "所有实例重建完成！"
        log_success "========================================="
        exit 0
    else
        log_error ""
        log_error "========================================="
        log_error "部分实例重建失败，请检查日志"
        log_error "========================================="
        exit 1
    fi
}

# 执行主程序
main "$@"

```

