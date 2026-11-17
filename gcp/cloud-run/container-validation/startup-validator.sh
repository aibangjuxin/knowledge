#!/bin/bash

# 容器启动时的环境校验脚本
# 在Dockerfile中作为ENTRYPOINT或在应用启动前调用

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function log_info() { echo -e "${GREEN}[STARTUP-VALIDATOR]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[STARTUP-VALIDATOR]${NC} $1"; }
function log_error() { echo -e "${RED}[STARTUP-VALIDATOR]${NC} $1"; }
function log_debug() { echo -e "${BLUE}[STARTUP-VALIDATOR]${NC} $1"; }

# 配置 - 基于命名约定的模式匹配
PRODUCTION_PATTERNS=("*-prd" "*-prod" "*-production")
PRE_PRODUCTION_PATTERNS=("*-ppd" "*-preprod" "*-staging" "*-uat")
DEVELOPMENT_PATTERNS=("*-dev" "*-test" "*-sandbox")
REQUIRED_BRANCH_PREFIX="master"

# 从Cloud Run元数据获取项目信息
function get_project_id() {
    local project_id=""
    
    # 方法1: 从元数据服务获取
    if command -v curl >/dev/null 2>&1; then
        project_id=$(curl -s -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/project/project-id" 2>/dev/null || echo "")
    fi
    
    # 方法2: 从环境变量获取 (如果Cloud Run设置了)
    if [[ -z "$project_id" && -n "$GOOGLE_CLOUD_PROJECT" ]]; then
        project_id="$GOOGLE_CLOUD_PROJECT"
    fi
    
    # 方法3: 从gcloud配置获取 (如果容器内有gcloud)
    if [[ -z "$project_id" ]] && command -v gcloud >/dev/null 2>&1; then
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    fi
    
    echo "$project_id"
}

# 通用的环境检测函数
function get_environment_type() {
    local project_id="$1"
    
    # 检查生产环境模式
    for pattern in "${PRODUCTION_PATTERNS[@]}"; do
        if [[ "$project_id" == $pattern ]]; then
            echo "production"
            return 0
        fi
    done
    
    # 检查预生产环境模式
    for pattern in "${PRE_PRODUCTION_PATTERNS[@]}"; do
        if [[ "$project_id" == $pattern ]]; then
            echo "pre-production"
            return 0
        fi
    done
    
    # 检查开发环境模式
    for pattern in "${DEVELOPMENT_PATTERNS[@]}"; do
        if [[ "$project_id" == $pattern ]]; then
            echo "development"
            return 0
        fi
    done
    
    # 默认为开发环境
    echo "development"
}

# 检查是否为生产环境项目
function is_production_project() {
    local project_id="$1"
    [[ "$(get_environment_type "$project_id")" == "production" ]]
}

# 检查是否为预生产环境项目
function is_pre_production_project() {
    local project_id="$1"
    [[ "$(get_environment_type "$project_id")" == "pre-production" ]]
}

# 获取构建信息 (需要在构建时注入)
function get_build_info() {
    # 这些变量应该在Docker构建时通过ARG注入
    local git_branch="${GIT_BRANCH:-unknown}"
    local git_commit="${GIT_COMMIT:-unknown}"
    local build_time="${BUILD_TIME:-unknown}"
    local build_user="${BUILD_USER:-unknown}"
    
    log_debug "构建信息:"
    log_debug "  分支: $git_branch"
    log_debug "  提交: $git_commit"
    log_debug "  时间: $build_time"
    log_debug "  构建者: $build_user"
    
    echo "$git_branch"
}

# 校验生产环境部署
function validate_production_deployment() {
    local project_id="$1"
    local git_branch="$2"
    
    log_warn "🔒 检测到生产环境项目: $project_id"
    log_warn "执行严格校验..."
    
    # 校验1: 检查分支
    if [[ "$git_branch" != "$REQUIRED_BRANCH_PREFIX"* ]]; then
        log_error "❌ 生产环境校验失败!"
        log_error "生产环境只能部署来自 $REQUIRED_BRANCH_PREFIX 分支的镜像"
        log_error "当前分支: $git_branch"
        log_error "要求分支前缀: $REQUIRED_BRANCH_PREFIX"
        return 1
    fi
    
    # 校验2: 检查环境变量
    if [[ -z "$PRODUCTION_APPROVED" ]]; then
        log_error "❌ 生产环境校验失败!"
        log_error "缺少生产环境批准标识 (PRODUCTION_APPROVED)"
        log_error "请确保通过正确的部署流程部署到生产环境"
        return 1
    fi
    
    # 校验3: 检查必需的生产环境配置
    local required_env_vars=("DATABASE_URL" "API_KEY" "SECRET_KEY")
    for var in "${required_env_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "❌ 生产环境校验失败!"
            log_error "缺少必需的环境变量: $var"
            return 1
        fi
    done
    
    log_info "✅ 生产环境校验通过"
    return 0
}

# 校验预生产环境部署
function validate_pre_production_deployment() {
    local project_id="$1"
    local git_branch="$2"
    
    log_warn "🧪 检测到预生产环境项目: $project_id"
    
    # 预生产环境的校验相对宽松，但仍需要一些基本检查
    if [[ "$git_branch" == "unknown" ]]; then
        log_warn "⚠️  无法确定构建分支，请检查构建流程"
    fi
    
    log_info "✅ 预生产环境校验通过"
    return 0
}

# 主校验函数
function main() {
    log_info "🚀 开始容器启动校验..."
    
    # 获取项目ID
    local project_id=$(get_project_id)
    if [[ -z "$project_id" ]]; then
        log_error "❌ 无法获取GCP项目ID"
        log_error "请确保容器运行在Cloud Run环境中"
        exit 1
    fi
    
    log_info "当前项目: $project_id"
    
    # 获取构建信息
    local git_branch=$(get_build_info)
    
    # 获取环境类型并执行相应校验
    local environment_type=$(get_environment_type "$project_id")
    log_info "环境类型: $environment_type"
    
    case "$environment_type" in
        "production")
            if ! validate_production_deployment "$project_id" "$git_branch"; then
                log_error "🚫 生产环境校验失败，容器启动被阻止"
                exit 1
            fi
            ;;
        "pre-production")
            if ! validate_pre_production_deployment "$project_id" "$git_branch"; then
                log_error "🚫 预生产环境校验失败，容器启动被阻止"
                exit 1
            fi
            ;;
        *)
            log_info "ℹ️  开发/测试环境，跳过严格校验"
            ;;
    esac
    
    log_info "🎉 容器启动校验完成，继续启动应用..."
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi