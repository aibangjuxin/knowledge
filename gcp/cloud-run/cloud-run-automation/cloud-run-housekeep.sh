#!/bin/bash

# =============================================================================
# Cloud Run Job Housekeeping Script (Enhanced Version)
# =============================================================================
#
# 功能:
# - 删除失败的执行
# - 删除过期的执行
# - 支持批量处理多个作业
# - 支持干运行模式
# - 详细的日志记录
# - 错误处理和重试机制
# - 统计报告
#
# 作者: Kiro AI Assistant
# 版本: 2.0
# 更新时间: $(date +"%Y-%m-%d")
#
# =============================================================================

set -euo pipefail

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 全局变量 ---
SCRIPT_NAME=$(basename "$0")
LOG_FILE="/tmp/cloud-run-housekeep-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false
BATCH_MODE=false
CONFIG_FILE=""
PROJECT_ID=""
DELETED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0
PROCESSED_COUNT=0
DELETE_FAILED=false
OLDER_THAN_DAYS=""
RETRY_COUNT=3

# --- 日志函数 ---
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [ "$VERBOSE" = true ]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
        "SUCCESS")
            echo -e "${CYAN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# --- 帮助信息 ---
show_help() {
    cat << EOF
${GREEN}$SCRIPT_NAME - Cloud Run Job Housekeeping Script${NC}

${YELLOW}用法:${NC}
    $SCRIPT_NAME [选项] <JOB_NAME> <REGION>
    $SCRIPT_NAME [选项] --batch --config <CONFIG_FILE>

${YELLOW}选项:${NC}
    ${BLUE}-h, --help${NC}              显示此帮助信息
    ${BLUE}-d, --dry-run${NC}           干运行模式，不实际删除
    ${BLUE}-v, --verbose${NC}           详细输出
    ${BLUE}-f, --delete-failed${NC}     删除失败的执行
    ${BLUE}-o, --older-than DAYS${NC}   删除指定天数前的执行
    ${BLUE}-b, --batch${NC}             批量模式
    ${BLUE}-c, --config FILE${NC}       配置文件路径
    ${BLUE}-p, --project PROJECT${NC}   指定项目ID (可选)
    ${BLUE}-l, --log-file FILE${NC}     指定日志文件路径
    ${BLUE}-r, --retry COUNT${NC}       重试次数 (默认: 3)
    ${BLUE}--force${NC}                 强制删除，跳过确认

${YELLOW}示例:${NC}
    # 删除失败的执行
    $SCRIPT_NAME -f my-job europe-west2

    # 删除30天前的执行 (干运行)
    $SCRIPT_NAME -d -o 30 my-job europe-west2

    # 批量处理
    $SCRIPT_NAME -b -c jobs.conf

    # 完整清理 (指定项目)
    $SCRIPT_NAME -f -o 7 -v -p my-project my-job europe-west2

${YELLOW}配置文件格式 (jobs.conf):${NC}
    ${PURPLE}# 格式: JOB_NAME,REGION,DELETE_FAILED,OLDER_THAN_DAYS,PROJECT_ID${NC}
    my-job-1,europe-west2,true,30,project-1
    my-job-2,us-central1,false,7,project-2
    my-job-3,asia-northeast1,true,14,

${YELLOW}注意事项:${NC}
    - 如果未指定项目ID，将使用当前gcloud配置的项目
    - 配置文件中的PROJECT_ID列可以为空，表示使用默认项目
    - 建议先使用 --dry-run 选项预览要删除的内容

EOF
}

# --- 参数解析 ---
parse_arguments() {
    local force_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--delete-failed)
                DELETE_FAILED=true
                shift
                ;;
            -o|--older-than)
                OLDER_THAN_DAYS="$2"
                if ! [[ "$OLDER_THAN_DAYS" =~ ^[0-9]+$ ]]; then
                    log "ERROR" "天数必须是正整数: $OLDER_THAN_DAYS"
                    exit 1
                fi
                shift 2
                ;;
            -b|--batch)
                BATCH_MODE=true
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -r|--retry)
                RETRY_COUNT="$2"
                if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
                    log "ERROR" "重试次数必须是正整数: $RETRY_COUNT"
                    exit 1
                fi
                shift 2
                ;;
            --force)
                force_mode=true
                shift
                ;;
            -*)
                log "ERROR" "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [ "$BATCH_MODE" = false ]; then
                    if [ -z "${JOB_NAME:-}" ]; then
                        JOB_NAME="$1"
                    elif [ -z "${REGION:-}" ]; then
                        REGION="$1"
                    else
                        log "ERROR" "过多的参数: $1"
                        exit 1
                    fi
                fi
                shift
                ;;
        esac
    done

    export FORCE_MODE="$force_mode"
}

# --- 验证依赖 ---
check_dependencies() {
    local deps=("gcloud" "jq" "date")

    log "DEBUG" "检查依赖工具..."
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "依赖 '$dep' 未找到，请先安装"
            case $dep in
                "jq")
                    log "INFO" "安装方法:"
                    log "INFO" "  macOS: brew install jq"
                    log "INFO" "  Ubuntu/Debian: sudo apt-get install jq"
                    log "INFO" "  CentOS/RHEL: sudo yum install jq"
                    ;;
                "gcloud")
                    log "INFO" "请安装 Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
                    ;;
            esac
            exit 1
        fi
    done

    # 检查 gcloud 认证
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
    if [ -z "$active_account" ]; then
        log "ERROR" "gcloud 未认证，请先运行 'gcloud auth login'"
        exit 1
    fi

    log "DEBUG" "当前认证账号: $active_account"

    # 获取默认项目（如果未指定）
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            log "WARN" "未设置默认项目，某些操作可能需要明确指定项目ID"
        else
            log "DEBUG" "使用默认项目: $PROJECT_ID"
        fi
    fi

    log "SUCCESS" "所有依赖检查通过"
}

# --- 重试机制 ---
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "尝试执行命令 (第 $attempt 次): ${command[*]}"

        if "${command[@]}" 2>/dev/null; then
            return 0
        else
            local exit_code=$?
            log "WARN" "命令执行失败 (第 $attempt 次)，退出码: $exit_code"

            if [ $attempt -lt $max_attempts ]; then
                log "INFO" "等待 $delay 秒后重试..."
                sleep "$delay"
            fi

            ((attempt++))
        fi
    done

    log "ERROR" "命令在 $max_attempts 次尝试后仍然失败"
    return 1
}

# --- 获取执行列表 ---
get_executions() {
    local job_name="$1"
    local region="$2"
    local project_id="$3"

    log "DEBUG" "获取作业 '$job_name' 在区域 '$region' 的执行列表"

    local gcloud_cmd=("gcloud" "run" "jobs" "executions" "list" 
                      "--job=$job_name" 
                      "--region=$region" 
                      "--format=json")
    
    if [ -n "$project_id" ]; then
        gcloud_cmd+=("--project=$project_id")
    fi

    local executions_json
    if ! executions_json=$(retry_command "$RETRY_COUNT" 2 "${gcloud_cmd[@]}"); then
        log "ERROR" "无法获取作业 '$job_name' 的执行列表"
        return 1
    fi

    if [ "$executions_json" = "[]" ] || [ -z "$executions_json" ]; then
        log "INFO" "作业 '$job_name' 没有找到任何执行"
        echo "[]"
        return 0
    fi

    # 验证JSON格式
    if ! echo "$executions_json" | jq empty 2>/dev/null; then
        log "ERROR" "返回的执行列表不是有效的JSON格式"
        return 1
    fi

    echo "$executions_json"
}

# --- 删除失败的执行 ---
delete_failed_executions() {
    local job_name="$1"
    local region="$2"
    local project_id="$3"
    local executions_json="$4"

    log "INFO" "查找作业 '$job_name' 的失败执行..."

    # 使用更精确的jq查询来识别失败的执行
    local failed_executions
    failed_executions=$(echo "$executions_json" | jq -r '
        .[] |
        select(
            (.status.conditions[]? | select(.type == "Completed" and .status == "False")) or
            (.status.failedCount? and (.status.failedCount | tonumber) > 0) or
            (.status.phase? and .status.phase == "Failed")
        ) |
        .metadata.name
    ' 2>/dev/null || echo "")

    if [ -z "$failed_executions" ]; then
        log "INFO" "没有找到失败的执行"
        return 0
    fi

    local count=0
    local failed_list=()
    while IFS= read -r execution_name; do
        [ -z "$execution_name" ] && continue
        failed_list+=("$execution_name")
        ((count++))
    done <<< "$failed_executions"

    if [ $count -eq 0 ]; then
        log "INFO" "没有找到失败的执行"
        return 0
    fi

    log "INFO" "找到 $count 个失败的执行"

    # 如果不是强制模式且不是干运行，询问确认
    if [ "$FORCE_MODE" = false ] && [ "$DRY_RUN" = false ]; then
        echo -e "${YELLOW}将要删除以下失败的执行:${NC}"
        printf '%s\n' "${failed_list[@]}"
        echo ""
        read -p "确认删除这些执行吗? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "用户取消删除操作"
            ((SKIPPED_COUNT += count))
            return 0
        fi
    fi

    # 删除失败的执行
    for execution_name in "${failed_list[@]}"; do
        log "INFO" "处理失败的执行: $execution_name"

        if [ "$DRY_RUN" = true ]; then
            log "INFO" "[DRY RUN] 将删除失败的执行: $execution_name"
            ((SKIPPED_COUNT++))
        else
            local delete_cmd=("gcloud" "run" "jobs" "executions" "delete" 
                              "$execution_name" "--region=$region" "--quiet")
            
            if [ -n "$project_id" ]; then
                delete_cmd+=("--project=$project_id")
            fi

            if retry_command "$RETRY_COUNT" 2 "${delete_cmd[@]}"; then
                log "SUCCESS" "成功删除失败的执行: $execution_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "删除失败的执行失败: $execution_name"
                ((FAILED_COUNT++))
            fi
        fi
    done

    log "INFO" "处理了 $count 个失败的执行"
}

# --- 删除过期的执行 ---
delete_older_executions() {
    local job_name="$1"
    local region="$2"
    local project_id="$3"
    local executions_json="$4"
    local days="$5"

    log "INFO" "查找作业 '$job_name' 中 $days 天前的执行..."

    # 计算截止日期
    local cutoff_date
    if command -v gdate &> /dev/null; then
        # macOS with GNU date
        cutoff_date=$(gdate -d "$days days ago" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    else
        # Linux date or macOS BSD date
        cutoff_date=$(date -d "$days days ago" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                     date -v-"$days"d -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    fi

    if [ -z "$cutoff_date" ]; then
        log "ERROR" "无法计算截止日期，请检查date命令"
        return 1
    fi

    log "DEBUG" "截止日期: $cutoff_date"

    # 查找过期的执行
    local older_executions
    older_executions=$(echo "$executions_json" | jq -r --arg CUTOFF_DATE "$cutoff_date" '
        .[] |
        select(
            .status.completionTime and
            .status.completionTime < $CUTOFF_DATE and
            (.status.conditions[]? | select(.type == "Completed" and .status == "True"))
        ) |
        .metadata.name
    ' 2>/dev/null || echo "")

    if [ -z "$older_executions" ]; then
        log "INFO" "没有找到 $days 天前的执行"
        return 0
    fi

    local count=0
    local older_list=()
    while IFS= read -r execution_name; do
        [ -z "$execution_name" ] && continue
        older_list+=("$execution_name")
        ((count++))
    done <<< "$older_executions"

    if [ $count -eq 0 ]; then
        log "INFO" "没有找到 $days 天前的执行"
        return 0
    fi

    log "INFO" "找到 $count 个超过 $days 天的执行"

    # 如果不是强制模式且不是干运行，询问确认
    if [ "$FORCE_MODE" = false ] && [ "$DRY_RUN" = false ]; then
        echo -e "${YELLOW}将要删除以下超过 $days 天的执行:${NC}"
        printf '%s\n' "${older_list[@]}"
        echo ""
        read -p "确认删除这些执行吗? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "用户取消删除操作"
            ((SKIPPED_COUNT += count))
            return 0
        fi
    fi

    # 删除过期的执行
    for execution_name in "${older_list[@]}"; do
        log "INFO" "处理过期的执行: $execution_name"

        if [ "$DRY_RUN" = true ]; then
            log "INFO" "[DRY RUN] 将删除过期的执行: $execution_name"
            ((SKIPPED_COUNT++))
        else
            local delete_cmd=("gcloud" "run" "jobs" "executions" "delete" 
                              "$execution_name" "--region=$region" "--quiet")
            
            if [ -n "$project_id" ]; then
                delete_cmd+=("--project=$project_id")
            fi

            if retry_command "$RETRY_COUNT" 2 "${delete_cmd[@]}"; then
                log "SUCCESS" "成功删除过期的执行: $execution_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "删除过期的执行失败: $execution_name"
                ((FAILED_COUNT++))
            fi
        fi
    done

    log "INFO" "处理了 $count 个过期的执行"
}

# --- 处理单个作业 ---
process_job() {
    local job_name="$1"
    local region="$2"
    local delete_failed="$3"
    local older_than_days="$4"
    local project_id="$5"

    log "INFO" "开始处理作业: $job_name (区域: $region)"
    if [ -n "$project_id" ]; then
        log "INFO" "项目: $project_id"
    fi

    ((PROCESSED_COUNT++))

    # 验证作业是否存在
    local describe_cmd=("gcloud" "run" "jobs" "describe" "$job_name" "--region=$region")
    if [ -n "$project_id" ]; then
        describe_cmd+=("--project=$project_id")
    fi

    if ! "${describe_cmd[@]}" &>/dev/null; then
        log "ERROR" "作业 '$job_name' 在区域 '$region' 中不存在"
        if [ -n "$project_id" ]; then
            log "ERROR" "项目: $project_id"
        fi
        ((FAILED_COUNT++))
        return 1
    fi

    # 获取执行列表
    local executions_json
    if ! executions_json=$(get_executions "$job_name" "$region" "$project_id"); then
        log "ERROR" "无法获取作业 '$job_name' 的执行列表"
        ((FAILED_COUNT++))
        return 1
    fi

    # 检查是否有执行记录
    if [ "$executions_json" = "[]" ]; then
        log "INFO" "作业 '$job_name' 没有执行记录，跳过处理"
        ((SKIPPED_COUNT++))
        return 0
    fi

    # 显示执行统计
    local total_executions
    total_executions=$(echo "$executions_json" | jq length 2>/dev/null || echo "0")
    log "INFO" "作业 '$job_name' 共有 $total_executions 个执行记录"

    # 删除失败的执行
    if [ "$delete_failed" = true ]; then
        delete_failed_executions "$job_name" "$region" "$project_id" "$executions_json"
    fi

    # 删除过期的执行
    if [ -n "$older_than_days" ]; then
        delete_older_executions "$job_name" "$region" "$project_id" "$executions_json" "$older_than_days"
    fi

    log "SUCCESS" "完成处理作业: $job_name"
}

# --- 批量处理 ---
process_batch() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        log "ERROR" "配置文件不存在: $config_file"
        exit 1
    fi

    log "INFO" "开始批量处理，配置文件: $config_file"

    local line_number=0
    local total_lines
    total_lines=$(grep -v '^[[:space:]]*#' "$config_file" | grep -v '^[[:space:]]*$' | wc -l)
    log "INFO" "配置文件包含 $total_lines 个有效配置"

    while IFS=',' read -r job_name region delete_failed older_than_days project_id || [ -n "$job_name" ]; do
        ((line_number++))

        # 跳过空行和注释
        if [[ -z "$job_name" || "$job_name" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # 清理空格
        job_name=$(echo "$job_name" | xargs)
        region=$(echo "$region" | xargs)
        delete_failed=$(echo "$delete_failed" | xargs)
        older_than_days=$(echo "$older_than_days" | xargs)
        project_id=$(echo "$project_id" | xargs)

        log "INFO" "处理配置行 $line_number/$total_lines: $job_name,$region,$delete_failed,$older_than_days,$project_id"

        # 验证参数
        if [ -z "$job_name" ] || [ -z "$region" ]; then
            log "ERROR" "配置文件第 $line_number 行格式错误: 缺少作业名称或区域"
            ((FAILED_COUNT++))
            continue
        fi

        # 验证布尔值
        if [ -n "$delete_failed" ] && [ "$delete_failed" != "true" ] && [ "$delete_failed" != "false" ]; then
            log "ERROR" "配置文件第 $line_number 行: delete_failed 必须是 true 或 false"
            ((FAILED_COUNT++))
            continue
        fi

        # 验证天数
        if [ -n "$older_than_days" ] && ! [[ "$older_than_days" =~ ^[0-9]+$ ]]; then
            log "ERROR" "配置文件第 $line_number 行: older_than_days 必须是正整数"
            ((FAILED_COUNT++))
            continue
        fi

        # 如果没有指定任何清理选项，跳过
        if [ "$delete_failed" != "true" ] && [ -z "$older_than_days" ]; then
            log "WARN" "配置文件第 $line_number 行: 没有指定任何清理选项，跳过"
            ((SKIPPED_COUNT++))
            continue
        fi

        # 使用配置文件中的项目ID，如果为空则使用全局项目ID
        local effective_project_id="$project_id"
        if [ -z "$effective_project_id" ]; then
            effective_project_id="$PROJECT_ID"
        fi

        # 处理作业
        process_job "$job_name" "$region" "$delete_failed" "$older_than_days" "$effective_project_id"

        # 添加进度显示
        if [ "$VERBOSE" = true ]; then
            log "INFO" "进度: $line_number/$total_lines 完成"
        fi

    done < "$config_file"
}

# --- 生成报告 ---
generate_report() {
    echo ""
    log "INFO" "==================== 清理报告 ===================="
    log "INFO" "执行时间: $(date)"
    log "INFO" "日志文件: $LOG_FILE"
    log "INFO" "运行模式: $([ "$DRY_RUN" = true ] && echo "干运行" || echo "实际执行")"
    log "INFO" ""
    log "INFO" "统计信息:"
    log "INFO" "  - 处理的作业数: $PROCESSED_COUNT"
    log "INFO" "  - 成功删除: $DELETED_COUNT"
    log "INFO" "  - 跳过处理: $SKIPPED_COUNT"
    log "INFO" "  - 处理失败: $FAILED_COUNT"
    
    if [ $DELETED_COUNT -gt 0 ]; then
        log "SUCCESS" "  - 总计释放的执行记录: $DELETED_COUNT"
    fi
    
    log "INFO" "=================================================="

    # 提供建议
    if [ "$DRY_RUN" = true ] && [ $SKIPPED_COUNT -gt 0 ]; then
        log "INFO" "提示: 这是干运行模式，实际删除请移除 --dry-run 选项"
    fi

    if [ $FAILED_COUNT -gt 0 ]; then
        log "WARN" "存在处理失败的项目，请检查日志文件: $LOG_FILE"
    fi
}

# --- 清理函数 ---
cleanup() {
    generate_report

    if [ "$VERBOSE" = true ]; then
        log "INFO" "详细日志已保存到: $LOG_FILE"
    fi

    # 根据实际的失败情况决定退出码
    if [ $FAILED_COUNT -gt 0 ]; then
        log "ERROR" "脚本执行过程中存在失败项目，退出码: 1"
        exit 1
    else
        log "SUCCESS" "脚本执行完成"
        exit 0
    fi
}

# --- 主函数 ---
main() {
    # 设置信号处理
    trap cleanup EXIT INT TERM

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Cloud Run Job Housekeeping Script${NC}"
    echo -e "${GREEN}版本: 2.0${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    log "INFO" "开始 Cloud Run Job Housekeeping"
    log "INFO" "日志文件: $LOG_FILE"

    # 检查依赖
    check_dependencies

    # 解析参数
    parse_arguments "$@"

    # 验证参数
    if [ "$BATCH_MODE" = true ]; then
        if [ -z "$CONFIG_FILE" ]; then
            log "ERROR" "批量模式需要指定配置文件 (-c)"
            show_help
            exit 1
        fi
        process_batch "$CONFIG_FILE"
    else
        if [ -z "${JOB_NAME:-}" ] || [ -z "${REGION:-}" ]; then
            log "ERROR" "必须提供 JOB_NAME 和 REGION"
            show_help
            exit 1
        fi

        if [ "$DELETE_FAILED" = false ] && [ -z "$OLDER_THAN_DAYS" ]; then
            log "ERROR" "必须指定至少一个清理选项 (-f 或 -o)"
            show_help
            exit 1
        fi

        process_job "$JOB_NAME" "$REGION" "$DELETE_FAILED" "$OLDER_THAN_DAYS" "$PROJECT_ID"
    fi

    log "SUCCESS" "Housekeeping 完成"
}

# --- 脚本入口 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi