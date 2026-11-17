#!/bin/bash

# Secret Manager 迁移主控制脚本
# 功能：统一管理整个 Secret Manager 迁移流程

set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
source "$SCRIPT_DIR/config.sh"

# 显示帮助信息
show_help() {
    cat << EOF
Secret Manager 迁移工具 - GCP 跨项目密钥迁移自动化脚本

用法: $0 [选项] [阶段]

阶段:
  setup       环境准备和权限检查
  discover    发现和分析源项目中的密钥
  export      导出源项目中的所有密钥
  import      导入密钥到目标项目
  verify      验证迁移结果
  update      更新应用程序配置
  all         执行完整迁移流程 (setup -> discover -> export -> import -> verify)
  status      显示当前迁移状态

选项:
  -h, --help              显示此帮助信息
  -s, --source PROJECT    源项目ID (覆盖配置文件)
  -t, --target PROJECT    目标项目ID (覆盖配置文件)
  -d, --dry-run          干运行模式，只显示将要执行的操作
  -v, --verbose          详细输出模式
  -f, --force            强制执行，跳过确认提示
  --batch-size SIZE      批量处理大小 (默认: $BATCH_SIZE)
  --no-verify-values     跳过密钥值验证以加快速度

示例:
  $0 setup                                    # 环境准备
  $0 discover                                 # 发现密钥
  $0 export                                   # 导出密钥
  $0 import                                   # 导入密钥
  $0 verify                                   # 验证结果
  $0 update                                   # 更新应用配置
  $0 all                                      # 执行完整迁移流程
  $0 status                                   # 查看迁移状态
  
  $0 -s source-proj -t target-proj all       # 指定项目执行完整迁移
  $0 --dry-run import                         # 干运行导入
  $0 --force --no-verify-values verify       # 强制验证但跳过值检查
  $0 --batch-size 5 export                   # 使用较小批量大小导出

配置:
  在执行前，请确保已正确配置 config.sh 文件中的以下参数:
  - SOURCE_PROJECT: 源项目ID
  - TARGET_PROJECT: 目标项目ID
  - 其他相关配置参数

注意事项:
  1. 确保已安装并配置 gcloud、kubectl 工具
  2. 确保对源项目和目标项目有足够的权限
  3. 建议先在测试环境验证整个流程
  4. 迁移前请做好备份和回滚准备
EOF
}

# 显示当前配置
show_config() {
    echo "=== 当前配置 ==="
    echo "源项目: ${SOURCE_PROJECT:-未设置}"
    echo "目标项目: ${TARGET_PROJECT:-未设置}"
    echo "批量大小: ${BATCH_SIZE:-未设置}"
    echo "验证密钥值: ${VERIFY_SECRET_VALUES:-未设置}"
    echo "备份目录: ${BACKUP_DIR:-未设置}"
    echo "日志文件: ${LOG_FILE:-未设置}"
    echo ""
}

# 显示迁移状态
show_migration_status() {
    log_info "检查迁移状态..."
    
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        echo "❌ 未找到迁移状态文件"
        echo "请先运行: $0 setup"
        return 1
    fi
    
    echo "=== 迁移状态 ==="
    
    local migration_id
    migration_id=$(jq -r '.migration_id' "$BACKUP_DIR/migration_status.json")
    echo "迁移ID: $migration_id"
    
    local start_time
    start_time=$(jq -r '.start_time' "$BACKUP_DIR/migration_status.json")
    echo "开始时间: $start_time"
    
    echo ""
    echo "各阶段状态:"
    
    local stages=("setup" "discover" "export" "import" "verify" "update")
    for stage in "${stages[@]}"; do
        local status
        status=$(jq -r ".stages.$stage" "$BACKUP_DIR/migration_status.json")
        
        case "$status" in
            "completed")
                echo "  ✅ $stage: 已完成"
                ;;
            "failed")
                echo "  ❌ $stage: 失败"
                ;;
            "pending")
                echo "  ⏳ $stage: 待执行"
                ;;
            *)
                echo "  ❓ $stage: 未知状态"
                ;;
        esac
    done
    
    echo ""
    
    # 显示统计信息
    if [[ -f "$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json" ]]; then
        local total_secrets
        total_secrets=$(jq length "$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json")
        echo "发现的密钥数量: $total_secrets"
    fi
    
    if [[ -f "$BACKUP_DIR/export_log.json" ]]; then
        local exported_count
        exported_count=$(jq '[.[] | select(.status == "success")] | length' "$BACKUP_DIR/export_log.json")
        echo "已导出密钥数量: $exported_count"
    fi
    
    if [[ -f "$BACKUP_DIR/import_log.json" ]]; then
        local imported_count
        imported_count=$(jq '[.[] | select(.status == "success")] | length' "$BACKUP_DIR/import_log.json")
        echo "已导入密钥数量: $imported_count"
    fi
    
    if [[ -f "$BACKUP_DIR/verification_log.json" ]]; then
        local verified_count
        verified_count=$(jq '[.[] | select(.status == "success")] | length' "$BACKUP_DIR/verification_log.json")
        echo "验证通过密钥数量: $verified_count"
    fi
    
    echo ""
    echo "备份目录: $BACKUP_DIR"
    
    # 建议下一步操作
    local next_stage=""
    for stage in "${stages[@]}"; do
        local status
        status=$(jq -r ".stages.$stage" "$BACKUP_DIR/migration_status.json")
        if [[ "$status" == "pending" ]]; then
            next_stage="$stage"
            break
        fi
    done
    
    if [[ -n "$next_stage" ]]; then
        echo "建议下一步: $0 $next_stage"
    else
        echo "✅ 所有阶段已完成！"
    fi
}

# 检查阶段依赖
check_stage_dependencies() {
    local stage=$1
    
    if [[ ! -f "$BACKUP_DIR/migration_status.json" && "$stage" != "setup" ]]; then
        log_error "未找到迁移状态文件，请先运行: $0 setup"
        return 1
    fi
    
    case "$stage" in
        "discover")
            local setup_status
            setup_status=$(jq -r '.stages.setup' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$setup_status" != "completed" ]]; then
                log_error "环境准备未完成，请先运行: $0 setup"
                return 1
            fi
            ;;
        "export")
            local discover_status
            discover_status=$(jq -r '.stages.discover' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$discover_status" != "completed" ]]; then
                log_error "密钥发现未完成，请先运行: $0 discover"
                return 1
            fi
            ;;
        "import")
            local export_status
            export_status=$(jq -r '.stages.export' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$export_status" != "completed" ]]; then
                log_error "密钥导出未完成，请先运行: $0 export"
                return 1
            fi
            ;;
        "verify")
            local import_status
            import_status=$(jq -r '.stages.import' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$import_status" != "completed" ]]; then
                log_error "密钥导入未完成，请先运行: $0 import"
                return 1
            fi
            ;;
        "update")
            local verify_status
            verify_status=$(jq -r '.stages.verify' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$verify_status" != "completed" ]]; then
                log_warning "密钥验证未完成，建议先运行: $0 verify"
                if [[ "$FORCE_MODE" != "true" ]]; then
                    read -p "是否继续？(y/n): " -r
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        return 1
                    fi
                fi
            fi
            ;;
    esac
    
    return 0
}

