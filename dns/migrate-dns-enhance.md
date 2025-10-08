# GCP DNS 迁移脚本 - 增强版

## 完整脚本

```bash
#!/bin/bash

##############################################
# GCP DNS 记录迁移脚本 - 增强版
# 用途: 将 DNS 记录从源项目迁移到目标项目
# 新增: 干运行、一致性检查、创建命令提示、执行摘要
##############################################

set -o pipefail

# ============= 配置区域 =============
SOURCE_PROJECT="a-project"
TARGET_PROJECT="b-project"
ENV="prod"
REGION="us-central1"
BASE_DOMAIN="gcp.cloud.${REGION}.aibang"

# DNS Zone 配置
SOURCE_ZONE="${SOURCE_PROJECT}"
TARGET_ZONE="${TARGET_PROJECT}"

# DNS TTL 配置
DEFAULT_TTL=300

# 并发处理配置
MAX_PARALLEL=1

# 干运行模式（通过命令行参数控制）
DRY_RUN=false

# 日志文件
LOG_FILE="dns_migration_$(date +%Y%m%d_%H%M%S).log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 统计计数器
declare -g TOTAL_COUNT=0
declare -g SUCCESS_COUNT=0
declare -g SKIPPED_COUNT=0
declare -g FAILED_COUNT=0
declare -g NEED_CREATE_COUNT=0
declare -A SKIPPED_LIST
declare -A FAILED_LIST
declare -A SUCCESS_LIST
declare -A NEED_CREATE_LIST

# ============= 函数定义 =============

# 日志记录函数
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

log_success() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1"
    echo -e "${GREEN}${message}${NC}" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

log_warning() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1"
    echo -e "${YELLOW}${message}${NC}" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

log_error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1"
    echo -e "${RED}${message}${NC}" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

log_info() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ℹ $1"
    echo -e "${BLUE}${message}${NC}" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

log_skip() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ⊘ $1"
    echo -e "${CYAN}${message}${NC}" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

log_dry_run() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [DRY-RUN] $1"
    echo -e "${MAGENTA}${message}${NC}" | tee -a "$LOG_FILE" || echo "$message" >> "$LOG_FILE"
}

# 错误处理函数
error_exit() {
    log_error "$1"
    print_summary_report
    exit 1
}

# 检查必要的工具
check_requirements() {
    log "检查必要工具..."
    
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud 命令未找到，请安装 Google Cloud SDK"
    fi
    
    log_success "工具检查完成"
}

# 一次性验证所有前置条件
verify_prerequisites() {
    log "验证前置条件..."
    
    # 验证源项目
    if ! gcloud projects describe "${SOURCE_PROJECT}" &> /dev/null; then
        error_exit "无法访问源项目 ${SOURCE_PROJECT}"
    fi
    log "✓ 源项目验证通过: ${SOURCE_PROJECT}"
    
    # 验证目标项目
    if ! gcloud projects describe "${TARGET_PROJECT}" &> /dev/null; then
        error_exit "无法访问目标项目 ${TARGET_PROJECT}"
    fi
    log "✓ 目标项目验证通过: ${TARGET_PROJECT}"
    
    # 验证源 DNS Zone
    if ! gcloud dns managed-zones describe "${SOURCE_ZONE}" \
        --project="${SOURCE_PROJECT}" &> /dev/null; then
        error_exit "源 DNS Zone ${SOURCE_ZONE} 不存在"
    fi
    log "✓ 源 DNS Zone 验证通过: ${SOURCE_ZONE}"
    
    # 验证目标 DNS Zone
    if ! gcloud dns managed-zones describe "${TARGET_ZONE}" \
        --project="${TARGET_PROJECT}" &> /dev/null; then
        error_exit "目标 DNS Zone ${TARGET_ZONE} 不存在"
    fi
    log "✓ 目标 DNS Zone 验证通过: ${TARGET_ZONE}"
    
    log_success "所有前置条件验证通过"
}

# 获取记录的详细信息
get_record_details() {
    local project=$1
    local zone=$2
    local fqdn=$3
    
    local result
    result=$(gcloud dns record-sets list \
        --zone="${zone}" \
        --project="${project}" \
        --filter="name=${fqdn}" \
        --format="value(name,type,ttl,rrdatas[0])" 2>/dev/null)
    
    echo "$result"
}

# 快速验证目标记录存在
verify_target_record_exists() {
    local target_fqdn=$1
    
    local result
    result=$(gcloud dns record-sets list \
        --zone="${TARGET_ZONE}" \
        --project="${TARGET_PROJECT}" \
        --filter="name=${target_fqdn}" \
        --format="value(name)" 2>/dev/null)
    
    if echo "$result" | grep -q "${target_fqdn}"; then
        return 0
    fi
    
    return 1
}

# 生成创建目标记录的命令
generate_create_command() {
    local target_fqdn=$1
    local record_type=${2:-"A"}
    local target_value=${3:-"<IP_ADDRESS_OR_CNAME>"}
    
    cat << EOF

${YELLOW}========================================${NC}
${YELLOW}目标记录不存在，需要手动创建${NC}
${YELLOW}========================================${NC}

${CYAN}创建命令:${NC}

gcloud dns record-sets create "${target_fqdn}" \\
    --type=${record_type} \\
    --ttl=${DEFAULT_TTL} \\
    --rrdatas="${target_value}" \\
    --zone="${TARGET_ZONE}" \\
    --project="${TARGET_PROJECT}"

${YELLOW}========================================${NC}

EOF
}

# 检查源记录和目标记录是否一致
check_record_consistency() {
    local source_fqdn=$1
    local target_fqdn=$2
    
    # 获取源记录的当前指向
    local current_target
    current_target=$(gcloud dns record-sets describe "${source_fqdn}" \
        --zone="${SOURCE_ZONE}" \
        --project="${SOURCE_PROJECT}" \
        --format="value(rrdatas[0])" 2>/dev/null)
    
    if [ -z "$current_target" ]; then
        return 1  # 源记录不存在
    fi
    
    # 检查是否已经指向目标
    if [ "$current_target" = "$target_fqdn" ]; then
        return 0  # 一致
    fi
    
    return 2  # 不一致
}

# 直接更新 DNS 记录（核心函数）
update_dns_record_direct() {
    local api_name=$1
    local source_fqdn="${api_name}.${SOURCE_PROJECT}.${ENV}.${BASE_DOMAIN}."
    local target_fqdn="${api_name}.${TARGET_PROJECT}.${ENV}.${BASE_DOMAIN}."
    
    ((TOTAL_COUNT++)) || true
    
    log "=========================================="
    log "处理 [${TOTAL_COUNT}]: ${api_name}"
    log "  源记录: ${source_fqdn}"
    log "  目标记录: ${target_fqdn}"
    
    # 步骤1: 检查目标记录是否存在
    if ! verify_target_record_exists "${target_fqdn}"; then
        log_error "${api_name}: 目标记录不存在"
        
        # 获取源记录信息以生成创建命令
        local source_details
        source_details=$(get_record_details "${SOURCE_PROJECT}" "${SOURCE_ZONE}" "${source_fqdn}")
        
        if [ -n "$source_details" ]; then
            local source_type source_value
            source_type=$(echo "$source_details" | awk '{print $2}')
            source_value=$(echo "$source_details" | awk '{print $4}')
            
            log_info "源记录信息: 类型=${source_type}, 值=${source_value}"
            generate_create_command "${target_fqdn}" "${source_type}" "${source_value}"
        else
            generate_create_command "${target_fqdn}"
        fi
        
        ((NEED_CREATE_COUNT++)) || true
        NEED_CREATE_LIST["${api_name}"]="${target_fqdn}"
        return 1
    fi
    
    log "  ✓ 目标记录存在"
    
    # 步骤2: 检查一致性
    local consistency_result
    check_record_consistency "${source_fqdn}" "${target_fqdn}"
    consistency_result=$?
    
    if [ $consistency_result -eq 0 ]; then
        log_skip "${api_name}: 记录已经指向目标，无需更新"
        log "  当前指向: ${target_fqdn}"
        ((SKIPPED_COUNT++)) || true
        SKIPPED_LIST["${api_name}"]="Already pointing to target"
        return 0
    elif [ $consistency_result -eq 1 ]; then
        log_warning "${api_name}: 源记录不存在"
        
        if [ "$DRY_RUN" = true ]; then
            log_dry_run "将创建新的源记录指向目标"
            log_dry_run "命令: gcloud dns record-sets create \"${source_fqdn}\" --type=CNAME --ttl=${DEFAULT_TTL} --rrdatas=\"${target_fqdn}\" --zone=\"${SOURCE_ZONE}\" --project=\"${SOURCE_PROJECT}\""
            ((SUCCESS_COUNT++)) || true
            SUCCESS_LIST["${api_name}"]="[DRY-RUN] Would create"
            return 0
        fi
        
        # 实际创建
        local create_output
        if create_output=$(gcloud dns record-sets create "${source_fqdn}" \
            --type=CNAME \
            --ttl="${DEFAULT_TTL}" \
            --rrdatas="${target_fqdn}" \
            --zone="${SOURCE_ZONE}" \
            --project="${SOURCE_PROJECT}" 2>&1); then
            
            log_success "${api_name}: 创建源记录成功"
            echo "$create_output" >> "$LOG_FILE"
            ((SUCCESS_COUNT++)) || true
            SUCCESS_LIST["${api_name}"]="Created new record"
            return 0
        else
            log_error "${api_name}: 创建源记录失败"
            echo "$create_output" >> "$LOG_FILE"
            ((FAILED_COUNT++)) || true
            FAILED_LIST["${api_name}"]="Failed to create"
            return 1
        fi
    fi
    
    # 步骤3: 需要更新，获取当前值
    local current_target
    current_target=$(gcloud dns record-sets describe "${source_fqdn}" \
        --zone="${SOURCE_ZONE}" \
        --project="${SOURCE_PROJECT}" \
        --format="value(rrdatas[0])" 2>/dev/null)
    
    log "  当前指向: ${current_target}"
    log "  将更新为: ${target_fqdn}"
    
    # 干运行模式
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "将执行更新操作"
        log_dry_run "命令: gcloud dns record-sets update \"${source_fqdn}\" --type=CNAME --ttl=${DEFAULT_TTL} --rrdatas=\"${target_fqdn}\" --zone=\"${SOURCE_ZONE}\" --project=\"${SOURCE_PROJECT}\""
        ((SUCCESS_COUNT++)) || true
        SUCCESS_LIST["${api_name}"]="[DRY-RUN] Would update from ${current_target}"
        return 0
    fi
    
    # 步骤4: 实际更新
    local update_output
    if update_output=$(gcloud dns record-sets update "${source_fqdn}" \
        --type=CNAME \
        --ttl="${DEFAULT_TTL}" \
        --rrdatas="${target_fqdn}" \
        --zone="${SOURCE_ZONE}" \
        --project="${SOURCE_PROJECT}" 2>&1); then
        
        log_success "${api_name}: 更新成功"
        log "  ${current_target} → ${target_fqdn}"
        echo "$update_output" >> "$LOG_FILE"
        ((SUCCESS_COUNT++)) || true
        SUCCESS_LIST["${api_name}"]="Updated from ${current_target}"
        return 0
    else
        log_error "${api_name}: 更新失败"
        echo "$update_output" >> "$LOG_FILE"
        ((FAILED_COUNT++)) || true
        FAILED_LIST["${api_name}"]="Update failed"
        return 1
    fi
}

# 从文件读取 API 列表并处理
process_api_list_from_file() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        error_exit "API 列表文件不存在: ${file}"
    fi
    
    log "从文件读取 API 列表: ${file}"
    
    local api_list=()
    while IFS= read -r api_name || [ -n "$api_name" ]; do
        [[ -z "$api_name" || "$api_name" =~ ^# ]] && continue
        api_name=$(echo "$api_name" | xargs)
        api_list+=("$api_name")
    done < "$file"
    
    log "共发现 ${#api_list[@]} 个 API 待处理"
    
    if [ ${#api_list[@]} -eq 0 ]; then
        error_exit "文件中没有有效的 API 名称"
    fi
    
    process_api_list "${api_list[@]}"
}

# 处理 API 列表
process_api_list() {
    local api_list=("$@")
    
    if [ ${#api_list[@]} -eq 0 ]; then
        error_exit "未提供 API 名称"
    fi
    
    log "=========================================="
    log "开始处理 ${#api_list[@]} 个 API"
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "运行在干运行模式，不会执行实际操作"
    fi
    log "=========================================="
    
    for api_name in "${api_list[@]}"; do
        update_dns_record_direct "$api_name"
        echo ""  # 空行分隔
    done
}

# 打印执行摘要报告
print_summary_report() {
    local report_file="dns_migration_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat << EOF | tee "$report_file"

${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}
${GREEN}║                    DNS 迁移执行摘要报告                        ║${NC}
${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}

${CYAN}【基本信息】${NC}
  执行时间: $(date +'%Y-%m-%d %H:%M:%S')
  源项目:   ${SOURCE_PROJECT}
  目标项目: ${TARGET_PROJECT}
  环境:     ${ENV}
  运行模式: $([ "$DRY_RUN" = true ] && echo "干运行模式（DRY-RUN）" || echo "实际执行模式")

${CYAN}【统计数据】${NC}
  总计:     ${TOTAL_COUNT} 个 API
  ${GREEN}成功:     ${SUCCESS_COUNT} 个${NC}
  ${CYAN}跳过:     ${SKIPPED_COUNT} 个${NC}
  ${RED}失败:     ${FAILED_COUNT} 个${NC}
  ${YELLOW}需创建:   ${NEED_CREATE_COUNT} 个${NC}

${CYAN}【详细信息】${NC}

EOF

    # 成功列表
    if [ ${SUCCESS_COUNT} -gt 0 ]; then
        echo -e "${GREEN}✓ 成功更新的 API (${SUCCESS_COUNT}):${NC}" | tee -a "$report_file"
        for api in "${!SUCCESS_LIST[@]}"; do
            echo "  - ${api}: ${SUCCESS_LIST[$api]}" | tee -a "$report_file"
        done
        echo "" | tee -a "$report_file"
    fi
    
    # 跳过列表
    if [ ${SKIPPED_COUNT} -gt 0 ]; then
        echo -e "${CYAN}⊘ 跳过的 API (${SKIPPED_COUNT}):${NC}" | tee -a "$report_file"
        for api in "${!SKIPPED_LIST[@]}"; do
            echo "  - ${api}: ${SKIPPED_LIST[$api]}" | tee -a "$report_file"
        done
        echo "" | tee -a "$report_file"
    fi
    
    # 失败列表
    if [ ${FAILED_COUNT} -gt 0 ]; then
        echo -e "${RED}✗ 失败的 API (${FAILED_COUNT}):${NC}" | tee -a "$report_file"
        for api in "${!FAILED_LIST[@]}"; do
            echo "  - ${api}: ${FAILED_LIST[$api]}" | tee -a "$report_file"
        done
        echo "" | tee -a "$report_file"
    fi
    
    # 需要创建的列表
    if [ ${NEED_CREATE_COUNT} -gt 0 ]; then
        echo -e "${YELLOW}⚠ 需要创建目标记录的 API (${NEED_CREATE_COUNT}):${NC}" | tee -a "$report_file"
        for api in "${!NEED_CREATE_LIST[@]}"; do
            echo "  - ${api}: ${NEED_CREATE_LIST[$api]}" | tee -a "$report_file"
        done
        echo "" | tee -a "$report_file"
        
        # 生成批量创建脚本
        local batch_create_script="create_missing_records.sh"
        echo "#!/bin/bash" > "$batch_create_script"
        echo "# 批量创建缺失的目标记录" >> "$batch_create_script"
        echo "" >> "$batch_create_script"
        for api in "${!NEED_CREATE_LIST[@]}"; do
            local target_fqdn="${NEED_CREATE_LIST[$api]}"
            echo "# ${api}" >> "$batch_create_script"
            echo "gcloud dns record-sets create \"${target_fqdn}\" \\" >> "$batch_create_script"
            echo "    --type=CNAME \\" >> "$batch_create_script"
            echo "    --ttl=${DEFAULT_TTL} \\" >> "$batch_create_script"
            echo "    --rrdatas=\"<TARGET_VALUE>\" \\" >> "$batch_create_script"
            echo "    --zone=\"${TARGET_ZONE}\" \\" >> "$batch_create_script"
            echo "    --project=\"${TARGET_PROJECT}\"" >> "$batch_create_script"
            echo "" >> "$batch_create_script"
        done
        chmod +x "$batch_create_script"
        
        echo -e "${YELLOW}已生成批量创建脚本: ${batch_create_script}${NC}" | tee -a "$report_file"
        echo "" | tee -a "$report_file"
    fi
    
    cat << EOF | tee -a "$report_file"
${CYAN}【文件输出】${NC}
  详细日志: ${LOG_FILE}
  摘要报告: ${report_file}
$([ ${NEED_CREATE_COUNT} -gt 0 ] && echo "  创建脚本: create_missing_records.sh")

${GREEN}════════════════════════════════════════════════════════════════${NC}

EOF

    if [ "$DRY_RUN" = true ]; then
        echo -e "${MAGENTA}【提示】当前为干运行模式，没有执行实际操作。${NC}"
        echo -e "${MAGENTA}      如需实际执行，请移除 --dry-run 参数重新运行。${NC}"
        echo ""
    fi
}

# ============= 主函数 =============

main() {
    # 解析命令行参数
    local args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--file)
                args+=("$1" "$2")
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    log "=========================================="
    log "GCP DNS 迁移脚本启动（增强版）"
    log "源项目: ${SOURCE_PROJECT}"
    log "目标项目: ${TARGET_PROJECT}"
    log "环境: ${ENV}"
    log "TTL: ${DEFAULT_TTL}s"
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "运行模式: 干运行（DRY-RUN）"
    else
        log "运行模式: 实际执行"
    fi
    log "=========================================="
    
    # 预检查
    check_requirements
    verify_prerequisites
    
    # 根据参数决定处理方式
    if [ "${args[0]}" = "-f" ] || [ "${args[0]}" = "--file" ]; then
        if [ -z "${args[1]}" ]; then
            error_exit "请提供 API 列表文件路径"
        fi
        process_api_list_from_file "${args[1]}"
    elif [ ${#args[@]} -gt 0 ]; then
        process_api_list "${args[@]}"
    else
        error_exit "请提供 API 名称或使用 -f 参数指定文件"
    fi
    
    # 打印摘要报告
    print_summary_report
    
    log_success "脚本执行完成"
}

# 显示帮助信息
show_help() {
    cat << EOF
${GREEN}GCP DNS 迁移脚本 - 增强版${NC}

${CYAN}使用方法:${NC}
  $0 [选项] <api-name1> [api-name2 ...]
  $0 [选项] -f <file>

${CYAN}选项:${NC}
  --dry-run              干运行模式，只显示将要执行的操作，不实际执行
  -f, --file <file>      从文件读取 API 列表
  -h, --help             显示帮助信息

${CYAN}示例:${NC}
  # 干运行模式，查看将要执行的操作
  $0 --dry-run user-service order-service

  # 实际执行迁移
  $0 user-service order-service

  # 从文件读取并干运行
  $0 --dry-run -f api_list.txt

  # 从文件读取并实际执行
  $0 -f api_list.txt

${CYAN}新增特性:${NC}
  ${GREEN}✓${NC} 干运行模式: 预览操作而不实际执行
  ${GREEN}✓${NC} 一致性检查: 自动跳过已正确配置的记录
  ${GREEN}✓${NC} 创建命令提示: 为缺失的目标记录生成创建命令
  ${GREEN}✓${NC} 执行摘要报告: 详细的操作结果统计和分类

${CYAN}配置说明:${NC}
  请在脚本顶部 '配置区域' 修改以下参数:
  - SOURCE_PROJECT: 源项目 ID
  - TARGET_PROJECT: 目标项目 ID
  - ENV: 环境名称
  - REGION: 区域名称
  - DEFAULT_TTL: DNS TTL 值（默认 300）
  - MAX_PARALLEL: 最大并发数（默认 1）

${CYAN}输出文件:${NC}
  - dns_migration_YYYYMMDD_HHMMSS.log        详细执行日志
  - dns_migration_report_YYYYMMDD_HHMMSS.txt 执行摘要报告
  - create_missing_records.sh                批量创建缺失记录的脚本
EOF
}

# ============= 脚本入口 =============

# 执行主函数
main "$@"
```

