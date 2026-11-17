#!/bin/bash

# GKE 跨项目 Namespace 迁移工具
# 作者: Migration Tool Team
# 版本: 1.0.0

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
EXPORTS_DIR="${SCRIPT_DIR}/exports"
BACKUPS_DIR="${SCRIPT_DIR}/backups"
LOGS_DIR="${SCRIPT_DIR}/logs"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# 创建必要目录
mkdir -p "${EXPORTS_DIR}" "${BACKUPS_DIR}" "${LOGS_DIR}"

# 日志文件
LOG_FILE="${LOGS_DIR}/migration-$(date +%Y%m%d_%H%M%S).log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
NAMESPACE=""
DRY_RUN=false
RESOURCES=""
EXCLUDE=""
BACKUP_ENABLED=true
FORCE=false
TIMEOUT=300
VERBOSE=false

# 日志函数
log() {
    local level=$1
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
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            else
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
GKE 跨项目 Namespace 迁移工具

用法: $0 [选项]

选项:
    -n, --namespace NAMESPACE    指定要迁移的 namespace (必需)
    --dry-run                   干运行模式，不实际执行迁移
    --resources TYPES           指定要迁移的资源类型 (逗号分隔)
    --exclude TYPES             排除特定资源类型 (逗号分隔)
    --backup                    强制创建备份
    --no-backup                 跳过备份
    --force                     强制覆盖已存在的资源
    --timeout SECONDS           设置超时时间 (默认: 300)
    -v, --verbose               详细输出
    -h, --help                  显示此帮助信息

示例:
    $0 -n my-app                           # 迁移 my-app namespace
    $0 -n app1,app2,app3                   # 迁移多个 namespace
    $0 -n my-app --dry-run                 # 干运行模式
    $0 -n my-app --resources deployments,services  # 只迁移指定资源
    $0 -n my-app --exclude secrets         # 排除 secrets

配置文件: config/config.yaml
EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --resources)
                RESOURCES="$2"
                shift 2
                ;;
            --exclude)
                EXCLUDE="$2"
                shift 2
                ;;
            --backup)
                BACKUP_ENABLED=true
                shift
                ;;
            --no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
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

    if [[ -z "$NAMESPACE" ]]; then
        log "ERROR" "必须指定 namespace (-n 或 --namespace)"
        show_help
        exit 1
    fi
}

# 加载配置文件
load_config() {
    local config_file="${CONFIG_DIR}/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "配置文件不存在: $config_file"
        exit 1
    fi

    log "INFO" "加载配置文件: $config_file"
    
    # 解析 YAML 配置文件 (支持 yq 或使用 grep/awk 备用方案)
    if command -v yq >/dev/null 2>&1; then
        log "DEBUG" "使用 yq 解析配置文件"
        SOURCE_PROJECT=$(yq eval '.source.project' "$config_file")
        SOURCE_CLUSTER=$(yq eval '.source.cluster' "$config_file")
        SOURCE_ZONE=$(yq eval '.source.zone' "$config_file")
        TARGET_PROJECT=$(yq eval '.target.project' "$config_file")
        TARGET_CLUSTER=$(yq eval '.target.cluster' "$config_file")
        TARGET_ZONE=$(yq eval '.target.zone' "$config_file")
    else
        log "INFO" "yq 未安装，使用 grep/awk 解析配置文件"
        # 简化的配置解析，使用 grep + awk + sed
        SOURCE_PROJECT=$(grep -A 10 "^source:" "$config_file" | grep "project:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
        SOURCE_CLUSTER=$(grep -A 10 "^source:" "$config_file" | grep "cluster:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
        SOURCE_ZONE=$(grep -A 10 "^source:" "$config_file" | grep "zone:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
        TARGET_PROJECT=$(grep -A 10 "^target:" "$config_file" | grep "project:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
        TARGET_CLUSTER=$(grep -A 10 "^target:" "$config_file" | grep "cluster:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
        TARGET_ZONE=$(grep -A 10 "^target:" "$config_file" | grep "zone:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
    fi

    log "DEBUG" "源项目: $SOURCE_PROJECT, 集群: $SOURCE_CLUSTER, 区域: $SOURCE_ZONE"
    log "DEBUG" "目标项目: $TARGET_PROJECT, 集群: $TARGET_CLUSTER, 区域: $TARGET_ZONE"
}

# 检查依赖工具
check_dependencies() {
    log "INFO" "检查依赖工具..."
    
    local tools=("kubectl" "gcloud")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "ERROR" "缺少必需工具: $tool"
            exit 1
        fi
    done
    
    log "INFO" "依赖工具检查完成"
}

# 连接到源集群
connect_source_cluster() {
    log "INFO" "连接到源集群..."
    
    gcloud container clusters get-credentials "$SOURCE_CLUSTER" \
        --zone "$SOURCE_ZONE" \
        --project "$SOURCE_PROJECT" || {
        log "ERROR" "无法连接到源集群"
        exit 1
    }
    
    # 验证连接
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "源集群连接验证失败"
        exit 1
    fi
    
    log "INFO" "成功连接到源集群"
}

# 连接到目标集群
connect_target_cluster() {
    log "INFO" "连接到目标集群..."
    
    gcloud container clusters get-credentials "$TARGET_CLUSTER" \
        --zone "$TARGET_ZONE" \
        --project "$TARGET_PROJECT" || {
        log "ERROR" "无法连接到目标集群"
        exit 1
    }
    
    # 验证连接
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "目标集群连接验证失败"
        exit 1
    fi
    
    log "INFO" "成功连接到目标集群"
}

# 执行迁移
execute_migration() {
    local namespaces=(${NAMESPACE//,/ })
    
    for ns in "${namespaces[@]}"; do
        log "INFO" "开始迁移 namespace: $ns"
        
        # 导出资源
        log "INFO" "导出 namespace $ns 的资源..."
        connect_source_cluster
        
        if ! "${SCRIPTS_DIR}/export.sh" "$ns" "$RESOURCES" "$EXCLUDE"; then
            log "ERROR" "导出 namespace $ns 失败"
            continue
        fi
        
        # 导入资源
        log "INFO" "导入 namespace $ns 的资源..."
        connect_target_cluster
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "干运行模式: 跳过实际导入"
            "${SCRIPTS_DIR}/validate.sh" "$ns" --dry-run
        else
            if ! "${SCRIPTS_DIR}/import.sh" "$ns" "$FORCE" "$TIMEOUT"; then
                log "ERROR" "导入 namespace $ns 失败"
                continue
            fi
            
            # 验证迁移结果
            "${SCRIPTS_DIR}/validate.sh" "$ns"
        fi
        
        log "INFO" "namespace $ns 迁移完成"
    done
}

# 主函数
main() {
    log "INFO" "开始 GKE Namespace 迁移"
    log "INFO" "日志文件: $LOG_FILE"
    
    parse_args "$@"
    load_config
    check_dependencies
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "运行模式: 干运行 (不会实际执行迁移)"
    fi
    
    execute_migration
    
    log "INFO" "迁移完成"
    log "INFO" "详细日志请查看: $LOG_FILE"
}

# 错误处理
trap 'log "ERROR" "脚本执行失败，退出码: $?"' ERR

# 执行主函数
main "$@"