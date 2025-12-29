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
