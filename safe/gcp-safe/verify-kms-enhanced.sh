#!/bin/bash

################################################################################
# GCP KMS 跨项目权限校验脚本 (增强版)
# 用途: 验证 KMS 跨项目加解密架构的完整性和权限配置
# 版本: 2.0.0
# 改进: 更健壮的错误处理、更准确的 IAM 解析、支持 JSON 输出
################################################################################

set -euo pipefail

# ============================================================================
# 颜色配置
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# 全局变量
# ============================================================================
SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="kms-validation-report-${TIMESTAMP}.md"
JSON_REPORT_FILE="kms-validation-report-${TIMESTAMP}.json"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
TEST_FILE_PREFIX="kms-test-${TIMESTAMP}"
TEMP_DIR="/tmp/kms-validator-$$"

# 检查结果数组
declare -a CHECK_RESULTS=()

# ============================================================================
# 工具函数
# ============================================================================

# 初始化临时目录
init_temp_dir() {
    mkdir -p "$TEMP_DIR"
    trap cleanup_temp_dir EXIT
}

# 清理临时目录
cleanup_temp_dir() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# 记录检查结果
record_check() {
    local status="$1"
    local message="$2"
    local detail="${3:-}"
    
    CHECK_RESULTS+=("{\"status\":\"$status\",\"message\":\"$message\",\"detail\":\"$detail\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}")
}

# 打印信息
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

# 打印成功
log_success() {
    echo -e "${GREEN}[✓]${NC} $1" >&2
    ((PASSED_CHECKS++))
    record_check "success" "$1"
}

# 打印警告
log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" >&2
    ((WARNING_CHECKS++))
    record_check "warning" "$1"
}

# 打印错误
log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
    ((FAILED_CHECKS++))
    record_check "error" "$1"
}

# 打印分隔线
print_separator() {
    echo "========================================================================" >&2
}

# 检查命令是否存在
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "必需命令未找到: $cmd"
        exit 1
    fi
}

# 使用说明
usage() {
    cat << EOF
使用方法: $SCRIPT_NAME [选项]

必需参数:
  --kms-project PROJECT_ID          KMS 项目 ID
  --business-project PROJECT_ID     业务项目 ID
  --keyring NAME                    Keyring 名称
  --key NAME                        CryptoKey 名称
  --location LOCATION               密钥位置 (如: global, us-central1)
  --service-accounts ACCOUNTS       服务账号列表 (逗号分隔)

可选参数:
  --test-encrypt                    执行加密功能测试
  --test-decrypt                    执行解密功能测试
  --output-format FORMAT            输出格式: text|json|markdown (默认: text)
  --skip-rotation-check             跳过密钥轮换策略检查
  --verbose                         详细输出模式
  --help                            显示此帮助信息

示例:
  $SCRIPT_NAME \\
    --kms-project aibang-project-id-kms-env \\
    --business-project aibang-1234567-ajx01-env \\
    --keyring aibang-1234567-ajx01-env \\
    --key env01-uk-core-ajx \\
    --location global \\
    --service-accounts "sa1@project.iam.gserviceaccount.com,sa2@project.iam.gserviceaccount.com" \\
    --test-encrypt --test-decrypt

EOF
    exit 1
}

