#!/bin/bash

################################################################################
# GCS Bucket IAM 绑定验证脚本 (纯 Shell + jq 版本)
# 用途: 验证 Bucket 所有 IAM 绑定并识别跨项目账户
################################################################################

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# 显示使用说明
usage() {
    cat << EOF
使用方法: $0 [选项]

选项:
    -b, --bucket BUCKET_NAME        GCS Bucket 名称 (必需)
    -p, --project PROJECT_ID        Bucket 所在项目 ID (可选，用于识别跨项目账户)
    -o, --output FORMAT             输出格式: text|json|csv (默认: text)
    -f, --filter PERMISSION         过滤特定权限: read|write|admin|all (默认: all)
    -v, --verbose                   详细输出模式
    -h, --help                      显示此帮助信息

示例:
    # 基本使用
    $0 -b gs://ab-env-region-api

    # 指定项目 ID 以识别跨项目账户
    $0 -b gs://ab-env-region-api -p my-project-id

    # 只显示有写入权限的账户
    $0 -b gs://ab-env-region-api -f write

    # 输出为 JSON 格式
    $0 -b gs://ab-env-region-api -o json

    # 输出为 CSV 格式
    $0 -b gs://ab-env-region-api -o csv > iam-report.csv
EOF
    exit 1
}

# 参数解析
BUCKET=""
PROJECT_ID=""
OUTPUT_FORMAT="text"
PERMISSION_FILTER="all"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bucket)
            BUCKET="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -f|--filter)
            PERMISSION_FILTER="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "未知参数: $1"
            usage
            ;;
    esac
done

# 验证必需参数
if [[ -z "$BUCKET" ]]; then
    log_error "缺少必需参数: -b/--bucket"
    usage
fi

# 检查 jq 是否安装
if ! command -v jq &> /dev/null; then
    log_error "此脚本需要 jq 工具，请先安装: brew install jq 或 apt-get install jq"
    exit 1
fi

# 处理 bucket 名称
BUCKET="${BUCKET#gs://}"
BUCKET="${BUCKET#gsutil://}"

# 获取当前项目
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -n "$PROJECT_ID" ]]; then
        log_info "使用当前项目 ID: $PROJECT_ID"
    else
        log_warn "未指定项目 ID，将无法准确识别跨项目账户"
    fi
fi

# 临时文件
TEMP_IAM_FILE=$(mktemp)
trap "rm -f $TEMP_IAM_FILE" EXIT

# 权限分类函数
get_permission_category() {
    local role="$1"
    case "$role" in
        "roles/storage.objectViewer"|"roles/storage.legacyBucketReader"|"roles/storage.legacyObjectReader")
            echo "read"
            ;;
        "roles/storage.objectCreator"|"roles/storage.legacyBucketWriter"|"roles/storage.objectUser")
            echo "write"
            ;;
        "roles/storage.objectAdmin"|"roles/storage.legacyBucketOwner"|"roles/storage.admin")
            echo "admin"
            ;;
        *)
            echo "other"
            ;;
    esac
}

# 权限说明函数
get_permission_description() {
    local role="$1"
    case "$role" in
        "roles/storage.objectViewer") echo "对象查看 (只读)" ;;
        "roles/storage.legacyBucketReader") echo "Bucket 读取" ;;
        "roles/storage.legacyObjectReader") echo "对象读取 (遗留)" ;;
        "roles/storage.objectCreator") echo "对象创建" ;;
        "roles/storage.legacyBucketWriter") echo "Bucket 写入" ;;
        "roles/storage.objectUser") echo "对象读写" ;;
        "roles/storage.objectAdmin") echo "对象管理员" ;;
        "roles/storage.legacyBucketOwner") echo "Bucket 所有者" ;;
        "roles/storage.admin") echo "存储管理员" ;;
        *) echo "$role" ;;
    esac
}

# 账户类型函数
get_account_type() {
    local member="$1"
    case "$member" in
        user:*) echo "用户账户" ;;
        serviceAccount:*) 
            local sa_email="${member#serviceAccount:}"
            if [[ "$sa_email" =~ @([^.]+)\. ]]; then
                local account_project="${BASH_REMATCH[1]}"
                if [[ -n "$PROJECT_ID" ]] && [[ "$account_project" != "$PROJECT_ID" ]]; then
                    echo "Service Account (跨项目: $account_project)"
                else
                    echo "Service Account (本项目)"
                fi
            else
                echo "Service Account"
            fi
            ;;
        group:*) echo "群组" ;;
        domain:*) echo "域" ;;
        allUsers) echo "所有用户 (公开)" ;;
        allAuthenticatedUsers) echo "所有认证用户" ;;
        *) echo "其他" ;;
    esac
}

# 检查 bucket 是否存在
check_bucket() {
    log_info "检查 Bucket: gs://$BUCKET"
    
    if ! gcloud storage buckets describe "gs://$BUCKET" &>/dev/null; then
        log_error "Bucket 不存在或无访问权限: gs://$BUCKET"
        exit 1
    fi
    
    log_info "✓ Bucket 存在"
}

# 获取 IAM 策略
get_iam_policy() {
    log_info "获取 IAM 策略..."
    
    if ! gcloud storage buckets get-iam-policy "gs://$BUCKET" --format=json > "$TEMP_IAM_FILE" 2>/dev/null; then
        log_error "无法获取 IAM 策略"
        exit 1
    fi
    
    log_info "✓ IAM 策略已获取"
}

# 解析 IAM 策略 (使用 jq)
parse_iam_policy() {
    jq -r --arg project_id "$PROJECT_ID" --arg filter "$PERMISSION_FILTER" '
        .bindings[] | 
        .role as $role | 
        .members[] | 
        . as $member |
        
        # 判断权限类别
        (if ($role | test("objectViewer|legacyBucketReader|legacyObjectReader")) then "read"
         elif ($role | test("objectCreator|legacyBucketWriter|objectUser")) then "write"
         elif ($role | test("objectAdmin|legacyBucketOwner|storage.admin")) then "admin"
         else "other" end) as $category |
        
        # 过滤权限
        if ($filter != "all" and $category != $filter) then empty
        else
            # 提取项目 ID (如果是 Service Account)
            (if ($member | startswith("serviceAccount:")) then
                ($member | sub("serviceAccount:"; "") | split("@")[1] | split(".")[0])
             else "" end) as $member_project |
            
            # 判断是否跨项目
            (if ($member_project != "" and $project_id != "" and $member_project != $project_id) then "true"
             else "false" end) as $is_cross |
            
            # 输出格式: member|role|category|is_cross|member_project
            "\($member)|\($role)|\($category)|\($is_cross)|\($member_project)"
        end
    ' "$TEMP_IAM_FILE"
}

