#!/bin/bash
set -euo pipefail

#######################################
# Firestore 精准字段查询工具
# 用于快速检索 Firestore 中特定 collection 下的字段值
#######################################

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_result() { echo -e "${CYAN}[RESULT]${NC} $1"; }

#######################################
# Defaults
#######################################
proxy=""
tk=""
project_id=""
config_file=""

#######################################
# 默认配置示例
# 格式: collection:document_id:field_path
# field_path 使用点号分隔，例如: env.region.abc
#######################################
declare -a QUERY_LIST=(
    # "capteams:team001:env.region.abc"
    # "users:user123:settings.notification.email"
    # "configs:config001:database.connection.host"
)

#######################################
# Usage
#######################################
usage() {
    cat <<EOF
用法: $0 [-f config_file] [-p proxy] [-t token] [-P project_id] [-h]

选项:
  -f config_file  配置文件路径 (每行格式: collection:document_id:field_path)
  -p proxy        HTTP proxy (例如: host:port)
  -t token        Access token (省略则使用 gcloud auth print-access-token)
  -P project_id   GCP Project ID (默认使用当前 gcloud project)
  -h              显示帮助信息

配置文件格式:
  每行一个查询配置，格式为: collection:document_id:field_path
  field_path 使用点号分隔多层字段，例如:
    capteams:team001:env.region.abc
    users:user123:settings.notification.email
    configs:config001:database.connection.host

示例:
  # 使用配置文件
  $0 -f queries.txt -P my-project
  
  # 使用代理
  $0 -f queries.txt -p proxy.example.com:3128
  
  # 提供自定义 token
  $0 -f queries.txt -t \$(gcloud auth print-access-token)

注意:
  - 如果不提供配置文件，请编辑脚本中的 QUERY_LIST 数组
  - 字段路径支持嵌套，使用点号分隔 (例如: env.region.abc)
  - 结果直接打印到标准输出，格式化的 JSON
EOF
    exit 1
}

#######################################
# 参数解析
#######################################
while getopts ":f:p:t:P:h" opt; do
    case "$opt" in
        f) config_file="$OPTARG" ;;
        p) proxy="$OPTARG" ;;
        t) tk="$OPTARG" ;;
        P) project_id="$OPTARG" ;;
        h) usage ;;
        :) log_error "选项 -$OPTARG 缺少参数"; usage ;;
        \?) log_error "未知选项: -$OPTARG"; usage ;;
    esac
done

#######################################
# 从配置文件加载查询列表
#######################################
if [ -n "$config_file" ]; then
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在: $config_file"
        exit 2
    fi
    
    QUERY_LIST=()
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        QUERY_LIST+=("$line")
    done < "$config_file"
fi