# ============================================================================
# 参数解析
# ============================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --kms-project)
                KMS_PROJECT="$2"
                shift 2
                ;;
            --business-project)
                BUSINESS_PROJECT="$2"
                shift 2
                ;;
            --keyring)
                KEYRING="$2"
                shift 2
                ;;
            --key)
                CRYPTO_KEY="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --service-accounts)
                SERVICE_ACCOUNTS="$2"
                shift 2
                ;;
            --test-encrypt)
                TEST_ENCRYPT=true
                shift
                ;;
            --test-decrypt)
                TEST_DECRYPT=true
                shift
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --skip-rotation-check)
                SKIP_ROTATION_CHECK=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                echo "未知参数: $1" >&2
                usage
                ;;
        esac
    done

    # 验证必需参数
    local missing_params=()
    [[ -z "${KMS_PROJECT:-}" ]] && missing_params+=("--kms-project")
    [[ -z "${BUSINESS_PROJECT:-}" ]] && missing_params+=("--business-project")
    [[ -z "${KEYRING:-}" ]] && missing_params+=("--keyring")
    [[ -z "${CRYPTO_KEY:-}" ]] && missing_params+=("--key")
    [[ -z "${LOCATION:-}" ]] && missing_params+=("--location")
    [[ -z "${SERVICE_ACCOUNTS:-}" ]] && missing_params+=("--service-accounts")
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        echo -e "${RED}错误: 缺少必需参数: ${missing_params[*]}${NC}" >&2
        usage
    fi

    # 设置默认值
    TEST_ENCRYPT=${TEST_ENCRYPT:-false}
    TEST_DECRYPT=${TEST_DECRYPT:-false}
    OUTPUT_FORMAT=${OUTPUT_FORMAT:-text}
    SKIP_ROTATION_CHECK=${SKIP_ROTATION_CHECK:-false}
    VERBOSE=${VERBOSE:-false}
}

# ============================================================================
# 验证模块
# ============================================================================

# 1. 验证前置条件
check_prerequisites() {
    print_separator
    log_info "检查前置条件..."
    ((TOTAL_CHECKS++))
    
    check_command "gcloud"
    check_command "jq"
    
    # 验证 gcloud 已认证
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "gcloud 未认证，请先运行: gcloud auth login"
        exit 1
    fi
    
    log_success "前置条件检查通过 (gcloud, jq)"
}

# 2. 验证 KMS 项目访问权限
check_kms_project() {
    print_separator
    log_info "验证 KMS 项目: $KMS_PROJECT"
    ((TOTAL_CHECKS++))
    
    local project_info
    if project_info=$(gcloud projects describe "$KMS_PROJECT" --format=json 2>&1); then
        local project_state
        project_state=$(echo "$project_info" | jq -r '.lifecycleState // "UNKNOWN"')
        
        if [[ "$project_state" == "ACTIVE" ]]; then
            log_success "KMS 项目可访问且状态为 ACTIVE"
        else
            log_warning "KMS 项目状态为: $project_state"
        fi
    else
        log_error "无法访问 KMS 项目: $KMS_PROJECT"
        [[ "$VERBOSE" == true ]] && echo "$project_info" >&2
        exit 1
    fi
}

# 3. 验证业务项目访问权限
check_business_project() {
    print_separator
    log_info "验证业务项目: $BUSINESS_PROJECT"
    ((TOTAL_CHECKS++))
    
    local project_info
    if project_info=$(gcloud projects describe "$BUSINESS_PROJECT" --format=json 2>&1); then
        local project_state
        project_state=$(echo "$project_info" | jq -r '.lifecycleState // "UNKNOWN"')
        
        if [[ "$project_state" == "ACTIVE" ]]; then
            log_success "业务项目可访问且状态为 ACTIVE"
        else
            log_warning "业务项目状态为: $project_state"
        fi
    else
        log_error "无法访问业务项目: $BUSINESS_PROJECT"
        [[ "$VERBOSE" == true ]] && echo "$project_info" >&2
        exit 1
    fi
}

# 4. 验证 Keyring 存在性
check_keyring() {
    print_separator
    log_info "验证 Keyring: $KEYRING (位置: $LOCATION)"
    ((TOTAL_CHECKS++))
    
    local keyring_info
    if keyring_info=$(gcloud kms keyrings describe "$KEYRING" \
        --project="$KMS_PROJECT" \
        --location="$LOCATION" \
        --format=json 2>&1); then
        
        local keyring_name
        keyring_name=$(echo "$keyring_info" | jq -r '.name // "unknown"')
        log_success "Keyring 存在: $keyring_name"
    else
        log_error "Keyring 不存在: $KEYRING"
        [[ "$VERBOSE" == true ]] && echo "$keyring_info" >&2
        exit 1
    fi
}

# 5. 验证 CryptoKey 存在性
check_crypto_key() {
    print_separator
    log_info "验证 CryptoKey: $CRYPTO_KEY"
    ((TOTAL_CHECKS++))
    
    local key_info
    if key_info=$(gcloud kms keys describe "$CRYPTO_KEY" \
        --project="$KMS_PROJECT" \
        --keyring="$KEYRING" \
        --location="$LOCATION" \
        --format=json 2>&1); then
        
        local key_purpose
        key_purpose=$(echo "$key_info" | jq -r '.purpose // "unknown"')
        local key_state
        key_state=$(echo "$key_info" | jq -r '.primary.state // "unknown"')
        
        log_success "CryptoKey 存在 (用途: $key_purpose, 状态: $key_state)"
        
        # 保存密钥信息供后续使用
        echo "$key_info" > "$TEMP_DIR/key_info.json"
    else
        log_error "CryptoKey 不存在: $CRYPTO_KEY"
        [[ "$VERBOSE" == true ]] && echo "$key_info" >&2
        exit 1
    fi
}

# 6. 获取并分析 IAM 策略
check_iam_policy() {
    print_separator
    log_info "获取密钥 IAM 策略..."
    
    local iam_policy
    if iam_policy=$(gcloud kms keys get-iam-policy "$CRYPTO_KEY" \
        --project="$KMS_PROJECT" \
        --keyring="$KEYRING" \
        --location="$LOCATION" \
        --format=json 2>&1); then
        
        echo "$iam_policy" > "$TEMP_DIR/iam_policy.json"
        
        local bindings_count
        bindings_count=$(echo "$iam_policy" | jq '.bindings | length // 0')
        log_success "IAM 策略获取成功 (包含 $bindings_count 个角色绑定)"
    else
        log_error "无法获取 IAM 策略"
        [[ "$VERBOSE" == true ]] && echo "$iam_policy" >&2
        return 1
    fi
}

# 7. 验证服务账号权限 (改进版 - 使用 jq 解析)
check_service_account_permissions() {
    print_separator
    log_info "验证服务账号权限..."
    
    if [[ ! -f "$TEMP_DIR/iam_policy.json" ]]; then
        log_error "IAM 策略文件不存在，跳过权限检查"
        return 1
    fi
    
    # 解析 IAM 策略，提取加密和解密权限
    local encrypters
    local decrypters
    
    encrypters=$(jq -r '.bindings[] | select(.role == "roles/cloudkms.cryptoKeyEncrypter") | .members[]' "$TEMP_DIR/iam_policy.json" 2>/dev/null | grep "serviceAccount:" | sed 's/serviceAccount://' || echo "")
    decrypters=$(jq -r '.bindings[] | select(.role == "roles/cloudkms.cryptoKeyDecrypter") | .members[]' "$TEMP_DIR/iam_policy.json" 2>/dev/null | grep "serviceAccount:" | sed 's/serviceAccount://' || echo "")
    
    # 保存到临时文件
    echo "$encrypters" > "$TEMP_DIR/encrypters.txt"
    echo "$decrypters" > "$TEMP_DIR/decrypters.txt"
    
    # 检查每个服务账号
    IFS=',' read -ra SA_ARRAY <<< "$SERVICE_ACCOUNTS"
    
    for sa in "${SA_ARRAY[@]}"; do
        sa=$(echo "$sa" | xargs)  # 去除空格
        ((TOTAL_CHECKS++))
        
        local has_encrypt=false
        local has_decrypt=false
        
        if echo "$encrypters" | grep -qF "$sa"; then
            has_encrypt=true
        fi
        
        if echo "$decrypters" | grep -qF "$sa"; then
            has_decrypt=true
        fi
        
        if [[ "$has_encrypt" == true && "$has_decrypt" == true ]]; then
            log_warning "服务账号同时拥有加密和解密权限 (不符合最小权限原则): $sa"
        elif [[ "$has_encrypt" == true ]]; then
            log_success "服务账号拥有加密权限: $sa"
        elif [[ "$has_decrypt" == true ]]; then
            log_success "服务账号拥有解密权限: $sa"
        else
            log_error "服务账号没有任何 KMS 权限: $sa"
        fi
    done
    
    # 检查是否有未预期的服务账号
    log_info "检查未授权的服务账号..."
    local all_sa
    all_sa=$(cat "$TEMP_DIR/encrypters.txt" "$TEMP_DIR/decrypters.txt" | sort -u)
    
    while IFS= read -r sa; do
        [[ -z "$sa" ]] && continue
        
        local is_expected=false
        for expected_sa in "${SA_ARRAY[@]}"; do
            expected_sa=$(echo "$expected_sa" | xargs)
            if [[ "$sa" == "$expected_sa" ]]; then
                is_expected=true
                break
            fi
        done
        
        if [[ "$is_expected" == false ]]; then
            log_warning "发现未在检查列表中的服务账号: $sa"
        fi
    done <<< "$all_sa"
}

# 8. 验证密钥轮换策略
check_rotation_policy() {
    if [[ "$SKIP_ROTATION_CHECK" == true ]]; then
        log_info "跳过密钥轮换策略检查 (--skip-rotation-check)"
        return 0
    fi
    
    print_separator
    log_info "检查密钥轮换策略..."
    ((TOTAL_CHECKS++))
    
    if [[ ! -f "$TEMP_DIR/key_info.json" ]]; then
        log_warning "密钥信息文件不存在，跳过轮换策略检查"
        return 0
    fi
    
    local rotation_period
    local next_rotation_time
    
    rotation_period=$(jq -r '.rotationPeriod // "null"' "$TEMP_DIR/key_info.json")
    next_rotation_time=$(jq -r '.nextRotationTime // "null"' "$TEMP_DIR/key_info.json")
    
    if [[ "$rotation_period" != "null" && "$rotation_period" != "" ]]; then
        log_success "密钥轮换策略已配置: $rotation_period"
        
        if [[ "$next_rotation_time" != "null" && "$next_rotation_time" != "" ]]; then
            log_info "下次轮换时间: $next_rotation_time"
        fi
    else
        log_warning "未配置密钥轮换策略 (建议配置自动轮换以提高安全性)"
    fi
}

# 9. 执行加密功能测试
test_encryption() {
    if [[ "$TEST_ENCRYPT" != true ]]; then
        return 0
    fi
    
    print_separator
    log_info "执行加密功能测试..."
    ((TOTAL_CHECKS++))
    
    local plaintext_file="$TEMP_DIR/plaintext.txt"
    local ciphertext_file="$TEMP_DIR/ciphertext.enc"
    
    # 创建测试文件
    echo "KMS Encryption Test - Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$plaintext_file"
    
    # 尝试加密
    local encrypt_output
    if encrypt_output=$(gcloud kms encrypt \
        --project="$KMS_PROJECT" \
        --location="$LOCATION" \
        --keyring="$KEYRING" \
        --key="$CRYPTO_KEY" \
        --plaintext-file="$plaintext_file" \
        --ciphertext-file="$ciphertext_file" 2>&1); then
        
        if [[ -f "$ciphertext_file" && -s "$ciphertext_file" ]]; then
            local cipher_size
            cipher_size=$(wc -c < "$ciphertext_file")
            log_success "加密测试通过 (密文大小: $cipher_size bytes)"
            
            # 保存加密文件用于解密测试
            cp "$ciphertext_file" "$TEMP_DIR/test_cipher.enc"
        else
            log_error "加密测试失败: 密文文件为空或不存在"
        fi
    else
        log_error "加密测试失败"
        [[ "$VERBOSE" == true ]] && echo "$encrypt_output" >&2
    fi
}

# 10. 执行解密功能测试
test_decryption() {
    if [[ "$TEST_DECRYPT" != true ]]; then
        return 0
    fi
    
    print_separator
    log_info "执行解密功能测试..."
    ((TOTAL_CHECKS++))
    
    local ciphertext_file="$TEMP_DIR/test_cipher.enc"
    local decrypted_file="$TEMP_DIR/decrypted.txt"
    
    if [[ ! -f "$ciphertext_file" ]]; then
        log_warning "跳过解密测试: 未找到加密测试文件 (需先执行 --test-encrypt)"
        return 0
    fi
    
    # 尝试解密
    local decrypt_output
    if decrypt_output=$(gcloud kms decrypt \
        --project="$KMS_PROJECT" \
        --location="$LOCATION" \
        --keyring="$KEYRING" \
        --key="$CRYPTO_KEY" \
        --ciphertext-file="$ciphertext_file" \
        --plaintext-file="$decrypted_file" 2>&1); then
        
        if [[ -f "$decrypted_file" ]]; then
            # 验证内容
            if grep -q "KMS Encryption Test" "$decrypted_file"; then
                log_success "解密测试通过 (内容验证成功)"
            else
                log_error "解密测试失败: 解密内容与原文不匹配"
                [[ "$VERBOSE" == true ]] && cat "$decrypted_file" >&2
            fi
        else
            log_error "解密测试失败: 解密文件不存在"
        fi
    else
        log_error "解密测试失败"
        [[ "$VERBOSE" == true ]] && echo "$decrypt_output" >&2
    fi
}

# ============================================================================
# 报告生成
# ============================================================================

