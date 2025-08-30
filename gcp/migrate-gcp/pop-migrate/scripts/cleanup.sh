#!/bin/bash

# 清理脚本 - 清理导出文件、备份和临时文件

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXPORTS_DIR="${PROJECT_DIR}/exports"
BACKUPS_DIR="${PROJECT_DIR}/backups"
LOGS_DIR="${PROJECT_DIR}/logs"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认参数
DAYS_OLD=7
DRY_RUN=false
FORCE=false
CLEAN_EXPORTS=false
CLEAN_BACKUPS=false
CLEAN_LOGS=false
CLEAN_ALL=false

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")
            echo -e "${GREEN}[CLEANUP-INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[CLEANUP-WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[CLEANUP-ERROR]${NC} $message"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
清理脚本 - 清理迁移工具产生的文件

用法: $0 [选项]

选项:
    --days DAYS             清理指定天数之前的文件 (默认: 7)
    --exports              清理导出文件
    --backups              清理备份文件
    --logs                 清理日志文件
    --all                  清理所有文件
    --dry-run              干运行模式，不实际删除文件
    --force                强制删除，不询问确认
    -h, --help             显示此帮助信息

示例:
    $0 --exports --days 30          # 清理30天前的导出文件
    $0 --all --dry-run              # 干运行模式清理所有文件
    $0 --logs --force               # 强制清理日志文件

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --days)
                DAYS_OLD="$2"
                shift 2
                ;;
            --exports)
                CLEAN_EXPORTS=true
                shift
                ;;
            --backups)
                CLEAN_BACKUPS=true
                shift
                ;;
            --logs)
                CLEAN_LOGS=true
                shift
                ;;
            --all)
                CLEAN_ALL=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 如果没有指定清理类型，默认清理所有
    if [[ "$CLEAN_EXPORTS" == "false" && "$CLEAN_BACKUPS" == "false" && "$CLEAN_LOGS" == "false" && "$CLEAN_ALL" == "false" ]]; then
        CLEAN_ALL=true
    fi

    # 如果指定了 --all，设置所有清理选项
    if [[ "$CLEAN_ALL" == "true" ]]; then
        CLEAN_EXPORTS=true
        CLEAN_BACKUPS=true
        CLEAN_LOGS=true
    fi
}

# 确认删除操作
confirm_deletion() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo -e "${YELLOW}警告: 此操作将删除以下类型的文件:${NC}"
    
    if [[ "$CLEAN_EXPORTS" == "true" ]]; then
        echo "  - 导出文件 (超过 $DAYS_OLD 天)"
    fi
    
    if [[ "$CLEAN_BACKUPS" == "true" ]]; then
        echo "  - 备份文件 (超过 $DAYS_OLD 天)"
    fi
    
    if [[ "$CLEAN_LOGS" == "true" ]]; then
        echo "  - 日志文件 (超过 $DAYS_OLD 天)"
    fi
    
    echo ""
    read -p "确定要继续吗? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "操作已取消"
        exit 0
    fi
}

# 清理导出文件
cleanup_exports() {
    if [[ "$CLEAN_EXPORTS" != "true" ]]; then
        return 0
    fi

    log "INFO" "清理导出文件 (超过 $DAYS_OLD 天)..."

    if [[ ! -d "$EXPORTS_DIR" ]]; then
        log "WARN" "导出目录不存在: $EXPORTS_DIR"
        return 0
    fi

    local files_found=0
    local files_deleted=0

    # 查找超过指定天数的导出目录
    while IFS= read -r -d '' dir; do
        ((files_found++))
        
        local dir_name=$(basename "$dir")
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] 将删除: $dir_name ($size)"
        else
            log "INFO" "删除: $dir_name ($size)"
            rm -rf "$dir"
            ((files_deleted++))
        fi
    done < <(find "$EXPORTS_DIR" -maxdepth 1 -type d -mtime +$DAYS_OLD -not -path "$EXPORTS_DIR" -print0 2>/dev/null)

    # 清理符号链接
    while IFS= read -r -d '' link; do
        if [[ ! -e "$link" ]]; then  # 检查链接是否指向不存在的文件
            ((files_found++))
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY-RUN] 将删除无效链接: $(basename "$link")"
            else
                log "INFO" "删除无效链接: $(basename "$link")"
                rm -f "$link"
                ((files_deleted++))
            fi
        fi
    done < <(find "$EXPORTS_DIR" -maxdepth 1 -type l -print0 2>/dev/null)

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "导出文件清理 (干运行): 找到 $files_found 个项目"
    else
        log "INFO" "导出文件清理完成: 删除了 $files_deleted/$files_found 个项目"
    fi
}

# 清理备份文件
cleanup_backups() {
    if [[ "$CLEAN_BACKUPS" != "true" ]]; then
        return 0
    fi

    log "INFO" "清理备份文件 (超过 $DAYS_OLD 天)..."

    if [[ ! -d "$BACKUPS_DIR" ]]; then
        log "WARN" "备份目录不存在: $BACKUPS_DIR"
        return 0
    fi

    local files_found=0
    local files_deleted=0

    # 查找超过指定天数的备份文件
    while IFS= read -r -d '' file; do
        ((files_found++))
        
        local file_name=$(basename "$file")
        local size=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "未知")
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] 将删除: $file_name ($size)"
        else
            log "INFO" "删除: $file_name ($size)"
            rm -rf "$file"
            ((files_deleted++))
        fi
    done < <(find "$BACKUPS_DIR" -type f -mtime +$DAYS_OLD -print0 2>/dev/null)

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "备份文件清理 (干运行): 找到 $files_found 个文件"
    else
        log "INFO" "备份文件清理完成: 删除了 $files_deleted/$files_found 个文件"
    fi
}

# 清理日志文件
cleanup_logs() {
    if [[ "$CLEAN_LOGS" != "true" ]]; then
        return 0
    fi

    log "INFO" "清理日志文件 (超过 $DAYS_OLD 天)..."

    if [[ ! -d "$LOGS_DIR" ]]; then
        log "WARN" "日志目录不存在: $LOGS_DIR"
        return 0
    fi

    local files_found=0
    local files_deleted=0

    # 查找超过指定天数的日志文件
    while IFS= read -r -d '' file; do
        ((files_found++))
        
        local file_name=$(basename "$file")
        local size=$(du -sh "$file" 2>/dev/null | cut -f1 || echo "未知")
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] 将删除: $file_name ($size)"
        else
            log "INFO" "删除: $file_name ($size)"
            rm -f "$file"
            ((files_deleted++))
        fi
    done < <(find "$LOGS_DIR" -type f -name "*.log" -mtime +$DAYS_OLD -print0 2>/dev/null)

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "日志文件清理 (干运行): 找到 $files_found 个文件"
    else
        log "INFO" "日志文件清理完成: 删除了 $files_deleted/$files_found 个文件"
    fi
}

# 显示磁盘使用情况
show_disk_usage() {
    log "INFO" "当前磁盘使用情况:"
    
    if [[ -d "$EXPORTS_DIR" ]]; then
        local exports_size=$(du -sh "$EXPORTS_DIR" 2>/dev/null | cut -f1 || echo "0")
        log "INFO" "  导出目录: $exports_size ($EXPORTS_DIR)"
    fi
    
    if [[ -d "$BACKUPS_DIR" ]]; then
        local backups_size=$(du -sh "$BACKUPS_DIR" 2>/dev/null | cut -f1 || echo "0")
        log "INFO" "  备份目录: $backups_size ($BACKUPS_DIR)"
    fi
    
    if [[ -d "$LOGS_DIR" ]]; then
        local logs_size=$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1 || echo "0")
        log "INFO" "  日志目录: $logs_size ($LOGS_DIR)"
    fi
}

# 清理空目录
cleanup_empty_directories() {
    log "INFO" "清理空目录..."
    
    local dirs_to_check=("$EXPORTS_DIR" "$BACKUPS_DIR" "$LOGS_DIR")
    
    for dir in "${dirs_to_check[@]}"; do
        if [[ -d "$dir" ]]; then
            # 查找并删除空目录
            find "$dir" -type d -empty -delete 2>/dev/null || true
        fi
    done
}

# 生成清理报告
generate_cleanup_report() {
    local report_file="${LOGS_DIR}/cleanup-report-$(date +%Y%m%d_%H%M%S).md"
    
    mkdir -p "$LOGS_DIR"
    
    cat > "$report_file" << EOF
# 清理报告

**清理时间:** $(date)  
**清理天数:** $DAYS_OLD 天  
**干运行模式:** $DRY_RUN

## 清理范围

- 导出文件: $CLEAN_EXPORTS
- 备份文件: $CLEAN_BACKUPS
- 日志文件: $CLEAN_LOGS

## 清理前磁盘使用情况

EOF

    if [[ -d "$EXPORTS_DIR" ]]; then
        echo "- 导出目录: $(du -sh "$EXPORTS_DIR" 2>/dev/null | cut -f1 || echo "0")" >> "$report_file"
    fi
    
    if [[ -d "$BACKUPS_DIR" ]]; then
        echo "- 备份目录: $(du -sh "$BACKUPS_DIR" 2>/dev/null | cut -f1 || echo "0")" >> "$report_file"
    fi
    
    if [[ -d "$LOGS_DIR" ]]; then
        echo "- 日志目录: $(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1 || echo "0")" >> "$report_file"
    fi

    cat >> "$report_file" << EOF

## 建议

- 定期运行清理脚本以释放磁盘空间
- 根据需要调整保留天数
- 重要的导出文件建议手动备份到其他位置

EOF

    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "清理报告已生成: $report_file"
    fi
}

# 主函数
main() {
    log "INFO" "开始清理操作"
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "运行模式: 干运行 (不会实际删除文件)"
    fi
    
    # 显示当前磁盘使用情况
    show_disk_usage
    
    # 确认删除操作
    confirm_deletion
    
    # 执行清理操作
    cleanup_exports
    cleanup_backups
    cleanup_logs
    
    # 清理空目录
    if [[ "$DRY_RUN" != "true" ]]; then
        cleanup_empty_directories
    fi
    
    # 生成清理报告
    generate_cleanup_report
    
    # 显示清理后的磁盘使用情况
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log "INFO" "清理后磁盘使用情况:"
        show_disk_usage
    fi
    
    log "INFO" "清理操作完成"
}

# 执行主函数
main "$@"