#######################################
# 验证配置
#######################################
if [ ${#QUERY_LIST[@]} -eq 0 ]; then
    log_error "查询列表为空。请提供配置文件 (-f) 或编辑脚本中的 QUERY_LIST 数组。"
    usage
fi

#######################################
# 获取 Project ID
#######################################
if [ -z "$project_id" ]; then
    if command -v gcloud >/dev/null 2>&1; then
        project_id=$(gcloud config get-value project 2>/dev/null) || true
    fi
    if [ -z "$project_id" ]; then
        log_error "未提供 Project ID 且无法通过 gcloud 获取。"
        exit 2
    fi
fi

#######################################
# 获取 Token
#######################################
if [ -z "$tk" ]; then
    if command -v gcloud >/dev/null 2>&1; then
        log_info "未提供 token，使用 gcloud 获取..."
        tk=$(gcloud auth print-access-token)
    else
        log_error "未提供 token 且 gcloud 命令不可用。请使用 -t 参数提供 token。"
        exit 2
    fi
fi

#######################################
# 检查依赖
#######################################
if ! command -v jq >/dev/null 2>&1; then
    log_error "需要 jq 但未安装。"
    exit 3
fi

#######################################
# 显示配置信息
#######################################
log_info "Project ID  : ${BLUE}${project_id}${NC}"
log_info "查询条目数  : ${BLUE}${#QUERY_LIST[@]}${NC}"
[ -n "$proxy" ] && log_info "Proxy       : ${BLUE}${proxy}${NC}"
echo ""

#######################################
# 提取嵌套字段值的函数
# $1: JSON 对象
# $2: 字段路径 (例如: env.region.abc)
#######################################
extract_field_value() {
    local json="$1"
    local field_path="$2"
    
    # 将点号分隔的路径转换为 jq 路径
    # 例如: env.region.abc -> .fields.env.mapValue.fields.region.mapValue.fields.abc
    local jq_path=""
    IFS='.' read -ra PATH_PARTS <<< "$field_path"
    
    for i in "${!PATH_PARTS[@]}"; do
        local part="${PATH_PARTS[$i]}"
        if [ $i -eq 0 ]; then
            jq_path=".fields.${part}"
        else
            jq_path="${jq_path}.mapValue.fields.${part}"
        fi
    done
    
    # 提取值并转换为可读格式
    local value=$(echo "$json" | jq -r "${jq_path} | 
        if .stringValue then .stringValue
        elif .integerValue then .integerValue
        elif .doubleValue then .doubleValue
        elif .booleanValue then .booleanValue
        elif .timestampValue then .timestampValue
        elif .arrayValue then .arrayValue
        elif .mapValue then .mapValue
        elif .nullValue then null
        else .
        end")
    
    echo "$value"
}

#######################################
# 主查询循环
#######################################
log_info "开始查询 Firestore 数据..."
echo ""

query_count=0
success_count=0
error_count=0

for query_config in "${QUERY_LIST[@]}"; do
    ((query_count++))
    
    # 解析配置: collection:document_id:field_path
    IFS=':' read -r collection document_id field_path <<< "$query_config"
    
    if [ -z "$collection" ] || [ -z "$document_id" ] || [ -z "$field_path" ]; then
        log_warn "配置格式错误，跳过: $query_config"
        ((error_count++))
        continue
    fi
    
    log_info "[$query_count/${#QUERY_LIST[@]}] 查询: ${YELLOW}${collection}/${document_id}${NC} -> ${CYAN}${field_path}${NC}"
    
    # 构建 Firestore API URL
    url="https://firestore.googleapis.com/v1/projects/${project_id}/databases/(default)/documents/${collection}/${document_id}"
    
    # 构建 curl 参数
    curl_args=(-s -H "Authorization: Bearer ${tk}")
    [ -n "$proxy" ] && curl_args+=(-x "$proxy")
    curl_args+=("$url")
    
    # 执行查询
    response=$(curl "${curl_args[@]}")
    
    # 检查 API 错误
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        error_msg=$(echo "$response" | jq -r '.error.message // .error')
        log_error "API 错误: $error_msg"
        ((error_count++))
        echo ""
        continue
    fi
    
    # 检查文档是否存在
    if ! echo "$response" | jq -e '.name' >/dev/null 2>&1; then
        log_warn "文档不存在或无数据"
        ((error_count++))
        echo ""
        continue
    fi
    
    # 提取字段值
    field_value=$(extract_field_value "$response" "$field_path")
    
    if [ "$field_value" = "null" ] || [ -z "$field_value" ]; then
        log_warn "字段 '${field_path}' 不存在或为空"
        ((error_count++))
    else
        log_result "字段值:"
        # 尝试格式化 JSON，如果失败则直接输出
        if echo "$field_value" | jq . >/dev/null 2>&1; then
            echo "$field_value" | jq .
        else
            echo "$field_value"
        fi
        ((success_count++))
    fi
    
    echo ""
done

#######################################
# 输出统计信息
#######################################
log_info "======================================"
log_info "查询完成"
log_info "总查询数: ${query_count}"
log_info "成功: ${GREEN}${success_count}${NC}"
log_info "失败/警告: ${RED}${error_count}${NC}"
log_info "======================================"
