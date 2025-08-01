#!/bin/bash

# Cloud Run镜像分支校验脚本
# 用于确保生产环境只能部署master分支的镜像

set -e

# 配置参数
ENVIRONMENT=${1:-""}
IMAGE_URL=${2:-""}
REQUIRED_BRANCH="master"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function validate_params() {
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "环境参数不能为空"
        echo "用法: $0 <environment> <image_url>"
        exit 1
    fi
    
    if [[ -z "$IMAGE_URL" ]]; then
        log_error "镜像URL不能为空"
        echo "用法: $0 <environment> <image_url>"
        exit 1
    fi
}

function is_production_environment() {
    local env=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$env" in
        "prd"|"prod"|"production")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

function extract_image_tag() {
    local image_url="$1"
    # 从镜像URL中提取tag部分
    # 例如: europe-west2-docker.pkg.dev/myproject/containers/my-agent:master-abc123
    echo "$image_url" | sed 's/.*://'
}

function validate_branch_in_tag() {
    local tag="$1"
    local required_branch="$2"
    
    # 检查tag是否以required_branch开头
    if [[ "$tag" == "$required_branch"* ]]; then
        return 0
    else
        return 1
    fi
}

function main() {
    log_info "开始镜像分支校验..."
    log_info "环境: $ENVIRONMENT"
    log_info "镜像: $IMAGE_URL"
    
    validate_params
    
    # 如果不是生产环境，跳过校验
    if ! is_production_environment "$ENVIRONMENT"; then
        log_info "非生产环境，跳过分支校验"
        exit 0
    fi
    
    log_warn "检测到生产环境部署，开始严格校验..."
    
    # 提取镜像tag
    IMAGE_TAG=$(extract_image_tag "$IMAGE_URL")
    log_info "镜像标签: $IMAGE_TAG"
    
    # 校验分支
    if validate_branch_in_tag "$IMAGE_TAG" "$REQUIRED_BRANCH"; then
        log_info "✅ 校验通过: 镜像来自 $REQUIRED_BRANCH 分支"
        exit 0
    else
        log_error "❌ 校验失败: 生产环境只能部署来自 $REQUIRED_BRANCH 分支的镜像"
        log_error "当前镜像标签: $IMAGE_TAG"
        log_error "要求分支前缀: $REQUIRED_BRANCH"
        exit 1
    fi
}

main "$@"