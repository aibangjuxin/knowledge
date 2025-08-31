#!/bin/bash

# GCP DNS 迁移配置示例文件
# 复制此文件为 config.sh 并根据实际环境修改配置

# ==================== 基础项目配置 ====================

# 源项目ID（当前运行服务的项目）
export SOURCE_PROJECT="my-source-project-123"

# 目标项目ID（要迁移到的项目）
export TARGET_PROJECT="my-target-project-456"

# 父域名（不包含项目前缀）
export PARENT_DOMAIN="dev.aliyun.cloud.uk.aibang"

# ==================== DNS Zone 配置 ====================

# DNS Zone 名称（通常基于项目和域名自动生成）
# 格式：project-id-domain-with-dashes
export SOURCE_ZONE="my-source-project-123-dev-aliyun-cloud-uk-aibang"
export TARGET_ZONE="my-target-project-456-dev-aliyun-cloud-uk-aibang"

# ==================== GKE 集群配置 ====================

# 源项目集群名称
export SOURCE_CLUSTER="gke-cluster-prod"

# 目标项目集群名称
export TARGET_CLUSTER="gke-cluster-new"

# 集群所在区域
export CLUSTER_REGION="europe-west2"

# ==================== 域名映射配置 ====================

# 域名映射数组，格式：subdomain:service_type
# service_type 可选值：
#   - ingress: GKE Ingress Controller
#   - ilb: Internal Load Balancer  
#   - service: LoadBalancer Service

export DOMAIN_MAPPINGS=(
    # API 服务 - 通过 Ingress 暴露
    "api:ingress"
    
    # 事件服务 - 通过 Internal Load Balancer 暴露
    "events:ilb"
    
    # 代理服务 - 通过 Ingress 暴露
    "events-proxy:ingress"
    
    # 管理后台 - 通过 Ingress 暴露
    "admin:ingress"
    
    # WebSocket 服务 - 通过 LoadBalancer Service 暴露
    "ws:service"
    
    # 监控服务 - 通过 Ingress 暴露
    "monitoring:ingress"
)

# ==================== DNS 配置 ====================

# 默认 TTL（秒）
export DEFAULT_TTL=300

# 迁移期间使用的低 TTL（秒）
export MIGRATION_TTL=60

# ==================== 备份和日志配置 ====================

# 备份目录（相对路径，会自动创建时间戳子目录）
export BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"

# 日志文件路径
export LOG_FILE="./logs/migration_$(date +%Y%m%d_%H%M%S).log"

# 是否启用调试模式
export DEBUG=true

# ==================== 验证配置 ====================

# DNS 验证超时时间（秒）
export VALIDATION_TIMEOUT=300

# 健康检查端点列表
export HEALTH_CHECK_ENDPOINTS=(
    "/health"
    "/api/v1/health"
    "/healthz"
    "/status"
    "/ping"
)

# ==================== 颜色输出配置 ====================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# ==================== 高级配置 ====================

# SSL 证书配置
export SSL_CERT_NAME="migration-cert"
export SSL_CERT_NAMESPACE="default"

# 网络配置
export VPC_NETWORK="default"
export SUBNET_NAME="default"

# IAM 配置
export SERVICE_ACCOUNT_EMAIL="migration-sa@${TARGET_PROJECT}.iam.gserviceaccount.com"

# 监控配置
export ENABLE_MONITORING=true
export MONITORING_NAMESPACE="monitoring"

# ==================== 环境特定配置 ====================

# 开发环境配置
if [[ "${ENVIRONMENT:-}" == "dev" ]]; then
    export DEFAULT_TTL=60
    export VALIDATION_TIMEOUT=120
    export DEBUG=true
fi

# 生产环境配置
if [[ "${ENVIRONMENT:-}" == "prod" ]]; then
    export DEFAULT_TTL=3600
    export VALIDATION_TIMEOUT=600
    export DEBUG=false
fi

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

# 检查必要工具
check_prerequisites() {
    local tools=("gcloud" "kubectl" "dig" "jq" "curl")
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
        echo "  dig: sudo apt-get install dnsutils (Ubuntu)"
        echo "  curl: 通常系统自带"
        return 1
    fi
    
    # 检查 gcloud 认证
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud 未认证，请运行 'gcloud auth login'"
        return 1
    fi
    
    # 检查 kubectl 配置
    if ! kubectl version --client &>/dev/null; then
        log_warning "kubectl 可能未正确配置"
    fi
    
    log_success "所有必要工具检查通过"
    return 0
}

# 创建必要目录
setup_directories() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
    
    if [[ "$DEBUG" == "true" ]]; then
        log_info "创建备份目录: $BACKUP_DIR"
        log_info "日志文件: $LOG_FILE"
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

# 验证配置完整性
validate_config() {
    local errors=()
    
    # 检查必需的配置项
    [[ -z "$SOURCE_PROJECT" ]] && errors+=("SOURCE_PROJECT 未设置")
    [[ -z "$TARGET_PROJECT" ]] && errors+=("TARGET_PROJECT 未设置")
    [[ -z "$PARENT_DOMAIN" ]] && errors+=("PARENT_DOMAIN 未设置")
    [[ -z "$CLUSTER_REGION" ]] && errors+=("CLUSTER_REGION 未设置")
    [[ ${#DOMAIN_MAPPINGS[@]} -eq 0 ]] && errors+=("DOMAIN_MAPPINGS 为空")
    
    # 检查项目ID格式
    if [[ ! "$SOURCE_PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        errors+=("SOURCE_PROJECT 格式不正确")
    fi
    
    if [[ ! "$TARGET_PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        errors+=("TARGET_PROJECT 格式不正确")
    fi
    
    # 检查域名映射格式
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        if [[ ! "$mapping" =~ ^[a-z0-9-]+:(ingress|ilb|service)$ ]]; then
            errors+=("域名映射格式错误: $mapping")
        fi
    done
    
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

# ==================== 配置验证 ====================

# 在配置加载后自动验证
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 直接执行此配置文件时进行验证
    setup_directories
    validate_config
    echo "配置文件验证完成"
fi