# 文本格式输出
output_text() {
    log_section "Bucket IAM 绑定分析报告"
    
    echo -e "${BLUE}Bucket:${NC} gs://$BUCKET"
    if [[ -n "$PROJECT_ID" ]]; then
        echo -e "${BLUE}项目 ID:${NC} $PROJECT_ID"
    fi
    echo -e "${BLUE}分析时间:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 统计信息
    local all_bindings=$(parse_iam_policy)
    local total_bindings=$(echo "$all_bindings" | wc -l | tr -d ' ')
    local cross_project_count=$(echo "$all_bindings" | grep -c "|true|" || echo "0")
    local read_count=$(echo "$all_bindings" | grep -c "|read|" || echo "0")
    local write_count=$(echo "$all_bindings" | grep -c "|write|" || echo "0")
    local admin_count=$(echo "$all_bindings" | grep -c "|admin|" || echo "0")
    
    # 确保变量是数字
    total_bindings=${total_bindings:-0}
    cross_project_count=${cross_project_count:-0}
    read_count=${read_count:-0}
    write_count=${write_count:-0}
    admin_count=${admin_count:-0}
    
    log_section "统计摘要"
    echo -e "${GREEN}总绑定数:${NC} $total_bindings"
    echo -e "${YELLOW}跨项目账户:${NC} $cross_project_count"
    echo -e "${CYAN}读取权限:${NC} $read_count"
    echo -e "${CYAN}写入权限:${NC} $write_count"
    echo -e "${MAGENTA}管理权限:${NC} $admin_count"
    
    # 按权限类别分组显示
    log_section "详细权限清单"
    
    # 读取权限
    if [[ "$PERMISSION_FILTER" == "all" ]] || [[ "$PERMISSION_FILTER" == "read" ]]; then
        if [[ ${read_count} -gt 0 ]]; then
            echo -e "\n${CYAN}【读取权限】${NC}"
            echo "$all_bindings" | grep "|read|" | while IFS='|' read -r member role category is_cross member_project; do
                local account_type=$(get_account_type "$member")
                local perm_desc=$(get_permission_description "$role")
                
                if [[ "$is_cross" == "true" ]]; then
                    echo -e "  ${YELLOW}[跨项目]${NC} $member"
                    echo -e "    └─ 类型: $account_type"
                    echo -e "    └─ 角色: $perm_desc"
                    echo -e "    └─ 来源项目: $member_project"
                else
                    echo -e "  $member"
                    echo -e "    └─ 类型: $account_type"
                    echo -e "    └─ 角色: $perm_desc"
                fi
                echo ""
            done
        fi
    fi
    
    # 写入权限
    if [[ "$PERMISSION_FILTER" == "all" ]] || [[ "$PERMISSION_FILTER" == "write" ]]; then
        if [[ ${write_count} -gt 0 ]]; then
            echo -e "\n${GREEN}【写入权限】${NC}"
            echo "$all_bindings" | grep "|write|" | while IFS='|' read -r member role category is_cross member_project; do
                local account_type=$(get_account_type "$member")
                local perm_desc=$(get_permission_description "$role")
                
                if [[ "$is_cross" == "true" ]]; then
                    echo -e "  ${YELLOW}[跨项目]${NC} $member"
                    echo -e "    └─ 类型: $account_type"
                    echo -e "    └─ 角色: $perm_desc"
                    echo -e "    └─ 来源项目: $member_project"
                else
                    echo -e "  $member"
                    echo -e "    └─ 类型: $account_type"
                    echo -e "    └─ 角色: $perm_desc"
                fi
                echo ""
            done
        fi
    fi
    
    # 管理权限
    if [[ "$PERMISSION_FILTER" == "all" ]] || [[ "$PERMISSION_FILTER" == "admin" ]]; then
        if [[ ${admin_count} -gt 0 ]]; then
            echo -e "\n${MAGENTA}【管理权限】${NC}"
            echo "$all_bindings" | grep "|admin|" | while IFS='|' read -r member role category is_cross member_project; do
                local account_type=$(get_account_type "$member")
                local perm_desc=$(get_permission_description "$role")
                
                if [[ "$is_cross" == "true" ]]; then
                    echo -e "  ${YELLOW}[跨项目]${NC} $member"
                    echo -e "    └─ 类型: $account_type"
                    echo -e "    └─ 角色: $perm_desc"
                    echo -e "    └─ 来源项目: $member_project"
                else
                    echo -e "  $member"
                    echo -e "    └─ 类型: $account_type"
                    echo -e "    └─ 角色: $perm_desc"
                fi
                echo ""
            done
        fi
    fi
    
    # 跨项目账户汇总
    if [[ ${cross_project_count} -gt 0 ]]; then
        log_section "跨项目账户汇总"
        echo "$all_bindings" | grep "|true|" | while IFS='|' read -r member role category is_cross member_project; do
            local perm_desc=$(get_permission_description "$role")
            echo -e "  ${YELLOW}$member${NC}"
            echo -e "    └─ 来源项目: $member_project"
            echo -e "    └─ 权限类型: $category"
            echo -e "    └─ 角色: $perm_desc"
            echo ""
        done
    fi
}

# JSON 格式输出
output_json() {
    jq -n --arg bucket "gs://$BUCKET" \
          --arg project "$PROJECT_ID" \
          --arg scan_time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
          --argjson bindings "$(parse_iam_policy | while IFS='|' read -r member role category is_cross member_project; do
              local account_type=$(get_account_type "$member")
              local perm_desc=$(get_permission_description "$role")
              
              jq -n --arg member "$member" \
                    --arg role "$role" \
                    --arg category "$category" \
                    --arg perm_desc "$perm_desc" \
                    --arg account_type "$account_type" \
                    --argjson is_cross "$(if [[ "$is_cross" == "true" ]]; then echo "true"; else echo "false"; fi)" \
                    --arg member_project "$member_project" \
                    '{member: $member, role: $role, permission_category: $category, permission_description: $perm_desc, account_type: $account_type, is_cross_project: $is_cross, source_project: $member_project}'
          done | jq -s '.')" \
          '{bucket: $bucket, project_id: $project, scan_time: $scan_time, bindings: $bindings}'
}

# CSV 格式输出
output_csv() {
    echo "Member,Role,Permission Category,Permission Description,Account Type,Is Cross Project,Source Project"
    
    parse_iam_policy | while IFS='|' read -r member role category is_cross member_project; do
        local account_type=$(get_account_type "$member")
        local perm_desc=$(get_permission_description "$role")
        
        echo "\"$member\",\"$role\",\"$category\",\"$perm_desc\",\"$account_type\",\"$is_cross\",\"$member_project\""
    done
}

# 主流程
main() {
    # 执行检查
    check_bucket
    get_iam_policy
    
    # 根据输出格式输出结果
    case "$OUTPUT_FORMAT" in
        text)
            output_text
            ;;
        json)
            output_json
            ;;
        csv)
            output_csv
            ;;
        *)
            log_error "不支持的输出格式: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# 执行主流程
main
