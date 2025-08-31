#!/bin/bash

# GCP DNS 迁移配置文件
# 请根据实际环境修改以下配置

# 项目配置
export SOURCE_PROJECT="project-id"
export TARGET_PROJECT="project-id2"
export PARENT_DOMAIN="dev.aliyun.cloud.uk.aibang"

# DNS Zone 配置
export SOURCE_ZONE="${SOURCE_PROJECT}-${PARENT_DOMAIN//./-}"
export TARGET_ZONE="${TARGET_PROJECT}-${PARENT_DOMAIN//./-}"

# 集群配置
export SOURCE_CLUSTER="gke-01"
export TARGET_CLUSTER="gke-01"
export CLUSTER_REGION="europe-west2"

# 域名映射配置 (格式: "subdomain:service_type")
# service_type: ingress|ilb|service
export DOMAIN_MAPPINGS=(
    "events:ilb"
    "events-proxy:ingress"
    "api:ingress"
    "admin:ingress"
)

# DNS TTL 配置
export DEFAULT_TTL=300
export MIGRATION_TTL=60

# 备份目录
export BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"

# 日志配置
export LOG_FILE="./logs/migration_$(date +%Y%m%d_%H%M%S).log"
export DEBUG=true

# 验证配置
export VALIDATION_TIMEOUT=300  # 5分钟
export HEALTH_CHECK_ENDPOINTS=(
    "/health"
    "/api/health"
    "/status"
)

# 颜色输出配置
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# 函数：打印带颜色的日志
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

# 函数：检查必要的工具
check_prerequisites() {
    local tools=("gcloud" "kubectl" "dig" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool 未安装或不在 PATH 中"
            return 1
        fi
    done
    
    # 检查 gcloud 认证
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud 未认证，请运行 'gcloud auth login'"
        return 1
    fi
    
    log_success "所有必要工具检查通过"
    return 0
}

# 函数：创建必要的目录
setup_directories() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
    log_info "创建目录: $BACKUP_DIR"
}

# 函数：验证项目访问权限
verify_project_access() {
    local project=$1
    if ! gcloud projects describe "$project" &>/dev/null; then
        log_error "无法访问项目: $project"
        return 1
    fi
    log_success "项目访问验证通过: $project"
    return 0
}