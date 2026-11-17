# Shell Scripts Collection

Generated on: 2026-08-02 11:48:38
Directory: /Users/lex/git/knowledge/safe/gcp-safe

## `verify-kms-enhanced.sh`

```bash
#!/bin/bash

################################################################################
# GCP KMS 跨项目权限校验脚本 (增强版)
# 用途: 验证 KMS 跨项目加解密架构的完整性和权限配置
# 版本: 2.0.0
# 改进: 更健壮的错误处理、更准确的 IAM 解析、支持 JSON 输出
################################################################################

set -euo pipefail

# 错误追踪函数
error_handler() {
    local line_no=$1
    local bash_lineno=$2
    local last_command=$3
    local exit_code=$4
    
    echo "" >&2
    echo "========================================================================" >&2
    echo "脚本执行出错！" >&2
    echo "  行号: $line_no" >&2
    echo "  命令: $last_command" >&2
    echo "  退出码: $exit_code" >&2
    echo "========================================================================" >&2
    
    # 清理临时目录
    cleanup_temp_dir
}

# 设置错误追踪
trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND" $?' ERR

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
# 用 jq -n 构造 JSON 对象,避免 message/detail 含双引号时把 JSON 行打坏
record_check() {
    local status="$1"
    local message="$2"
    local detail="${3:-}"

    local entry
    entry=$(jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg detail "$detail" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status: $status, message: $message, detail: $detail, timestamp: $timestamp}')

    CHECK_RESULTS+=("$entry")
}

# 打印信息
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

# 打印成功
log_success() {
    echo -e "${GREEN}[✓]${NC} $1" >&2
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    record_check "success" "$1"
}

# 打印警告
log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" >&2
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    record_check "warning" "$1"
}

# 打印错误
log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
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
        
        case "$cmd" in
            gcloud)
                echo "请安装 Google Cloud SDK: https://cloud.google.com/sdk/docs/install" >&2
                ;;
            jq)
                echo "请安装 jq: " >&2
                echo "  - Ubuntu/Debian: sudo apt-get install jq" >&2
                echo "  - CentOS/RHEL: sudo yum install jq" >&2
                echo "  - macOS: brew install jq" >&2
                ;;
        esac
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
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    check_command "gcloud"
    check_command "jq"
    
    # 验证 gcloud 已认证
    local auth_account
    auth_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1 || true)
    
    if [[ -z "$auth_account" ]]; then
        log_error "gcloud 未认证或无活动账号，请先运行: gcloud auth login"
        [[ "$VERBOSE" == true ]] && echo "认证检查输出: $auth_account" >&2
        exit 1
    fi
    
    log_success "前置条件检查通过 (gcloud, jq) - 当前账号: ${auth_account%%$'\n'*}"
}

# 2. 验证 KMS 项目访问权限
check_kms_project() {
    print_separator
    log_info "验证 KMS 项目: $KMS_PROJECT"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
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
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
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
# 这个逻辑有一点问题 ，因为我不能 descreep，但是我可以 get。 
check_keyring() {
    print_separator
    log_info "验证 Keyring: $KEYRING (位置: $LOCATION)"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # 使用 list 命令验证 Keyring 是否存在（不需要 describe 权限）
    local keyring_list
    if keyring_list=$(gcloud kms keyrings list \
        --project="$KMS_PROJECT" \
        --location="$LOCATION" \
        --filter="name:$KEYRING" \
        --format=json 2>&1); then
        
        # 检查是否找到匹配的 Keyring
        local keyring_count
        keyring_count=$(echo "$keyring_list" | jq '. | length')
        
        if [[ "$keyring_count" -gt 0 ]]; then
            local keyring_name
            keyring_name=$(echo "$keyring_list" | jq -r '.[0].name // "unknown"')
            log_success "Keyring 存在: $keyring_name"
        else
            log_error "Keyring 不存在或无权限访问: $KEYRING"
            [[ "$VERBOSE" == true ]] && echo "未找到匹配的 Keyring" >&2
            exit 1
        fi
    else
        log_error "无法列出 Keyring (可能缺少 cloudkms.keyRings.list 权限)"
        [[ "$VERBOSE" == true ]] && echo "$keyring_list" >&2
        exit 1
    fi
}

# 5. 验证 CryptoKey 存在性
check_crypto_key() {
    print_separator
    log_info "验证 CryptoKey: $CRYPTO_KEY"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # 使用 list 命令验证 CryptoKey 是否存在（不需要 describe 权限）
    local key_list
    if key_list=$(gcloud kms keys list \
        --project="$KMS_PROJECT" \
        --keyring="$KEYRING" \
        --location="$LOCATION" \
        --filter="name:$CRYPTO_KEY" \
        --format=json 2>&1); then
        
        # 检查是否找到匹配的 CryptoKey
        local key_count
        key_count=$(echo "$key_list" | jq '. | length')
        
        if [[ "$key_count" -gt 0 ]]; then
            local key_purpose
            key_purpose=$(echo "$key_list" | jq -r '.[0].purpose // "unknown"')
            local key_state
            key_state=$(echo "$key_list" | jq -r '.[0].primary.state // "unknown"')
            local key_name
            key_name=$(echo "$key_list" | jq -r '.[0].name // "unknown"')
            
            log_success "CryptoKey 存在 (用途: $key_purpose, 状态: $key_state)"
            
            # 保存密钥信息供后续使用
            echo "$key_list" | jq '.[0]' > "$TEMP_DIR/key_info.json"
        else
            log_error "CryptoKey 不存在或无权限访问: $CRYPTO_KEY"
            [[ "$VERBOSE" == true ]] && echo "未找到匹配的 CryptoKey" >&2
            exit 1
        fi
    else
        log_error "无法列出 CryptoKey (可能缺少 cloudkms.cryptoKeys.list 权限)"
        [[ "$VERBOSE" == true ]] && echo "$key_list" >&2
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
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        
        local has_encrypt=false
        local has_decrypt=false
        
        # -xF = 整行精确匹配:避免短 SA 名误中长 SA 的子串(grep -qF 默认子串匹配)
        if echo "$encrypters" | grep -qxF "$sa"; then
            has_encrypt=true
        fi

        if echo "$decrypters" | grep -qxF "$sa"; then
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
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
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
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
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
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
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
    
    # 调试信息
    if [[ "$VERBOSE" == true ]]; then
        log_info "调试模式已启用"
        log_info "临时目录: $TEMP_DIR"
        log_info "Shell: $SHELL"
        log_info "Bash 版本: $BASH_VERSION"
    fi
    
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

```

## `test-permissions.sh`

```bash
#!/bin/bash

################################################################################
# KMS 权限测试脚本
# 用于测试 describe vs list 命令的权限要求
################################################################################

set -euo pipefail

echo "=========================================="
echo "KMS 权限测试：describe vs list"
echo "=========================================="
echo ""

# 检查参数
if [[ $# -lt 4 ]]; then
    echo "使用方法: $0 KMS_PROJECT LOCATION KEYRING CRYPTO_KEY"
    echo ""
    echo "示例:"
    echo "  $0 my-kms-project global my-keyring my-key"
    exit 1
fi

KMS_PROJECT="$1"
LOCATION="$2"
KEYRING="$3"
CRYPTO_KEY="$4"

echo "测试配置:"
echo "  KMS 项目: $KMS_PROJECT"
echo "  位置: $LOCATION"
echo "  Keyring: $KEYRING"
echo "  CryptoKey: $CRYPTO_KEY"
echo ""

# ============================================================================
# 测试 Keyring 访问
# ============================================================================
echo "1. 测试 Keyring 访问方法"
echo "----------------------------------------"

# 方法 1: describe (需要 cloudkms.keyRings.get 权限)
echo "方法 1: gcloud kms keyrings describe"
if gcloud kms keyrings describe "$KEYRING" \
    --project="$KMS_PROJECT" \
    --location="$LOCATION" \
    --format=json &> /dev/null; then
    echo "  ✓ describe 成功 (有 cloudkms.keyRings.get 权限)"
else
    echo "  ✗ describe 失败 (缺少 cloudkms.keyRings.get 权限)"
fi
echo ""

# 方法 2: list (需要 cloudkms.keyRings.list 权限)
echo "方法 2: gcloud kms keyrings list"
keyring_list=$(gcloud kms keyrings list \
    --project="$KMS_PROJECT" \
    --location="$LOCATION" \
    --filter="name:$KEYRING" \
    --format=json 2>&1 || echo "[]")

keyring_count=$(echo "$keyring_list" | jq '. | length' 2>/dev/null || echo "0")

if [[ "$keyring_count" -gt 0 ]]; then
    echo "  ✓ list 成功 (有 cloudkms.keyRings.list 权限)"
    echo "  找到 Keyring: $(echo "$keyring_list" | jq -r '.[0].name')"
else
    echo "  ✗ list 失败或未找到 (缺少 cloudkms.keyRings.list 权限或 Keyring 不存在)"
fi
echo ""

# ============================================================================
# 测试 CryptoKey 访问
# ============================================================================
echo "2. 测试 CryptoKey 访问方法"
echo "----------------------------------------"

# 方法 1: describe (需要 cloudkms.cryptoKeys.get 权限)
echo "方法 1: gcloud kms keys describe"
if key_info=$(gcloud kms keys describe "$CRYPTO_KEY" \
    --project="$KMS_PROJECT" \
    --keyring="$KEYRING" \
    --location="$LOCATION" \
    --format=json 2>&1); then
    echo "  ✓ describe 成功 (有 cloudkms.cryptoKeys.get 权限)"
    key_purpose=$(echo "$key_info" | jq -r '.purpose // "unknown"')
    key_state=$(echo "$key_info" | jq -r '.primary.state // "unknown"')
    echo "  密钥用途: $key_purpose"
    echo "  密钥状态: $key_state"
else
    echo "  ✗ describe 失败 (缺少 cloudkms.cryptoKeys.get 权限)"
fi
echo ""

# 方法 2: list (需要 cloudkms.cryptoKeys.list 权限)
echo "方法 2: gcloud kms keys list"
key_list=$(gcloud kms keys list \
    --project="$KMS_PROJECT" \
    --keyring="$KEYRING" \
    --location="$LOCATION" \
    --filter="name:$CRYPTO_KEY" \
    --format=json 2>&1 || echo "[]")

key_count=$(echo "$key_list" | jq '. | length' 2>/dev/null || echo "0")

if [[ "$key_count" -gt 0 ]]; then
    echo "  ✓ list 成功 (有 cloudkms.cryptoKeys.list 权限)"
    echo "  找到 CryptoKey: $(echo "$key_list" | jq -r '.[0].name')"
    key_purpose=$(echo "$key_list" | jq -r '.[0].purpose // "unknown"')
    key_state=$(echo "$key_list" | jq -r '.[0].primary.state // "unknown"')
    echo "  密钥用途: $key_purpose"
    echo "  密钥状态: $key_state"
else
    echo "  ✗ list 失败或未找到 (缺少 cloudkms.cryptoKeys.list 权限或 Key 不存在)"
fi
echo ""

# ============================================================================
# 测试 IAM 策略访问
# ============================================================================
echo "3. 测试 IAM 策略访问"
echo "----------------------------------------"

echo "gcloud kms keys get-iam-policy"
if iam_policy=$(gcloud kms keys get-iam-policy "$CRYPTO_KEY" \
    --project="$KMS_PROJECT" \
    --keyring="$KEYRING" \
    --location="$LOCATION" \
    --format=json 2>&1); then
    echo "  ✓ get-iam-policy 成功 (有 cloudkms.cryptoKeys.getIamPolicy 权限)"
    bindings_count=$(echo "$iam_policy" | jq '.bindings | length // 0')
    echo "  IAM 绑定数量: $bindings_count"
else
    echo "  ✗ get-iam-policy 失败 (缺少 cloudkms.cryptoKeys.getIamPolicy 权限)"
fi
echo ""

# ============================================================================
# 总结
# ============================================================================
echo "=========================================="
echo "总结"
echo "=========================================="
echo ""
echo "权限对比:"
echo ""
echo "describe 方法需要的权限:"
echo "  - cloudkms.keyRings.get"
echo "  - cloudkms.cryptoKeys.get"
echo ""
echo "list 方法需要的权限:"
echo "  - cloudkms.keyRings.list"
echo "  - cloudkms.cryptoKeys.list"
echo ""
echo "建议:"
echo "  - 如果只有 list 权限，使用 list 方法（脚本已优化）"
echo "  - 如果有 get 权限，describe 方法可以获取更详细的信息"
echo "  - list 方法更适合最小权限原则"
echo ""
echo "当前脚本使用: list 方法 (v2.0.1+)"

```

## `test-arithmetic.sh`

```bash
#!/bin/bash

echo "测试 Bash 算术运算在 set -euo pipefail 下的行为"
echo "================================================"
echo ""

# 测试 1: 不使用 set -e
echo "测试 1: 正常模式"
COUNTER=0
((COUNTER++))
echo "COUNTER = $COUNTER (成功)"
echo ""

# 测试 2: 使用 set -e
echo "测试 2: set -e 模式"
(
    set -e
    COUNTER=0
    ((COUNTER++)) || true  # 需要 || true 来避免退出
    echo "COUNTER = $COUNTER (成功)"
)
echo ""

# 测试 3: 演示问题
echo "测试 3: 演示 ((COUNTER++)) 的退出码"
COUNTER=0
((COUNTER++))
echo "退出码: $?"
echo "COUNTER = $COUNTER"
echo ""

# 测试 4: 当值为 0 时
echo "测试 4: 当值为 0 时的退出码"
COUNTER=0
if ((COUNTER)); then
    echo "COUNTER 为真"
else
    echo "COUNTER 为假 (退出码: $?)"
fi
echo ""

# 测试 5: 安全的递增方式
echo "测试 5: 安全的递增方式"
set -euo pipefail
COUNTER=0

# 方式 1: 使用 let
let COUNTER++ || true
echo "方式 1 (let): COUNTER = $COUNTER"

# 方式 2: 使用算术展开
COUNTER=$((COUNTER + 1))
echo "方式 2 (算术展开): COUNTER = $COUNTER"

# 方式 3: 使用 (()) 但加 || true
((COUNTER++)) || true
echo "方式 3 ((++)) || true: COUNTER = $COUNTER"

# 方式 4: 最安全的方式
: $((COUNTER++))
echo "方式 4 (: $((++))): COUNTER = $COUNTER"

echo ""
echo "结论: 在 set -e 模式下，((COUNTER++)) 可能导致脚本退出！"
echo "推荐使用: COUNTER=\$((COUNTER + 1)) 或 : \$((COUNTER++))"

```

