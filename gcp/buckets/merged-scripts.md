# Shell Scripts Collection

Generated on: 2025-12-30 11:15:33
Directory: /Users/lex/git/knowledge/gcp/buckets

## `add-bucket-binding.sh`

```bash
#!/bin/bash

################################################################################
# GCS Bucket IAM 绑定添加脚本
# 用法: ./add-bucket-binding.sh -p <project-id> -b <bucket-name> -s <service-account> [-r <role>]
# 示例: ./add-bucket-binding.sh -p my-project -b gs://my-bucket -s sa@project.iam.gserviceaccount.com
################################################################################

set -euo pipefail

# ============================================================================ 
# 颜色定义
# ============================================================================ 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================ 
# 默认配置
# ============================================================================ 
DEFAULT_ROLE="roles/storage.legacyBucketReader"

# ============================================================================ 
# 辅助函数
# ============================================================================ 
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

usage() {
    cat << EOF
用法: $0 -p <project-id> -b <bucket-name> -s <service-account> [-r <role>]

参数:
    -p    GCP 项目 ID (必需)
    -b    Bucket 名称 (必需, e.g., gs://my-bucket)
    -s    Service Account 邮箱 (必需)
    -r    IAM 角色 (可选, 默认: ${DEFAULT_ROLE})
    -h    显示此帮助信息

示例:
    $0 -p aibang-projectid-wwww-dev -b gs://abjx-env-region-gkecofigs -s mysa@other-project.iam.gserviceaccount.com
EOF
    exit 1
}

# ============================================================================ 
# 参数解析
# ============================================================================ 
PROJECT_ID=""
BUCKET_NAME=""
SERVICE_ACCOUNT=""
ROLE="${DEFAULT_ROLE}"

while getopts "p:b:s:r:h" opt; do
    case ${opt} in
        p) PROJECT_ID="${OPTARG}" ;; 
        b) BUCKET_NAME="${OPTARG}" ;; 
        s) SERVICE_ACCOUNT="${OPTARG}" ;; 
        r) ROLE="${OPTARG}" ;; 
        h) usage ;; 
        \?) print_error "无效的参数: -${OPTARG}"; usage ;; 
        :) print_error "参数 -${OPTARG} 需要一个值"; usage ;; 
    esac
done

# 检查必需参数
if [[ -z "${PROJECT_ID}" || -z "${BUCKET_NAME}" || -z "${SERVICE_ACCOUNT}" ]]; then
    print_error "缺少必需参数"
    usage
fi

# 规范化 Bucket 名称 (确保有 gs:// 前缀)
if [[ ! "${BUCKET_NAME}" =~ ^gs:// ]]; then
    BUCKET_NAME="gs://${BUCKET_NAME}"
fi

# 规范化 Service Account (添加 member 前缀)
MEMBER="serviceAccount:${SERVICE_ACCOUNT}"

# ============================================================================ 
# 主逻辑
# ============================================================================ 
print_section "GCS IAM 绑定添加工具"
echo "项目:          ${PROJECT_ID}"
echo "Bucket:        ${BUCKET_NAME}"
echo "成员 (Member): ${MEMBER}"
echo "角色 (Role):   ${ROLE}"

# 1. 检查 Bucket 是否存在
print_section "检查 Bucket 状态"
if ! gcloud storage buckets describe "${BUCKET_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
    print_error "Bucket ${BUCKET_NAME} 不存在或无权访问 (项目: ${PROJECT_ID})"
    exit 1
fi
print_success "Bucket 存在"

# 2. 显示当前策略 (满足用户 'get policy' 的需求)
print_section "当前 IAM 策略 (部分)"
# 只显示相关角色的绑定，避免输出过多
print_info "正在获取当前策略..."
CURRENT_BINDING=$(gcloud storage buckets get-iam-policy "${BUCKET_NAME}" --project="${PROJECT_ID}" --format="json" | grep -A 5 "${ROLE}" || echo "未找到该角色的绑定")
echo "${CURRENT_BINDING}"

# 3. 添加绑定
print_section "添加 IAM 绑定"
print_info "正在执行: gcloud storage buckets add-iam-policy-binding ${BUCKET_NAME} --member=${MEMBER} --role=${ROLE}"

if gcloud storage buckets add-iam-policy-binding "${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --member="${MEMBER}" \
    --role="${ROLE}" > /dev/null; then
    
    print_success "绑定添加成功！"
else
    print_error "绑定添加失败"
    exit 1
fi

# 4. 验证更改
print_section "验证更改"
print_info "重新获取策略以验证..."
NEW_POLICY=$(gcloud storage buckets get-iam-policy "${BUCKET_NAME}" --project="${PROJECT_ID}" --format="json(bindings)")

# 简单检查 (使用 grep 检查输出中是否包含 member 和 role)
# 注意: JSON 输出格式化后，grep 可能需要多行匹配，这里简化处理，直接显示结果
# 更严谨的检查需要 jq，但不假设环境中有 jq
if echo "${NEW_POLICY}" | grep -q "${SERVICE_ACCOUNT}"; then
    if echo "${NEW_POLICY}" | grep -q "${ROLE}"; then
        print_success "验证通过: 策略中包含目标 Service Account 和角色"
    else
        print_warning "验证: 找到了 Service Account，但未在上下文中确认角色 (请人工核对)"
    fi
else
    print_error "验证失败: 策略中未找到该 Service Account"
fi

print_info "完整策略检查命令: gcloud storage buckets get-iam-policy ${BUCKET_NAME} --project=${PROJECT_ID}"

exit 0

```

