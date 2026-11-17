#!/bin/bash

# GCP Secret Manager 迁移配置文件
# 请根据实际环境修改以下配置

# ==================== 基础项目配置 ====================

# 源项目ID（当前存储密钥的项目）
export SOURCE_PROJECT="your-source-project-id"

# 目标项目ID（要迁移到的项目）
export TARGET_PROJECT="your-target-project-id"

# ==================== 备份和日志配置 ====================

# 备份目录（相对路径，会自动创建时间戳子目录）
export BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"

# 日志文件路径
export LOG_FILE="$BACKUP_DIR/migration.log"

# 是否启用调试模式
export DEBUG=true

# ==================== 迁移配置 ====================

# 批量处理大小（一次处理的密钥数量）
export BATCH_SIZE=10

# 重试次数
export RETRY_COUNT=3

# 重试间隔（秒）
export RETRY_INTERVAL=5

# ==================== 验证配置 ====================

# 是否验证密钥值（可能会增加迁移时间）
export VERIFY_SECRET_VALUES=true

# 验证超时时间（秒）
export VERIFICATION_TIMEOUT=300

# ==================== 应用配置 ====================

# Kubernetes 命名空间列表（用于更新应用配置）
export K8S_NAMESPACES=("default" "production" "staging")

# 需要更新的配置文件模式
export CONFIG_FILE_PATTERNS=(
    "*.yaml"
    "*.yml"
    "*.json"
    "*.env"
)

# ==================== 颜色输出配置 ====================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# ==================== 函数定义 ====================

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
    fi
}

# 检查必要工具
check_prerequisites() {
    local tools=("gcloud" "jq" "kubectl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "以下工具未安装: ${missing_tools[*]}"
        echo "安装指南："
        echo "  gcloud: https://cloud.google.com/sdk/docs/install"
        echo "  kubectl: gcloud components install kubectl"
        echo "  jq: sudo apt-get install jq (Ubuntu) 或 brew install jq (macOS)"
        return 1
    fi
    
    # 检查 gcloud 认证
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud 未认证，请运行 'gcloud auth login'"
        return 1
    fi
    
    log_success "所有必要工具检查通过"
    return 0
}

# 创建必要目录
setup_directories() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/exported_secrets"
    mkdir -p "$BACKUP_DIR/k8s_backups"
    
    if [[ "$DEBUG" == "true" ]]; then
        log_debug "创建备份目录: $BACKUP_DIR"
        log_debug "日志文件: $LOG_FILE"
    fi
}

# 验证项目访问权限
verify_project_access() {
    local project=$1
    
    if ! gcloud projects describe "$project" &>/dev/null; then
        log_error "无法访问项目: $project"
        echo "请检查："
        echo "1. 项目ID是否正确"
        echo "2. 是否有项目访问权限"
        echo "3. gcloud 是否已正确认证"
        return 1
    fi
    
    log_success "项目访问验证通过: $project"
    return 0
}

# 检查 Secret Manager API
check_secret_manager_api() {
    local project=$1
    
    if ! gcloud services list --project="$project" --filter="name:secretmanager.googleapis.com" --format="value(name)" | grep -q secretmanager; then
        log_warning "项目 $project 未启用 Secret Manager API，正在启用..."
        if gcloud services enable secretmanager.googleapis.com --project="$project"; then
            log_success "Secret Manager API 已启用: $project"
        else
            log_error "无法启用 Secret Manager API: $project"
            return 1
        fi
    else
        log_success "Secret Manager API 已启用: $project"
    fi
    
    return 0
}

# 验证配置完整性
validate_config() {
    local errors=()
    
    # 检查必需的配置项
    [[ -z "$SOURCE_PROJECT" ]] && errors+=("SOURCE_PROJECT 未设置")
    [[ -z "$TARGET_PROJECT" ]] && errors+=("TARGET_PROJECT 未设置")
    [[ -z "$BACKUP_DIR" ]] && errors+=("BACKUP_DIR 未设置")
    [[ -z "$LOG_FILE" ]] && errors+=("LOG_FILE 未设置")
    
    # 检查项目ID格式
    if [[ ! "$SOURCE_PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        errors+=("SOURCE_PROJECT 格式不正确")
    fi
    
    if [[ ! "$TARGET_PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        errors+=("TARGET_PROJECT 格式不正确")
    fi
    
    # 检查源项目和目标项目不能相同
    if [[ "$SOURCE_PROJECT" == "$TARGET_PROJECT" ]]; then
        errors+=("源项目和目标项目不能相同")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "配置验证失败："
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_success "配置验证通过"
    return 0
}

# 重试机制
retry_command() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        else
            if [[ $attempt -lt $max_attempts ]]; then
                log_warning "命令执行失败，${delay}秒后重试 (尝试 $attempt/$max_attempts)"
                sleep "$delay"
            else
                log_error "命令执行失败，已达到最大重试次数 ($max_attempts)"
                return 1
            fi
        fi
        ((attempt++))
    done
}

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r${CYAN}[进度]${NC} ["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $remaining | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# 完成进度显示
complete_progress() {
    echo ""
}

# ==================== 初始化检查 ====================

# 如果直接执行此配置文件，进行基本验证
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Secret Manager 迁移工具配置验证"
    echo "=================================="
    
    setup_directories
    
    if validate_config && check_prerequisites; then
        echo ""
        log_success "配置验证完成，可以开始迁移"
        echo ""
        echo "下一步："
        echo "1. 修改配置文件中的项目ID"
        echo "2. 运行: ./migrate-secrets.sh setup"
    else
        echo ""
        log_error "配置验证失败，请修复后重试"
        exit 1
    fi
fi