## 使用示例

### 1. 干运行模式（推荐先使用）

```bash
# 单个 API 干运行
./dns_migration.sh --dry-run pop-test

# 多个 API 干运行
./dns_migration.sh --dry-run user-service order-service payment-service

# 从文件读取并干运行
./dns_migration.sh --dry-run -f api_list.txt
```

### 2. 实际执行

```bash
# 确认干运行结果无误后，实际执行
./dns_migration.sh pop-test

# 批量执行
./dns_migration.sh -f api_list.txt
```

## 输出示例

### 干运行模式输出

```
==========================================
处理 [1]: pop-test
  源记录: pop-test.a-project.prod.gcp.cloud.us-central1.aibang.
  目标记录: pop-test.b-project.prod.gcp.cloud.us-central1.aibang.
  ✓ 目标记录存在
  当前指向: old-target.example.com.
  将更新为: pop-test.b-project.prod.gcp.cloud.us-central1.aibang.
[DRY-RUN] 将执行更新操作
[DRY-RUN] 命令: gcloud dns record-sets update "pop-test.a-project.prod..." --type=CNAME --ttl=300 --rrdatas="pop-test.b-project.prod..." --zone="a-project" --project="a-project"
```

### 一致性跳过输出

```
==========================================
处理 [2]: already-migrated-api
  源记录: already-migrated-api.a-project.prod.gcp.cloud.us-central1.aibang.
  目标记录: already-migrated-api.b-project.prod.gcp.cloud.us-central1.aibang.
  ✓ 目标记录存在
⊘ already-migrated-api: 记录已经指向目标，无需更新
  当前指向: already-migrated-api.b-project.prod.gcp.cloud.us-central1.aibang.
```