# 执行单个阶段
execute_stage() {
    local stage=$1
    local script_file=""
    
    case "$stage" in
        "setup")
            script_file="$SCRIPT_DIR/01-setup.sh"
            ;;
        "discover")
            script_file="$SCRIPT_DIR/02-discover.sh"
            ;;
        "export")
            script_file="$SCRIPT_DIR/03-export.sh"
            ;;
        "import")
            script_file="$SCRIPT_DIR/04-import.sh"
            ;;
        "verify")
            script_file="$SCRIPT_DIR/05-verify.sh"
            ;;
        "update")
            script_file="$SCRIPT_DIR/06-update-apps.sh"
            ;;
        *)
            log_error "未知阶段: $stage"
            return 1
            ;;
    esac
    
    if [[ ! -f "$script_file" ]]; then
        log_error "脚本文件不存在: $script_file"
        return 1
    fi
    
    log_info "执行阶段: $stage"
    log_info "脚本文件: $script_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] 将要执行: $script_file"
        return 0
    fi
    
    # 检查阶段依赖
    if [[ "$FORCE_MODE" != "true" ]]; then
        if ! check_stage_dependencies "$stage"; then
            return 1
        fi
    fi
    
    # 执行脚本
    if bash "$script_file"; then
        log_success "阶段 $stage 执行成功"
        return 0
    else
        log_error "阶段 $stage 执行失败"
        return 1
    fi
}

# 执行完整迁移流程
execute_full_migration() {
    log_info "开始执行完整 Secret Manager 迁移流程..."
    
    local stages=("setup" "discover" "export" "import" "verify")
    
    for stage in "${stages[@]}"; do
        log_info "=== 执行阶段: $stage ==="
        
        if ! execute_stage "$stage"; then
            log_error "阶段 $stage 失败，停止执行"
            echo ""
            echo "故障排除建议："
            echo "1. 检查错误日志: $LOG_FILE"
            echo "2. 查看迁移状态: $0 status"
            echo "3. 修复问题后重新运行失败的阶段: $0 $stage"
            echo "4. 或从失败点继续: $0 ${stages[*]:$((${#stages[@]}-1))}"
            return 1
        fi
        
        # 在阶段之间添加暂停，让用户有机会检查结果
        if [[ "$FORCE_MODE" != "true" && "$stage" != "verify" ]]; then
            echo ""
            read -p "阶段 $stage 完成，按回车键继续下一阶段..." -r
        fi
    done
    
    log_success "完整 Secret Manager 迁移流程执行成功！"
    echo ""
    echo "🎉 迁移完成！"
    echo ""
    echo "后续步骤："
    echo "1. 查看验证报告: cat $BACKUP_DIR/verification_report.txt"
    echo "2. 更新应用配置: $0 update"
    echo "3. 测试应用程序功能"
    echo "4. 监控生产环境稳定性"
}

# 解析命令行参数
DRY_RUN=false
VERBOSE=false
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--source)
            export SOURCE_PROJECT="$2"
            shift 2
            ;;
        -t|--target)
            export TARGET_PROJECT="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            export DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --batch-size)
            export BATCH_SIZE="$2"
            shift 2
            ;;
        --no-verify-values)
            export VERIFY_SECRET_VALUES=false
            shift
            ;;
        setup|discover|export|import|verify|update|all|status)
            STAGE="$1"
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 初始化
setup_directories

# 显示配置信息
if [[ "$VERBOSE" == "true" ]]; then
    show_config
fi

# 检查必要参数
if [[ -z "${STAGE:-}" ]]; then
    echo "错误: 请指定要执行的阶段"
    echo ""
    show_help
    exit 1
fi

# 验证配置（除了 status 命令）
if [[ "$STAGE" != "status" ]]; then
    if [[ -z "${SOURCE_PROJECT:-}" || -z "${TARGET_PROJECT:-}" ]]; then
        echo "错误: 请在 config.sh 中设置 SOURCE_PROJECT 和 TARGET_PROJECT"
        echo "或使用 -s 和 -t 参数指定"
        exit 1
    fi
    
    if ! validate_config; then
        exit 1
    fi
fi

# 主执行逻辑
case "$STAGE" in
    "all")
        execute_full_migration
        ;;
    "status")
        show_migration_status
        ;;
    *)
        execute_stage "$STAGE"
        ;;
esac