## `create-buckets.sh`

```bash
#!/bin/bash

################################################################################
# GCS Bucket 批量创建脚本
# 用法: ./create-buckets.sh -p <project-id> [-c <config-file>]
# 示例: ./create-buckets.sh -p aibang-projectid-wwww-dev -c buckets-config.txt
################################################################################

set -euo pipefail

# ============================================================================
# 默认配置定义
# ============================================================================
DEFAULT_KMS_PROJECT="abjx-id-kms-dev"
DEFAULT_REGION="europe-west2"
DEFAULT_BUCKET_NAME="cap-lex-eg-gkeconfigs"
DEFAULT_STORAGE_CLASS="STANDARD"

# KMS 密钥配置
KMS_KEY_RING="cloudStorage"
KMS_KEY_NAME="cloudStorage"

# Autoclass 配置
AUTOCLASS_ENABLED="true"
AUTOCLASS_TERMINAL_CLASS="ARCHIVE"

# Soft Delete 配置（7天 = 604800秒）
SOFT_DELETE_RETENTION="604800s"

# 标签配置
LABEL_ENFORCER_AUTOCLASS="enabled"

# ============================================================================
# 颜色定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# 辅助函数
# ============================================================================
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

usage() {
    cat << EOF
用法: $0 -p <project-id> [-c <config-file>]

参数:
    -p    GCP 项目 ID (必需)
    -c    配置文件路径 (可选，默认使用内置配置)
    -h    显示此帮助信息

示例:
    # 使用内置默认配置创建单个 bucket
    $0 -p aibang-projectid-wwww-dev

    # 使用配置文件批量创建多个 bucket
    $0 -p aibang-projectid-wwww-dev -c buckets-config.txt

配置文件格式:
    每行一个配置，格式如下：
    kms-project == <kms-project> region == <region> project == <project> buckets = <bucket1> <bucket2> ...

    示例配置行：
    kms-project == abjx-id-kms-dev region == europe-west2 project == aibang-projectid-wwww-dev buckets = gs://cap-lex-eg-gkeconfigs gs://cap-lex-eg-gkeconfigs2
    kms-project == abjx-id-kms-dev region == us-central1 project == aibang-projectid-wwww-dev buckets = gs://cap-dev-us-backup

    注意：
    - 只会处理 project 字段与 -p 参数匹配的配置行
    - buckets 字段可以包含多个 bucket 名称（空格分隔）
    - bucket 名称可以带或不带 gs:// 前缀

内置默认配置:
    KMS Project:        ${DEFAULT_KMS_PROJECT}
    Region:             ${DEFAULT_REGION}
    Bucket Name:        gs://${DEFAULT_BUCKET_NAME}
    Storage Class:      ${DEFAULT_STORAGE_CLASS}
    Autoclass:          ${AUTOCLASS_ENABLED} (Terminal: ${AUTOCLASS_TERMINAL_CLASS})
    Soft Delete:        ${SOFT_DELETE_RETENTION}
EOF
    exit 1
}

# ============================================================================
# 解析配置行
# ============================================================================
parse_config_line() {
    local config_line="$1"
    local target_project="$2"
    
    # 提取参数
    local kms_proj=""
    local region=""
    local proj=""
    local buckets=()
    
    # 解析 kms-project
    if [[ "$config_line" =~ kms-project[[:space:]]*==[[:space:]]*([^[:space:]]+) ]]; then
        kms_proj="${BASH_REMATCH[1]}"
    fi
    
    # 解析 region
    if [[ "$config_line" =~ region[[:space:]]*==[[:space:]]*([^[:space:]]+) ]]; then
        region="${BASH_REMATCH[1]}"
    fi
    
    # 解析 project
    if [[ "$config_line" =~ project[[:space:]]*==[[:space:]]*([^[:space:]]+) ]]; then
        proj="${BASH_REMATCH[1]}"
    fi
    
    # 解析 buckets (支持多个 bucket)
    if [[ "$config_line" =~ buckets[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        local buckets_str="${BASH_REMATCH[1]}"
        # 分割 bucket 列表
        read -ra buckets <<< "$buckets_str"
    fi
    
    # 检查项目是否匹配
    if [[ "$proj" != "$target_project" ]]; then
        return 1
    fi
    
    # 验证必需字段
    if [[ -z "$kms_proj" || -z "$region" || -z "$proj" || ${#buckets[@]} -eq 0 ]]; then
        print_error "配置行缺少必需字段: $config_line"
        return 1
    fi
    
    # 导出解析结果
    echo "${kms_proj}|${region}|${proj}|${buckets[*]}"
    return 0
}

# ============================================================================
# 创建单个 bucket
# ============================================================================
create_bucket() {
    local bucket_name="$1"
    local project_id="$2"
    local region="$3"
    local kms_project="$4"
    
    # 构建 KMS 密钥路径
    local kms_key_path="projects/${kms_project}/locations/${region}/keyRings/${KMS_KEY_RING}/cryptoKeys/${KMS_KEY_NAME}"
    
    # 移除 gs:// 前缀（如果存在）
    bucket_name="${bucket_name#gs://}"
    
    print_section "处理 Bucket: gs://${bucket_name}"
    
    # 检查 bucket 是否已存在
    if gcloud storage buckets describe "gs://${bucket_name}" --project="${project_id}" &>/dev/null; then
        print_warning "Bucket gs://${bucket_name} 已存在于项目 ${project_id}"
        print_info "显示当前配置..."
        echo ""
        gcloud storage buckets describe "gs://${bucket_name}" --project="${project_id}" --format=json
        echo ""
        return 2  # 返回 2 表示已存在
    fi
    
    print_info "创建 bucket: gs://${bucket_name}"
    print_info "  项目: ${project_id}"
    print_info "  区域: ${region}"
    print_info "  KMS 密钥: ${kms_key_path}"
    print_info "  存储类别: ${DEFAULT_STORAGE_CLASS}"
    print_info "  Autoclass: 启用 (终端: ${AUTOCLASS_TERMINAL_CLASS})"
    print_info "  Soft Delete: ${SOFT_DELETE_RETENTION}"
    
    # 创建 bucket
    if ! gcloud storage buckets create "gs://${bucket_name}" \
        --project="${project_id}" \
        --location="${region}" \
        --default-storage-class="${DEFAULT_STORAGE_CLASS}" \
        --uniform-bucket-level-access \
        --enable-autoclass \
        --autoclass-terminal-storage-class="${AUTOCLASS_TERMINAL_CLASS}" \
        --soft-delete-duration="${SOFT_DELETE_RETENTION}" \
        --default-encryption-key="${kms_key_path}" 2>&1; then
        print_error "创建 bucket 失败: gs://${bucket_name}"
        return 1
    fi
    
    print_success "Bucket 创建成功！"
    
    # 添加标签
    print_info "添加标签: enforcer_autoclass=${LABEL_ENFORCER_AUTOCLASS}"
    if ! gcloud storage buckets update "gs://${bucket_name}" \
        --project="${project_id}" \
        --update-labels="enforcer_autoclass=${LABEL_ENFORCER_AUTOCLASS}" 2>&1; then
        print_warning "添加标签失败，但 bucket 已创建"
    else
        print_success "标签配置完成！"
    fi
    
    # 显示详细信息
    print_info "Bucket 详细信息:"
    echo ""
    gcloud storage buckets describe "gs://${bucket_name}" --project="${project_id}" --format=json
    echo ""
    
    return 0
}

# ============================================================================
# 参数解析
# ============================================================================
PROJECT_ID=""
CONFIG_FILE=""

while getopts "p:c:h" opt; do
    case ${opt} in
        p)
            PROJECT_ID="${OPTARG}"
            ;;
        c)
            CONFIG_FILE="${OPTARG}"
            ;;
        h)
            usage
            ;;
        \?)
            print_error "无效的参数: -${OPTARG}"
            usage
            ;;
        :)
            print_error "参数 -${OPTARG} 需要一个值"
            usage
            ;;
    esac
done

# 检查必需参数
if [[ -z "${PROJECT_ID}" ]]; then
    print_error "缺少必需参数: -p <project-id>"
    usage
fi

# ============================================================================
# 主逻辑
# ============================================================================
print_section "GCS Bucket 批量创建工具"
echo "目标项目: ${PROJECT_ID}"
if [[ -n "${CONFIG_FILE}" ]]; then
    echo "配置文件: ${CONFIG_FILE}"
else
    echo "配置模式: 使用内置默认配置"
fi

# 统计变量
TOTAL_BUCKETS=0
CREATED_BUCKETS=0
EXISTING_BUCKETS=0
FAILED_BUCKETS=0

# 处理配置
if [[ -n "${CONFIG_FILE}" ]]; then
    # 从配置文件读取
    print_section "读取配置文件"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        print_error "配置文件不存在: ${CONFIG_FILE}"
        exit 1
    fi
    
    line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        print_info "解析配置行 ${line_num}: ${line}"
        
        # 解析配置行
        if config_result=$(parse_config_line "$line" "$PROJECT_ID" 2>&1); then
            IFS='|' read -r kms_proj region proj buckets_str <<< "$config_result"
            
            print_success "找到匹配配置:"
            echo "  KMS Project: ${kms_proj}"
            echo "  Region: ${region}"
            echo "  Project: ${proj}"
            echo "  Buckets: ${buckets_str}"
            
            # 创建每个 bucket
            for bucket in $buckets_str; do
                ((TOTAL_BUCKETS++))
                
                if create_bucket "$bucket" "$proj" "$region" "$kms_proj"; then
                    ((CREATED_BUCKETS++))
                elif [[ $? -eq 2 ]]; then
                    ((EXISTING_BUCKETS++))
                else
                    ((FAILED_BUCKETS++))
                fi
            done
        else
            print_warning "配置行 ${line_num} 不匹配项目 ${PROJECT_ID}，跳过"
        fi
    done < "$CONFIG_FILE"
    
    if [[ ${TOTAL_BUCKETS} -eq 0 ]]; then
        print_warning "配置文件中没有找到匹配项目 ${PROJECT_ID} 的配置"
        exit 0
    fi
else
    # 使用内置默认配置
    print_section "使用内置默认配置"
    
    ((TOTAL_BUCKETS++))
    if create_bucket "$DEFAULT_BUCKET_NAME" "$PROJECT_ID" "$DEFAULT_REGION" "$DEFAULT_KMS_PROJECT"; then
        ((CREATED_BUCKETS++))
    elif [[ $? -eq 2 ]]; then
        ((EXISTING_BUCKETS++))
    else
        ((FAILED_BUCKETS++))
    fi
fi

# ============================================================================
# 总结
# ============================================================================
print_section "执行总结"
cat << EOF
总 Bucket 数:    ${TOTAL_BUCKETS}
新创建:          ${CREATED_BUCKETS}
已存在:          ${EXISTING_BUCKETS}
失败:            ${FAILED_BUCKETS}
EOF

if [[ ${FAILED_BUCKETS} -eq 0 ]]; then
    print_success "所有 Bucket 处理完成！"
    exit 0
else
    print_warning "部分 Bucket 处理失败，请检查上述错误信息"
    exit 1
fi

```