## `quick-test.sh`

```bash
#!/bin/bash

################################################################################
# 快速测试脚本 - 验证修复是否生效
################################################################################

echo "=========================================="
echo "快速测试：验证计数器修复"
echo "=========================================="
echo ""

# 模拟脚本的 set -euo pipefail 环境
set -euo pipefail

echo "1. 测试变量初始化"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
echo "   ✓ 变量初始化成功"
echo ""

echo "2. 测试计数器递增（新方式）"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
echo "   TOTAL_CHECKS = $TOTAL_CHECKS"

PASSED_CHECKS=$((PASSED_CHECKS + 1))
echo "   PASSED_CHECKS = $PASSED_CHECKS"

WARNING_CHECKS=$((WARNING_CHECKS + 1))
echo "   WARNING_CHECKS = $WARNING_CHECKS"

FAILED_CHECKS=$((FAILED_CHECKS + 1))
echo "   FAILED_CHECKS = $FAILED_CHECKS"
echo "   ✓ 所有计数器递增成功"
echo ""

echo "3. 测试多次递增"
for i in {1..5}; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
done
echo "   TOTAL_CHECKS 经过 5 次递增 = $TOTAL_CHECKS"
echo "   ✓ 循环递增成功"
echo ""

echo "4. 测试在函数中使用"
test_function() {
    local local_counter=0
    local_counter=$((local_counter + 1))
    echo "   函数内计数器 = $local_counter"
}
test_function
echo "   ✓ 函数内递增成功"
echo ""

echo "5. 模拟实际使用场景"
simulate_check() {
    local check_name="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ "$check_name" == "success" ]]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        echo "   [✓] $check_name 检查"
    elif [[ "$check_name" == "warning" ]]; then
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
        echo "   [⚠] $check_name 检查"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        echo "   [✗] $check_name 检查"
    fi
}

simulate_check "success"
simulate_check "warning"
simulate_check "success"

echo ""
echo "   最终统计:"
echo "   - 总检查: $TOTAL_CHECKS"
echo "   - 通过: $PASSED_CHECKS"
echo "   - 警告: $WARNING_CHECKS"
echo "   - 失败: $FAILED_CHECKS"
echo "   ✓ 实际场景模拟成功"
echo ""

echo "=========================================="
echo "✅ 所有测试通过！"
echo "=========================================="
echo ""
echo "修复已生效，脚本不会因为计数器递增而退出。"
echo "现在可以安全地运行主脚本了。"

```