### 目标记录不存在输出

```
==========================================
处理 [3]: missing-target-api
  源记录: missing-target-api.a-project.prod.gcp.cloud.us-central1.aibang.
  目标记录: missing-target-api.b-project.prod.gcp.cloud.us-central1.aibang.
✗ missing-target-api: 目标记录不存在

========================================
目标记录不存在，需要手动创建
========================================

创建命令:

gcloud dns record-sets create "missing-target-api.b-project.prod.gcp.cloud.us-central1.aibang." \
    --type=CNAME \
    --ttl=300 \
    --rrdatas="some-service.example.com." \
    --zone="b-project" \
    --project="b-project"

========================================
```

### 执行摘要报告

```
╔════════════════════════════════════════════════════════════════╗
║                    DNS 迁移执行摘要报告                        ║
╚════════════════════════════════════════════════════════════════╝

【基本信息】
  执行时间: 2024-10-08 15:30:45
  源项目:   a-project
  目标项目: b-project
  环境:     prod
  运行模式: 实际执行模式

【统计数据】
  总计:     5 个 API
  成功:     3 个
  跳过:     1 个
  失败:     0 个
  需创建:   1 个

【详细信息】

✓ 成功更新的 API (3):
  - pop-test: Updated from old-target.example.com.
  - user-service: Updated from legacy.example.com.
  - order-service: Created new record

⊘ 跳过的 API (1):
  - already-mig​​​​​​​​​​​​​​​​
```