## `verify-buckets-iam.sh`

```bash
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

```

## `verify-buckets.sh`

```bash
#!/bin/bash

################################################################################
# GCS Bucket 验证脚本
# 用法: ./verify-buckets.sh -b <bucket-name>
# 示例: ./verify-buckets.sh -b gs://my-bucket-name
################################################################################

set -euo pipefail

# ============================================================================
# 颜色定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ============================================================================
# 辅助函数
# ============================================================================
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_subsection() {
    echo ""
    echo -e "${MAGENTA}▶ $1${NC}"
    echo -e "${MAGENTA}────────────────────────────────────────────────────────────${NC}"
}

usage() {
    cat << EOF
用法: $0 -b <bucket-name> [-p <project-id>]

参数:
    -b    Bucket 名称 (必需，可带或不带 gs:// 前缀)
    -p    GCP 项目 ID (可选，如果未指定则使用当前活动项目)
    -h    显示此帮助信息

示例:
    # 使用当前活动项目
    $0 -b gs://my-bucket-name

    # 指定项目
    $0 -b my-bucket-name -p aibang-projectid-wwww-dev

    # 不带 gs:// 前缀
    $0 -b my-bucket-name

显示信息:
    - Bucket 基本信息
    - IAM Policy (访问控制策略)
    - Lifecycle (生命周期规则)
    - Versioning (版本控制)
    - CORS (跨域资源共享)
    - Labels (标签)
    - Encryption (加密配置)
    - Logging (日志配置)
EOF
    exit 1
}

# ============================================================================
# 参数解析
# ============================================================================
BUCKET_NAME=""
PROJECT_ID=""

while getopts "b:p:h" opt; do
    case ${opt} in
        b)
            BUCKET_NAME="${OPTARG}"
            ;;
        p)
            PROJECT_ID="${OPTARG}"
            ;;
        h)
            usage
            ;;
        \?)
            print_error "无效的参数: -${OPTARG}"
            usage
            ;;
        :)
            print_error "参数 -${OPTARG} 需要一个值"
            usage
            ;;
    esac
done

# 检查必需参数
if [[ -z "${BUCKET_NAME}" ]]; then
    print_error "缺少必需参数: -b <bucket-name>"
    usage
fi

# 移除 gs:// 前缀（如果存在）
BUCKET_NAME="${BUCKET_NAME#gs://}"

# 构建 gcloud 命令的项目参数
PROJECT_FLAG=""
if [[ -n "${PROJECT_ID}" ]]; then
    PROJECT_FLAG="--project=${PROJECT_ID}"
fi

# ============================================================================
# 主逻辑
# ============================================================================
print_section "GCS Bucket 验证工具"
echo "Bucket 名称: gs://${BUCKET_NAME}"
if [[ -n "${PROJECT_ID}" ]]; then
    echo "项目 ID: ${PROJECT_ID}"
else
    echo "项目 ID: (使用当前活动项目)"
fi

# 检查 bucket 是否存在
print_section "检查 Bucket 是否存在"
if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} &>/dev/null; then
    print_error "Bucket gs://${BUCKET_NAME} 不存在或无权限访问"
    exit 1
fi
print_success "Bucket 存在且可访问"

# ============================================================================
# 1. Bucket 基本信息
# ============================================================================
print_section "1. Bucket 基本信息"
print_info "获取 bucket 详细配置..."
echo ""

gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="table(
    name,
    location,
    locationType,
    storageClass,
    timeCreated.date('%Y-%m-%d %H:%M:%S'),
    updated.date('%Y-%m-%d %H:%M:%S')
)"

echo ""
print_subsection "存储统计"
gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="value(
    metageneration,
    satisfiesPZS
)" | while read -r metageneration pzs; do
    echo "Metageneration: ${metageneration}"
    echo "Satisfies PZS: ${pzs}"
done

# ============================================================================
# 2. IAM Policy (访问控制策略)
# ============================================================================
print_section "2. IAM Policy (访问控制策略)"
print_info "获取 IAM 策略..."
echo ""

if iam_policy=$(gcloud storage buckets get-iam-policy "gs://${BUCKET_NAME}" ${PROJECT_FLAG} 2>&1); then
    echo "$iam_policy"
else
    print_warning "无法获取 IAM 策略: $iam_policy"
fi

# ============================================================================
# 3. Lifecycle (生命周期规则)
# ============================================================================
print_section "3. Lifecycle (生命周期规则)"
print_info "获取生命周期配置..."
echo ""

lifecycle=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(lifecycle)")

if echo "$lifecycle" | jq -e '.lifecycle.rule' &>/dev/null; then
    echo "$lifecycle" | jq -r '.lifecycle.rule[] | 
        "规则 \(.action.type):",
        "  条件:",
        (if .condition.age then "    - Age: \(.condition.age) 天" else "" end),
        (if .condition.createdBefore then "    - Created Before: \(.condition.createdBefore)" else "" end),
        (if .condition.matchesStorageClass then "    - Storage Class: \(.condition.matchesStorageClass | join(", "))" else "" end),
        (if .condition.numNewerVersions then "    - Newer Versions: \(.condition.numNewerVersions)" else "" end),
        "  动作: \(.action.type)",
        (if .action.storageClass then "    - Target Class: \(.action.storageClass)" else "" end),
        ""'
else
    print_info "未配置生命周期规则"
fi

# ============================================================================
# 4. Versioning (版本控制)
# ============================================================================
print_section "4. Versioning (版本控制)"
print_info "获取版本控制状态..."
echo ""

versioning=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="value(versioning.enabled)")

if [[ "$versioning" == "True" ]]; then
    print_success "版本控制: 已启用"
else
    print_info "版本控制: 未启用"
fi

# ============================================================================
# 5. CORS (跨域资源共享)
# ============================================================================
print_section "5. CORS (跨域资源共享)"
print_info "获取 CORS 配置..."
echo ""

cors=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(cors)")

if echo "$cors" | jq -e '.cors' &>/dev/null; then
    echo "$cors" | jq -r '.cors[] | 
        "CORS 规则:",
        "  Origin: \(.origin | join(", "))",
        "  Method: \(.method | join(", "))",
        (if .responseHeader then "  Response Headers: \(.responseHeader | join(", "))" else "" end),
        (if .maxAgeSeconds then "  Max Age: \(.maxAgeSeconds) 秒" else "" end),
        ""'
else
    print_info "未配置 CORS 规则"
fi

# ============================================================================
# 6. Labels (标签)
# ============================================================================
print_section "6. Labels (标签)"
print_info "获取标签..."
echo ""

labels=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(labels)")

if echo "$labels" | jq -e '.labels' &>/dev/null; then
    echo "$labels" | jq -r '.labels | to_entries[] | "  \(.key): \(.value)"'
else
    print_info "未配置标签"
fi

# ============================================================================
# 7. Encryption (加密配置)
# ============================================================================
print_section "7. Encryption (加密配置)"
print_info "获取加密配置..."
echo ""

encryption=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(default_kms_key,defaultEventBasedHold)")

default_kms=$(echo "$encryption" | jq -r '.default_kms_key // "未配置 CMEK"')
event_hold=$(echo "$encryption" | jq -r '.defaultEventBasedHold // false')

echo "默认 KMS 密钥: ${default_kms}"
echo "Event-Based Hold: ${event_hold}"

# ============================================================================
# 8. Autoclass (自动存储类别)
# ============================================================================
print_section "8. Autoclass (自动存储类别)"
print_info "获取 Autoclass 配置..."
echo ""

autoclass=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(autoclass)")

if echo "$autoclass" | jq -e '.autoclass.enabled' &>/dev/null; then
    enabled=$(echo "$autoclass" | jq -r '.autoclass.enabled')
    terminal_class=$(echo "$autoclass" | jq -r '.autoclass.terminalStorageClass // "未设置"')
    toggle_time=$(echo "$autoclass" | jq -r '.autoclass.toggleTime // "未知"')
    
    if [[ "$enabled" == "true" ]]; then
        print_success "Autoclass: 已启用"
        echo "  终端存储类别: ${terminal_class}"
        echo "  启用时间: ${toggle_time}"
    else
        print_info "Autoclass: 未启用"
    fi
else
    print_info "Autoclass: 未配置"
fi

# ============================================================================
# 9. Soft Delete Policy (软删除策略)
# ============================================================================
print_section "9. Soft Delete Policy (软删除策略)"
print_info "获取软删除策略..."
echo ""

soft_delete=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(softDeletePolicy)")

if echo "$soft_delete" | jq -e '.softDeletePolicy' &>/dev/null; then
    retention=$(echo "$soft_delete" | jq -r '.softDeletePolicy.retentionDurationSeconds')
    effective_time=$(echo "$soft_delete" | jq -r '.softDeletePolicy.effectiveTime')
    
    retention_days=$((retention / 86400))
    echo "保留时长: ${retention} 秒 (${retention_days} 天)"
    echo "生效时间: ${effective_time}"
else
    print_info "未配置软删除策略"
fi

# ============================================================================
# 10. Logging (日志配置)
# ============================================================================
print_section "10. Logging (日志配置)"
print_info "获取日志配置..."
echo ""

logging=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(logging)")

if echo "$logging" | jq -e '.logging' &>/dev/null; then
    log_bucket=$(echo "$logging" | jq -r '.logging.logBucket')
    log_prefix=$(echo "$logging" | jq -r '.logging.logObjectPrefix // "无前缀"')
    
    echo "日志 Bucket: ${log_bucket}"
    echo "日志前缀: ${log_prefix}"
else
    print_info "未配置访问日志"
fi

# ============================================================================
# 11. Public Access Prevention (公共访问防护)
# ============================================================================
print_section "11. Public Access Prevention (公共访问防护)"
print_info "获取公共访问防护状态..."
echo ""

pap=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="value(iamConfiguration.publicAccessPrevention)")

case "$pap" in
    "enforced")
        print_success "公共访问防护: 已强制执行"
        ;;
    "inherited")
        print_info "公共访问防护: 继承自组织策略"
        ;;
    *)
        print_warning "公共访问防护: ${pap}"
        ;;
esac

# ============================================================================
# 12. Uniform Bucket-Level Access (统一桶级访问)
# ============================================================================
print_section "12. Uniform Bucket-Level Access (统一桶级访问)"
print_info "获取统一桶级访问状态..."
echo ""

ubla=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(iamConfiguration.uniformBucketLevelAccess)")

if echo "$ubla" | jq -e '.iamConfiguration.uniformBucketLevelAccess.enabled' &>/dev/null; then
    enabled=$(echo "$ubla" | jq -r '.iamConfiguration.uniformBucketLevelAccess.enabled')
    locked_time=$(echo "$ubla" | jq -r '.iamConfiguration.uniformBucketLevelAccess.lockedTime // "未锁定"')
    
    if [[ "$enabled" == "true" ]]; then
        print_success "统一桶级访问: 已启用"
        echo "  锁定时间: ${locked_time}"
    else
        print_info "统一桶级访问: 未启用"
    fi
fi

# ============================================================================
# 总结
# ============================================================================
print_section "验证完成"
print_success "Bucket gs://${BUCKET_NAME} 的所有配置信息已显示"

```

