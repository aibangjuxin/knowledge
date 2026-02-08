#!/bin/bash

#####################################################################
# 脚本说明：获取 API Token 并执行健康检查
# 用法：./curl-token.sh [OPTIONS]
# 选项：
#   -u, --url <URL>       健康检查的 URL (默认: https://www.example.com/.well-known/health)
#   -e, --env <FILE>      环境变量配置文件 (默认: .env)
#   -h, --help            显示帮助信息
#####################################################################

set -euo pipefail

# 默认值
DEFAULT_HEALTH_URL="https://www.example.com/.well-known/health"
DEFAULT_ENV_FILE=".env"
DEFAULT_TOKEN_URL=""  # 需要填写实际的 token URL

# 初始化变量
HEALTH_URL="${DEFAULT_HEALTH_URL}"
ENV_FILE="${DEFAULT_ENV_FILE}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 帮助函数
show_help() {
    cat << EOF
使用方法: $0 [OPTIONS]

选项:
    -u, --url <URL>       健康检查的 URL (默认: ${DEFAULT_HEALTH_URL})
    -e, --env <FILE>      环境变量配置文件 (默认: ${DEFAULT_ENV_FILE})
    -t, --token-url <URL> Token 获取 URL
    -h, --help            显示此帮助信息

示例:
    $0
    $0 -u https://api.example.com/health
    $0 --url https://api.example.com/health --env prod.env

环境变量 (在 .env 文件中配置):
    API_USERNAME    API 用户名
    API_PASSWORD    API 密码
    TOKEN_URL       Token 获取 URL (可选)
EOF
    exit 0
}

# 参数解析
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                HEALTH_URL="$2"
                shift 2
                ;;
            -e|--env)
                ENV_FILE="$2"
                shift 2
                ;;
            -t|--token-url)
                TOKEN_URL="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}" >&2
                show_help
                ;;
        esac
    done
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        log_info "加载环境变量文件: $ENV_FILE"
        # 更安全的方式加载环境变量
        set -a
        source "$ENV_FILE"
        set +a
    else
        log_warn "环境变量文件不存在: $ENV_FILE"
    fi
}

# 验证必要的环境变量
validate_credentials() {
    local missing_vars=()
    
    if [ -z "${API_USERNAME:-}" ]; then
        missing_vars+=("API_USERNAME")
    fi
    
    if [ -z "${API_PASSWORD:-}" ]; then
        missing_vars+=("API_PASSWORD")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "缺少必要的环境变量: ${missing_vars[*]}"
        log_error "请在 $ENV_FILE 文件中设置这些变量"
        exit 1
    fi
}

# 获取 Token
get_token() {
    local token_url="${TOKEN_URL:-${DEFAULT_TOKEN_URL}}"
    
    if [ -z "$token_url" ]; then
        log_error "Token URL 未设置，请通过 -t 参数或 TOKEN_URL 环境变量指定"
        exit 1
    fi
    
    log_info "正在获取 Token..."
    
    local response
    local http_code
    
    # 使用 curl 获取 token，同时获取 HTTP 状态码
    response=$(curl --silent --show-error --write-out "\n%{http_code}" \
        --request POST \
        --header "Content-Type: application/json" \
        --data "{
            \"input_token_state\": {
                \"token_type\": \"CREDENTIAL\",
                \"username\": \"$API_USERNAME\",
                \"password\": \"$API_PASSWORD\"
            },
            \"output_token_status\": {
                \"token_type\": \"JWT\"
            }
        }" \
        "$token_url" 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "获取 Token 失败"
        log_error "响应: $response"
        exit 1
    fi
    
    # 分离响应体和状态码
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    # 检查 HTTP 状态码
    if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        log_error "HTTP 请求失败，状态码: $http_code"
        log_error "响应: $response"
        exit 1
    fi
    
    # 使用 jq 解析 JSON (如果可用)，否则使用 awk
    local token
    if command -v jq &> /dev/null; then
        token=$(echo "$response" | jq -r '.token // .access_token // .jwt // empty')
    else
        # 备用方案：使用 awk
        token=$(echo "$response" | awk -F: '{print $2}' | tr -d '}\"' | tr -d '[:space:]')
    fi
    
    if [ -z "$token" ]; then
        log_error "无法从响应中提取 Token"
        log_error "响应: $response"
        exit 1
    fi
    
    echo "$token"
}

# 执行健康检查
health_check() {
    local token="$1"
    local url="$2"
    
    log_info "执行健康检查: $url"
    
    local http_code
    http_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
        --request POST \
        --header "trust-Token: $token" \
        "$url")
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 204 ]; then
        log_info "健康检查成功 (HTTP $http_code)"
        return 0
    else
        log_error "健康检查失败 (HTTP $http_code)"
        return 1
    fi
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    # 加载环境变量
    load_env
    
    # 验证必要的凭证
    validate_credentials
    
    # 获取 Token
    local token
    token=$(get_token)
    
    if [ -z "$token" ]; then
        log_error "获取 Token 失败"
        exit 1
    fi
    
    log_info "Token 获取成功"
    log_info "Token (前10个字符): ${token:0:10}..."
    
    # 执行健康检查
    if health_check "$token" "$HEALTH_URL"; then
        log_info "所有检查通过"
        exit 0
    else
        log_error "健康检查失败"
        exit 1
    fi
}

# 执行主函数
main "$@"