# 生成 Markdown 报告
generate_markdown_report() {
    cat > "$REPORT_FILE" << EOF
# GCP KMS 权限校验报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')  
**KMS 项目**: \`$KMS_PROJECT\`  
**业务项目**: \`$BUSINESS_PROJECT\`  
**Keyring**: \`$KEYRING\`  
**CryptoKey**: \`$CRYPTO_KEY\`  
**位置**: \`$LOCATION\`  

---

## 📊 检查统计

| 项目 | 数量 |
|------|------|
| 总检查项 | $TOTAL_CHECKS |
| ✅ 通过 | $PASSED_CHECKS |
| ⚠️ 警告 | $WARNING_CHECKS |
| ❌ 失败 | $FAILED_CHECKS |

**整体状态**: $(if [[ $FAILED_CHECKS -eq 0 ]]; then echo "✅ 通过"; else echo "❌ 失败"; fi)

---

## 🔍 详细结果

### 资源验证
EOF

    # 添加资源验证结果
    if [[ -f "$TEMP_DIR/key_info.json" ]]; then
        local key_purpose
        local key_state
        key_purpose=$(jq -r '.purpose // "unknown"' "$TEMP_DIR/key_info.json")
        key_state=$(jq -r '.primary.state // "unknown"' "$TEMP_DIR/key_info.json")
        
        cat >> "$REPORT_FILE" << EOF
- ✅ KMS 项目可访问
- ✅ 业务项目可访问
- ✅ Keyring 存在
- ✅ CryptoKey 存在 (用途: $key_purpose, 状态: $key_state)
EOF
    fi

    cat >> "$REPORT_FILE" << EOF

### 权限配置

#### 加密权限 (roles/cloudkms.cryptoKeyEncrypter)
EOF

    if [[ -f "$TEMP_DIR/encrypters.txt" ]]; then
        while IFS= read -r sa; do
            [[ -z "$sa" ]] && continue
            echo "- \`$sa\`" >> "$REPORT_FILE"
        done < "$TEMP_DIR/encrypters.txt"
    fi

    cat >> "$REPORT_FILE" << EOF

#### 解密权限 (roles/cloudkms.cryptoKeyDecrypter)
EOF

    if [[ -f "$TEMP_DIR/decrypters.txt" ]]; then
        while IFS= read -r sa; do
            [[ -z "$sa" ]] && continue
            echo "- \`$sa\`" >> "$REPORT_FILE"
        done < "$TEMP_DIR/decrypters.txt"
    fi

    cat >> "$REPORT_FILE" << EOF

### 查看完整 IAM 策略

\`\`\`bash
gcloud kms keys get-iam-policy $CRYPTO_KEY \\
  --project=$KMS_PROJECT \\
  --keyring=$KEYRING \\
  --location=$LOCATION
\`\`\`

---

## 📝 建议

EOF

    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo "1. ❌ **发现 $FAILED_CHECKS 个失败项，需要立即处理**" >> "$REPORT_FILE"
    fi
    
    if [[ $WARNING_CHECKS -gt 0 ]]; then
        echo "2. ⚠️ **发现 $WARNING_CHECKS 个警告项，建议检查并优化**" >> "$REPORT_FILE"
    fi
    
    if [[ $FAILED_CHECKS -eq 0 && $WARNING_CHECKS -eq 0 ]]; then
        echo "✅ **所有检查项均已通过，配置符合最佳实践**" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF

---

## 🔗 相关资源

- [GCP KMS 文档](https://cloud.google.com/kms/docs)
- [IAM 最佳实践](https://cloud.google.com/iam/docs/best-practices)
- [密钥轮换指南](https://cloud.google.com/kms/docs/key-rotation)

---

*报告生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
EOF

    log_success "Markdown 报告已生成: $REPORT_FILE"
}

# 生成 JSON 报告
generate_json_report() {
    local status="passed"
    [[ $FAILED_CHECKS -gt 0 ]] && status="failed"
    [[ $FAILED_CHECKS -eq 0 && $WARNING_CHECKS -gt 0 ]] && status="warning"
    
    cat > "$JSON_REPORT_FILE" << EOF
{
  "metadata": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "kms_project": "$KMS_PROJECT",
    "business_project": "$BUSINESS_PROJECT",
    "keyring": "$KEYRING",
    "crypto_key": "$CRYPTO_KEY",
    "location": "$LOCATION"
  },
  "summary": {
    "status": "$status",
    "total_checks": $TOTAL_CHECKS,
    "passed": $PASSED_CHECKS,
    "warnings": $WARNING_CHECKS,
    "failed": $FAILED_CHECKS
  },
  "checks": [
    $(IFS=,; echo "${CHECK_RESULTS[*]}")
  ]
}
EOF

    log_success "JSON 报告已生成: $JSON_REPORT_FILE"
}

# 生成报告
generate_report() {
    print_separator
    log_info "生成验证报告..."
    
    case "$OUTPUT_FORMAT" in
        json)
            generate_json_report
            ;;
        markdown)
            generate_markdown_report
            ;;
        text|*)
            generate_markdown_report
            ;;
    esac
}

# ============================================================================
# 主函数
# ============================================================================
main() {
    echo -e "${CYAN}" >&2
    cat << "EOF" >&2
╔════════════════════════════════════════════════════════════════╗
║           GCP KMS 跨项目权限校验工具 v2.0.0                    ║
║                      (Enhanced Edition)                        ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}" >&2
    
    # 初始化
    init_temp_dir
    
    # 解析参数
    parse_arguments "$@"
    
    # 执行检查
    check_prerequisites
    check_kms_project
    check_business_project
    check_keyring
    check_crypto_key
    check_iam_policy
    check_service_account_permissions
    check_rotation_policy
    test_encryption
    test_decryption
    
    # 生成报告
    generate_report
    
    # 输出总结
    print_separator
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "${GREEN}✅ 验证完成！所有核心检查通过${NC}" >&2
    else
        echo -e "${RED}❌ 验证完成，但发现问题${NC}" >&2
    fi
    
    echo "" >&2
    echo "📊 检查统计:" >&2
    echo "  总检查项: $TOTAL_CHECKS" >&2
    echo -e "  ${GREEN}通过: $PASSED_CHECKS${NC}" >&2
    echo -e "  ${YELLOW}警告: $WARNING_CHECKS${NC}" >&2
    echo -e "  ${RED}失败: $FAILED_CHECKS${NC}" >&2
    print_separator
    
    # 返回码
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        exit 1
    fi
    
    exit 0
}

# 执行主函数
main "$@"
