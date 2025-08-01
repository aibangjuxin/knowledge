#!/bin/bash

# 容器启动时的环境校验脚本 - 通用版本
# 支持多种配置方式：环境变量、配置文件、命名约定

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

# 默认配置文件路径
CONFIG_FILE="${VALIDATOR_CONFIG_FILE:-/app/config/validator.conf}"

# 加载配置
function load_config() {
    # 方法1: 从环境变量加载
    if [[ -n "$ENVIRONMENT_PATTERNS" ]]; then
        log_debug "从环境变量加载配置"
        return 0
    fi
    
    # 方法2: 从配置文件加载
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "从配置文件加载: $CONFIG_FILE"
        source "$CONFIG_FILE"
        return 0
    fi
    
    # 方法3: 使用默认命名约定
    log_debug "使用默认命名约定"
    PRODUCTION_PATTERNS=("*-prd" "*-prod" "*-production")
    PRE_PRODUCTION_PATTERNS=("*-ppd" "*-preprod" "*-staging" "*-uat")
    DEVELOPMENT_PATTERNS=("*-dev" "*-test" "*-sandbox")
}

# 通用的环境检测函数
function get_environment_type() {
    local project_id="$1"
    
    # 方法1: 直接从环境变量获取
    if [[ -n "$FORCE_ENVIRONMENT_TYPE" ]]; then
        echo "$FORCE_ENVIRONMENT_TYPE"
        return 0
    fi
    
    # 方法2: 从项目标签获取 (如果可用)
    local env_from_labels=$(get_environment_from_labels "$project_id")
    if [[ -n "$env_from_labels" ]]; then
        echo "$env_from_labels"
        return 0
    fi
    
    # 方法3: 基于命名模式匹配
    local env_from_pattern=$(get_environment_from_pattern "$project_id")
    echo "$env_from_pattern"
}

# 从GCP项目标签获取环境类型
function get_environment_from_labels() {
    local project_id="$1"
    
    # 尝试使用gcloud获取项目标签
    if command -v gcloud >/dev/null 2>&1; then
        local env_label=$(gcloud projects describe "$project_id" \
            --format="value(labels.environment)" 2>/dev/null || echo "")
        
        if [[ -n "$env_label" ]]; then
            case "$env_label" in
                "prod"|"production") echo "production" ;;
                "preprod"|"staging"|"uat") echo "pre-production" ;;
                "dev"|"development"|"test") echo "development" ;;
                *) echo "$env_label" ;;
            esac
            return 0
        fi
    fi
    
    echo ""
}

# 基于命名模式获取环境类型
function get_environment_from_pattern() {
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

# 从Cloud Run元数据获取项目信息
function get_project_id() {
    local project_id=""
    
    # 方法1: 从元数据服务获取
    if command -v curl >/dev/null 2>&1; then
        project_id=$(curl -s -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/project/project-id" 2>/dev/null || echo "")
    fi
    
    # 方法2: 从环境变量获取
    if [[ -z "$project_id" && -n "$GOOGLE_CLOUD_PROJECT" ]]; then
        project_id="$GOOGLE_CLOUD_PROJECT"
    fi
    
    # 方法3: 从gcloud配置获取
    if [[ -z "$project_id" ]] && command -v gcloud >/dev/null 2>&1; then
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    fi
    
    echo "$project_id"
}

# 获取构建信息
function get_build_info() {
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

# 根据环境类型执行校验
function validate_environment() {
    local project_id="$1"
    local environment_type="$2"
    local git_branch="$3"
    
    case "$environment_type" in
        "production")
            validate_production_deployment "$project_id" "$git_branch"
            ;;
        "pre-production")
            validate_pre_production_deployment "$project_id" "$git_branch"
            ;;
        "development")
            validate_development_deployment "$project_id" "$git_branch"
            ;;
        *)
            log_warn "未知环境类型: $environment_type，使用开发环境校验"
            validate_development_deployment "$project_id" "$git_branch"
            ;;
    esac
}

# 校验生产环境部署
function validate_production_deployment() {
    local project_id="$1"
    local git_branch="$2"
    
    log_warn "🔒 检测到生产环境项目: $project_id"
    log_warn "执行严格校验..."
    
    # 可配置的分支要求
    local required_branch="${REQUIRED_PRODUCTION_BRANCH:-master}"
    
    if [[ "$git_branch" != "$required_branch"* ]]; then
        log_error "❌ 生产环境校验失败!"
        log_error "生产环境只能部署来自 $required_branch 分支的镜像"
        log_error "当前分支: $git_branch"
        return 1
    fi
    
    if [[ -z "$PRODUCTION_APPROVED" ]]; then
        log_error "❌ 生产环境校验失败!"
        log_error "缺少生产环境批准标识 (PRODUCTION_APPROVED)"
        return 1
    fi
    
    log_info "✅ 生产环境校验通过"
    return 0
}

# 校验预生产环境部署
function validate_pre_production_deployment() {
    local project_id="$1"
    local git_branch="$2"
    
    log_warn "🧪 检测到预生产环境项目: $project_id"
    
    if [[ "$git_branch" == "unknown" ]]; then
        log_warn "⚠️  无法确定构建分支，请检查构建流程"
    fi
    
    log_info "✅ 预生产环境校验通过"
    return 0
}

# 校验开发环境部署
function validate_development_deployment() {
    local project_id="$1"
    local git_branch="$2"
    
    log_info "🛠️  开发环境项目: $project_id，跳过严格校验"
    return 0
}

# 主校验函数
function main() {
    log_info "🚀 开始容器启动校验..."
    
    # 加载配置
    load_config
    
    # 获取项目ID
    local project_id=$(get_project_id)
    if [[ -z "$project_id" ]]; then
        log_error "❌ 无法获取GCP项目ID"
        exit 1
    fi
    
    # 获取环境类型
    local environment_type=$(get_environment_type "$project_id")
    log_info "当前项目: $project_id (环境: $environment_type)"
    
    # 获取构建信息
    local git_branch=$(get_build_info)
    
    # 执行环境特定的校验
    if ! validate_environment "$project_id" "$environment_type" "$git_branch"; then
        log_error "🚫 环境校验失败，容器启动被阻止"
        exit 1
    fi
    
    log_info "🎉 容器启动校验完成，继续启动应用..."
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi