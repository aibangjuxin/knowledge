#!/bin/bash

# DNS 迁移主控制脚本
# 功能：统一管理整个DNS迁移流程

set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
source "$SCRIPT_DIR/config.sh"

# 函数：显示帮助信息
show_help() {
    cat << EOF
DNS 迁移工具 - GCP 跨项目DNS迁移自动化脚本

用法: $0 [选项] [阶段]

阶段:
  discovery     发现和分析源项目与目标项目的服务映射关系
  prepare       在目标项目中准备DNS记录和SSL证书
  migrate       执行DNS切换，将流量从源项目切换到目标项目
  rollback      回滚DNS记录到迁移前状态
  cleanup       清理源项目中不再使用的资源
  all           执行完整的迁移流程 (discovery -> prepare -> migrate)

选项:
  -h, --help              显示此帮助信息
  -c, --config FILE       指定配置文件 (默认: config.sh)
  -d, --dry-run          干运行模式，只显示将要执行的操作
  -v, --verbose          详细输出模式
  -f, --force            强制执行，跳过确认提示
  --source-project ID    源项目ID (覆盖配置文件)
  --target-project ID    目标项目ID (覆盖配置文件)

示例:
  $0 discovery                    # 发现服务映射关系
  $0 prepare                      # 准备目标项目
  $0 migrate                      # 执行迁移
  $0 all                          # 执行完整迁移流程
  $0 rollback                     # 回滚迁移
  $0 cleanup                      # 清理资源
  
  $0 --dry-run migrate           # 干运行迁移
  $0 --force cleanup             # 强制清理，跳过确认
  $0 --source-project proj1 --target-project proj2 all

配置:
  在执行前，请确保已正确配置 config.sh 文件中的以下参数:
  - SOURCE_PROJECT: 源项目ID
  - TARGET_PROJECT: 目标项目ID
  - PARENT_DOMAIN: 父域名
  - DOMAIN_MAPPINGS: 域名映射配置
  - 其他相关配置参数

注意事项:
  1. 确保已安装并配置 gcloud、kubectl 工具
  2. 确保对源项目和目标项目有足够的权限
  3. 建议先在测试环境验证整个流程
  4. 迁移前请做好备份和回滚准备
EOF
}

# 函数：显示当前配置
show_config() {
    echo "=== 当前配置 ==="
    echo "源项目: $SOURCE_PROJECT"
    echo "目标项目: $TARGET_PROJECT"
    echo "父域名: $PARENT_DOMAIN"
    echo "集群区域: $CLUSTER_REGION"
    echo "备份目录: $BACKUP_DIR"
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "域名映射:"
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        echo "  ${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN} -> ${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN} ($service_type)"
    done
    echo ""
}

# 函数：检查阶段依赖
check_stage_dependencies() {
    local stage=$1
    
    case "$stage" in
        "prepare")
            if [[ ! -f "$BACKUP_DIR"/*_endpoints.txt ]]; then
                log_warning "未找到服务发现结果，建议先运行 discovery 阶段"
                read -p "是否继续？(yes/no): " -r
                if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                    exit 0
                fi
            fi
            ;;
        "migrate")
            if [[ ! -f "$BACKUP_DIR"/*_dns_verification.txt ]]; then
                log_warning "未找到目标项目DNS验证结果，建议先运行 prepare 阶段"
                read -p "是否继续？(yes/no): " -r
                if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                    exit 0
                fi
            fi
            ;;
        "rollback")
            if [[ ! -f "$BACKUP_DIR"/*_dns_backup_*.json ]]; then
                log_error "未找到DNS备份文件，无法执行回滚"
                exit 1
            fi
            ;;
        "cleanup")
            if [[ ! -f "$BACKUP_DIR"/migration_report_*.txt ]]; then
                log_warning "未找到迁移报告，建议先完成迁移"
                read -p "是否继续清理？(yes/no): " -r
                if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                    exit 0
                fi
            fi
            ;;
    esac
}

# 函数：执行单个阶段
execute_stage() {
    local stage=$1
    local script_file=""
    
    case "$stage" in
        "discovery")
            script_file="$SCRIPT_DIR/01-discovery.sh"
            ;;
        "prepare")
            script_file="$SCRIPT_DIR/02-prepare-target.sh"
            ;;
        "migrate")
            script_file="$SCRIPT_DIR/03-execute-migration.sh"
            ;;
        "rollback")
            script_file="$SCRIPT_DIR/04-rollback.sh"
            ;;
        "cleanup")
            script_file="$SCRIPT_DIR/05-cleanup.sh"
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
        check_stage_dependencies "$stage"
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

# 函数：执行完整迁移流程
execute_full_migration() {
    log_info "开始执行完整DNS迁移流程..."
    
    local stages=("discovery" "prepare" "migrate")
    
    for stage in "${stages[@]}"; do
        log_info "=== 执行阶段: $stage ==="
        
        if ! execute_stage "$stage"; then
            log_error "阶段 $stage 失败，停止执行"
            echo ""
            echo "建议："
            echo "1. 检查错误日志: $LOG_FILE"
            echo "2. 修复问题后重新运行失败的阶段"
            echo "3. 如需回滚，运行: $0 rollback"
            return 1
        fi
        
        # 在阶段之间添加暂停，让用户有机会检查结果
        if [[ "$FORCE_MODE" != "true" && "$stage" != "migrate" ]]; then
            echo ""
            read -p "阶段 $stage 完成，按回车键继续下一阶段..." -r
        fi
    done
    
    log_success "完整DNS迁移流程执行成功！"
    echo ""
    echo "后续步骤："
    echo "1. 监控目标服务24-48小时"
    echo "2. 验证所有应用功能正常"
    echo "3. 运行清理脚本: $0 cleanup"
}

# 函数：显示迁移状态
show_migration_status() {
    log_info "检查迁移状态..."
    
    echo "=== 迁移状态检查 ==="
    
    # 检查各阶段的输出文件
    local discovery_done=false
    local prepare_done=false
    local migrate_done=false
    local rollback_done=false
    local cleanup_done=false
    
    if [[ -f "$BACKUP_DIR"/*_endpoints.txt ]]; then
        discovery_done=true
        echo "✓ Discovery 阶段已完成"
    else
        echo "✗ Discovery 阶段未完成"
    fi
    
    if [[ -f "$BACKUP_DIR"/*_dns_verification.txt ]]; then
        prepare_done=true
        echo "✓ Prepare 阶段已完成"
    else
        echo "✗ Prepare 阶段未完成"
    fi
    
    if [[ -f "$BACKUP_DIR"/migration_report_*.txt ]]; then
        migrate_done=true
        echo "✓ Migrate 阶段已完成"
        
        # 显示迁移结果摘要
        local latest_report
        latest_report=$(ls -t "$BACKUP_DIR"/migration_report_*.txt 2>/dev/null | head -1 || echo "")
        if [[ -n "$latest_report" ]]; then
            echo "  最新迁移报告: $latest_report"
            local success_count
            success_count=$(grep "成功迁移:" "$latest_report" | cut -d: -f2 | tr -d ' ' || echo "0")
            echo "  迁移结果: $success_count"
        fi
    else
        echo "✗ Migrate 阶段未完成"
    fi
    
    if [[ -f "$BACKUP_DIR"/rollback_report_*.txt ]]; then
        rollback_done=true
        echo "✓ Rollback 已执行"
    fi
    
    if [[ -f "$BACKUP_DIR"/cleanup_report_*.txt ]]; then
        cleanup_done=true
        echo "✓ Cleanup 已完成"
    else
        echo "✗ Cleanup 未完成"
    fi
    
    echo ""
    echo "建议的下一步操作:"
    if [[ "$discovery_done" == false ]]; then
        echo "  $0 discovery"
    elif [[ "$prepare_done" == false ]]; then
        echo "  $0 prepare"
    elif [[ "$migrate_done" == false ]]; then
        echo "  $0 migrate"
    elif [[ "$cleanup_done" == false && "$rollback_done" == false ]]; then
        echo "  $0 cleanup  # 清理源项目资源"
    else
        echo "  迁移流程已完成"
    fi
}

# 解析命令行参数
DRY_RUN=false
VERBOSE=false
FORCE_MODE=false
CUSTOM_CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --source-project)
            SOURCE_PROJECT="$2"
            shift 2
            ;;
        --target-project)
            TARGET_PROJECT="$2"
            shift 2
            ;;
        discovery|prepare|migrate|rollback|cleanup|all|status)
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

# 重新加载自定义配置（如果指定）
if [[ -n "$CUSTOM_CONFIG" ]]; then
    if [[ -f "$CUSTOM_CONFIG" ]]; then
        source "$CUSTOM_CONFIG"
        log_info "使用自定义配置文件: $CUSTOM_CONFIG"
    else
        log_error "配置文件不存在: $CUSTOM_CONFIG"
        exit 1
    fi
fi

# 初始化
setup_directories
check_prerequisites

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