## `debug-test.sh`

```bash
#!/bin/bash

################################################################################
# KMS 验证脚本调试工具
# 用于快速诊断环境问题
################################################################################

set -euo pipefail

echo "=========================================="
echo "KMS 验证脚本环境诊断"
echo "=========================================="
echo ""

# 1. 检查 Shell 环境
echo "1. Shell 环境:"
echo "   Shell: $SHELL"
echo "   Bash 版本: $BASH_VERSION"
echo ""

# 2. 检查必需命令
echo "2. 检查必需命令:"
if command -v gcloud &> /dev/null; then
    echo "   ✓ gcloud: $(command -v gcloud)"
    gcloud_version=$(gcloud version --format="value(core)" 2>&1 || echo "无法获取版本")
    echo "     版本: $gcloud_version"
else
    echo "   ✗ gcloud: 未找到"
fi

if command -v jq &> /dev/null; then
    echo "   ✓ jq: $(command -v jq)"
    jq_version=$(jq --version 2>&1 || echo "无法获取版本")
    echo "     版本: $jq_version"
else
    echo "   ✗ jq: 未找到"
fi
echo ""

# 3. 检查 gcloud 认证
echo "3. 检查 gcloud 认证:"
if command -v gcloud &> /dev/null; then
    echo "   尝试获取活动账号..."
    
    # 方法 1: 使用 filter
    auth_account1=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1 || echo "ERROR")
    echo "   方法1 (filter): $auth_account1"
    
    # 方法 2: 不使用 filter
    auth_account2=$(gcloud auth list --format="value(account)" 2>&1 | head -1 || echo "ERROR")
    echo "   方法2 (no filter): $auth_account2"
    
    # 方法 3: 使用 config
    auth_account3=$(gcloud config get-value account 2>&1 || echo "ERROR")
    echo "   方法3 (config): $auth_account3"
    
    # 显示完整的认证列表
    echo ""
    echo "   完整认证列表:"
    gcloud auth list 2>&1 | sed 's/^/     /'
else
    echo "   跳过 (gcloud 未安装)"
fi
echo ""

# 4. 检查临时目录权限
echo "4. 检查临时目录:"
TEMP_TEST_DIR="/tmp/kms-validator-test-$$"
if mkdir -p "$TEMP_TEST_DIR" 2>&1; then
    echo "   ✓ 可以创建临时目录: $TEMP_TEST_DIR"
    if echo "test" > "$TEMP_TEST_DIR/test.txt" 2>&1; then
        echo "   ✓ 可以写入文件"
    else
        echo "   ✗ 无法写入文件"
    fi
    rm -rf "$TEMP_TEST_DIR"
else
    echo "   ✗ 无法创建临时目录"
fi
echo ""

# 5. 测试 set -euo pipefail 行为
echo "5. 测试错误处理:"
test_function() {
    local result
    result=$(false 2>&1 || true)
    echo "   ✓ 使用 '|| true' 可以捕获错误"
}
test_function
echo ""

# 6. 测试 jq 解析
echo "6. 测试 jq 解析:"
if command -v jq &> /dev/null; then
    test_json='{"test": "value", "number": 123}'
    parsed=$(echo "$test_json" | jq -r '.test' 2>&1 || echo "ERROR")
    if [[ "$parsed" == "value" ]]; then
        echo "   ✓ jq 解析正常"
    else
        echo "   ✗ jq 解析失败: $parsed"
    fi
else
    echo "   跳过 (jq 未安装)"
fi
echo ""

echo "=========================================="
echo "诊断完成"
echo "=========================================="
echo ""
echo "如果所有检查都通过，请尝试运行:"
echo "  ./verify-kms-enhanced.sh --verbose [其他参数]"
echo ""
echo "如果仍有问题，请提供以上输出信息"

```

