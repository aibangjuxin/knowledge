#!/bin/bash

# 容器启动时的环境校验脚本 - JSON配置版本
# 支持JSON配置文件和环境变量覆盖

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

# 配置文件路径
CONFIG_FILE="${VALIDATOR_CONFIG_FILE:-/app/config/validator.json}"

# 从JSON配置获取环境类型
function get_environment_from_config() {
    local project_id="$1"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    
    # 使用jq解析JSON配置
    if command -v jq >/dev/null 2>&1; then
        # 直接匹配项目ID
        local env_type=$(jq -r --arg pid "$project_id" \
            '.environments[] | select(.projects[]? == $pid) | .type' \
            "$CONFIG_FILE" 2>/dev/null | head -1)
        
        if [[ -n "$env_type" && "$env_type" != "null" ]]; then
            echo "$env_type"
            return 0
        fi
        
        # 模式匹配
        local patterns=$(jq -r '.environments[].patterns[]?' "$CONFIG_FILE" 2>/dev/null)
        while IFS= read -r pattern; do
            if [[ -n "$pattern" && "$project_id" == $pattern ]]; then
                local env_type=$(jq -r --arg pat "$pattern" \
                    '.environments[] | select(.patterns[]? == $pat) | .type' \
                    "$CONFIG_FILE" 2>/dev/null | head -1)
                if [[ -n "$env_type" && "$env_type" != "null" ]]; then
                    echo "$env_type"
                    return 0
                fi
            fi
        done <<< "$patterns"
    fi
    
    return 1
}

# 通用的环境检测函数
function get_environment_type() {
    local project_id="$1"
    
    # 方法1: 强制环境类型
    if [[ -n "$FORCE_ENVIRONMENT_TYPE" ]]; then
        echo "$FORCE_ENVIRONMENT_TYPE"
        return 0
    fi
    
    # 方法2: 从JSON配置获取
    local env_from_config=$(get_environment_from_config "$project_id")
    if [[ -n "$env_from_config" ]]; then
        echo "$env_from_config"
        return 0
    fi
    
    # 方法3: 从项目标签获取
    local env_from_labels=$(get_environment_from_labels "$project_id")
    if [[ -n "$env_from_labels" ]]; then
        echo "$env_from_labels"
        return 0
    fi
    
    # 方法4: 基于默认命名约定
    get_environment_from_pattern "$project_id"
}

# 从GCP项目标签获取环境类型
function get_environment_from_labels() {
    local project_id="$1"
    
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

# 基于默认命名模式获取环境类型
function get_environment_from_pattern() {
    local project_id="$1"
    
    # 生产环境模式
    local prod_patterns=("*-prd" "*-prod" "*-production")
    for pattern in "${prod_patterns[@]}"; do
        if [[ "$project_id" == $pattern ]]; then
            echo "production"
            return 0
        fi
    done
    
    # 预生产环境模式
    local preprod_patterns=("*-ppd" "*-preprod" "*-staging" "*-uat")
    for pattern in "${preprod_patterns[@]}"; do
        if [[ "$project_id" == $pattern ]]; then
            echo "pre-production"
            return 0
        fi
    done
    
    # 默认为开发环境
    echo "development"
}

# 从JSON配置获取环境特定的校验规则
function get_validation_rules() {
    local environment_type="$1"
    
    if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -r --arg env "$environment_type" \
            '.environments[] | select(.type == $env) | .validation' \
            "$CONFIG_FILE" 2>/dev/null
    else
        echo "{}"
    fi
}

# 从Cloud Run元数据获取项目信息
function get_project_id() {
    local project_id=""
    
    if command -v curl >/dev/null 2>&1; then
        project_id=$(curl -s -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/project/project-id" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$project_id" && -n "$GOOGLE_CLOUD_PROJECT" ]]; then
        project_id="$GOOGLE_CLOUD_PROJECT"
    fi
    
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

# 通用校验函数
function validate_environment() {
    local project_id="$1"
    local environment_type="$2"
    local git_branch="$3"
    
    log_info "🔍 校验环境: $environment_type"
    
    # 获取校验规则
    local validation_rules=$(get_validation_rules "$environment_type")
    
    # 分支校验
    if command -v jq >/dev/null 2>&1 && [[ -n "$validation_rules" ]]; then
        local required_branch=$(echo "$validation_rules" | jq -r '.required_branch // empty')
        if [[ -n "$required_branch" && "$git_branch" != "$required_branch"* ]]; then
            log_error "❌ 分支校验失败!"
            log_error "要求分支: $required_branch, 当前分支: $git_branch"
            return 1
        fi
        
        # 环境变量校验
        local required_env_vars=$(echo "$validation_rules" | jq -r '.required_env_vars[]? // empty')
        while IFS= read -r var; do
            if [[ -n "$var" && -z "${!var}" ]]; then
                log_error "❌ 缺少必需的环境变量: $var"
                return 1
            fi
        done <<< "$required_env_vars"
        
        # 审批校验
        local requires_approval=$(echo "$validation_rules" | jq -r '.requires_approval // false')
        if [[ "$requires_approval" == "true" && -z "$DEPLOYMENT_APPROVED" ]]; then
            log_error "❌ 缺少部署审批标识"
            return 1
        fi
    else
        # 回退到基本校验
        case "$environment_type" in
            "production")
                if [[ "$git_branch" != "master"* ]]; then
                    log_error "❌ 生产环境只能部署master分支"
                    return 1
                fi
                if [[ -z "$PRODUCTION_APPROVED" ]]; then
                    log_error "❌ 缺少生产环境批准标识"
                    return 1
                fi
                ;;
        esac
    fi
    
    log_info "✅ 环境校验通过"
    return 0
}

# 主校验函数
function main() {
    log_info "🚀 开始容器启动校验..."
    
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
    
    # 执行校验
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