# Shell Scripts Collection

Generated on: 2025-12-29 17:10:57
Directory: /Users/lex/git/knowledge/gcp/buckets

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

encryption=$(gcloud storage buckets describe "gs://${BUCKET_NAME}" ${PROJECT_FLAG} --format="json(encryption,defaultEventBasedHold)")

default_kms=$(echo "$encryption" | jq -r '.encryption.defaultKmsKeyName // "未配置 CMEK"')
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

