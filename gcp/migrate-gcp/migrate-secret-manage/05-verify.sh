#!/bin/bash

# Secret Manager 迁移 - 验证脚本
# 功能：验证迁移结果的完整性和正确性

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 比较两个项目的密钥列表
compare_secret_lists() {
    log_info "比较源项目和目标项目的密钥列表..."
    
    local source_secrets_file="$BACKUP_DIR/source_secrets_comparison.json"
    local target_secrets_file="$BACKUP_DIR/target_secrets_comparison.json"
    local comparison_report="$BACKUP_DIR/secrets_comparison_report.txt"
    
    # 获取源项目密钥列表
    if ! gcloud secrets list --project="$SOURCE_PROJECT" --format=json > "$source_secrets_file"; then
        log_error "无法获取源项目密钥列表"
        return 1
    fi
    
    # 获取目标项目密钥列表
    if ! gcloud secrets list --project="$TARGET_PROJECT" --format=json > "$target_secrets_file"; then
        log_error "无法获取目标项目密钥列表"
        return 1
    fi
    
    # 生成比较报告
    cat > "$comparison_report" << EOF
# 密钥迁移比较报告
比较时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 密钥数量比较
EOF
    
    local source_count
    source_count=$(jq length "$source_secrets_file")
    local target_count
    target_count=$(jq length "$target_secrets_file")
    
    echo "源项目密钥数量: $source_count" >> "$comparison_report"
    echo "目标项目密钥数量: $target_count" >> "$comparison_report"
    echo "" >> "$comparison_report"
    
    # 检查缺失的密钥
    echo "## 缺失的密钥（在源项目中存在但目标项目中不存在）" >> "$comparison_report"
    local missing_secrets
    missing_secrets=$(jq -r --slurpfile target "$target_secrets_file" '
        [.[].name | split("/")[-1]] - [$target[0][].name | split("/")[-1]] | .[]
    ' "$source_secrets_file" 2>/dev/null || echo "")
    
    if [[ -n "$missing_secrets" && "$missing_secrets" != "null" ]]; then
        echo "$missing_secrets" >> "$comparison_report"
        log_warning "发现缺失的密钥"
    else
        echo "无缺失密钥" >> "$comparison_report"
        log_success "所有密钥都已迁移"
    fi
    
    echo "" >> "$comparison_report"
    
    # 检查额外的密钥
    echo "## 额外的密钥（仅在目标项目中存在）" >> "$comparison_report"
    local extra_secrets
    extra_secrets=$(jq -r --slurpfile source "$source_secrets_file" '
        [.[].name | split("/")[-1]] - [$source[0][].name | split("/")[-1]] | .[]
    ' "$target_secrets_file" 2>/dev/null || echo "")
    
    if [[ -n "$extra_secrets" && "$extra_secrets" != "null" ]]; then
        echo "$extra_secrets" >> "$comparison_report"
        log_info "目标项目存在额外密钥"
    else
        echo "无额外密钥" >> "$comparison_report"
    fi
    
    log_success "密钥列表比较完成: $comparison_report"
    echo "$comparison_report"
}

# 验证单个密钥的版本数量
verify_secret_versions() {
    local secret_name=$1
    
    log_debug "验证密钥版本: $secret_name"
    
    # 获取源项目版本
    local source_versions
    if ! source_versions=$(gcloud secrets versions list "$secret_name" --project="$SOURCE_PROJECT" --format="value(name)" 2>/dev/null); then
        log_warning "无法获取源项目密钥 $secret_name 的版本信息"
        return 1
    fi
    
    # 获取目标项目版本
    local target_versions
    if ! target_versions=$(gcloud secrets versions list "$secret_name" --project="$TARGET_PROJECT" --format="value(name)" 2>/dev/null); then
        log_warning "无法获取目标项目密钥 $secret_name 的版本信息"
        return 1
    fi
    
    local source_count
    source_count=$(echo "$source_versions" | grep -c . || echo "0")
    local target_count
    target_count=$(echo "$target_versions" | grep -c . || echo "0")
    
    if [[ "$source_count" -eq "$target_count" ]]; then
        log_debug "密钥 $secret_name 版本数量匹配: $source_count"
        return 0
    else
        log_warning "密钥 $secret_name 版本数量不匹配 - 源: $source_count, 目标: $target_count"
        return 1
    fi
}

# 验证密钥值（可选，可能耗时较长）
verify_secret_values() {
    local secret_name=$1
    
    if [[ "$VERIFY_SECRET_VALUES" != "true" ]]; then
        log_debug "跳过密钥值验证: $secret_name"
        return 0
    fi
    
    log_debug "验证密钥值: $secret_name"
    
    # 获取最新版本的值
    local source_value
    if ! source_value=$(gcloud secrets versions access latest --secret="$secret_name" --project="$SOURCE_PROJECT" 2>/dev/null); then
        log_warning "无法访问源项目密钥 $secret_name 的值"
        return 1
    fi
    
    local target_value
    if ! target_value=$(gcloud secrets versions access latest --secret="$secret_name" --project="$TARGET_PROJECT" 2>/dev/null); then
        log_warning "无法访问目标项目密钥 $secret_name 的值"
        return 1
    fi
    
    if [[ "$source_value" == "$target_value" ]]; then
        log_debug "密钥 $secret_name 值匹配"
        return 0
    else
        log_error "密钥 $secret_name 值不匹配"
        return 1
    fi
}

# 验证 IAM 策略
verify_iam_policies() {
    local secret_name=$1
    
    log_debug "验证 IAM 策略: $secret_name"
    
    # 获取源项目 IAM 策略
    local source_policy
    if ! source_policy=$(gcloud secrets get-iam-policy "$secret_name" --project="$SOURCE_PROJECT" --format=json 2>/dev/null); then
        source_policy="{}"
    fi
    
    # 获取目标项目 IAM 策略
    local target_policy
    if ! target_policy=$(gcloud secrets get-iam-policy "$secret_name" --project="$TARGET_PROJECT" --format=json 2>/dev/null); then
        target_policy="{}"
    fi
    
    # 比较绑定数量
    local source_bindings
    source_bindings=$(echo "$source_policy" | jq '.bindings // [] | length')
    local target_bindings
    target_bindings=$(echo "$target_policy" | jq '.bindings // [] | length')
    
    if [[ "$source_bindings" -eq "$target_bindings" ]]; then
        log_debug "密钥 $secret_name IAM 策略绑定数量匹配: $source_bindings"
        return 0
    else
        log_warning "密钥 $secret_name IAM 策略绑定数量不匹配 - 源: $source_bindings, 目标: $target_bindings"
        return 1
    fi
}

# 全面验证单个密钥
comprehensive_secret_verification() {
    local secret_name=$1
    local verification_results=()
    
    # 版本验证
    if verify_secret_versions "$secret_name"; then
        verification_results+=("versions:✅")
    else
        verification_results+=("versions:❌")
    fi
    
    # 值验证（如果启用）
    if [[ "$VERIFY_SECRET_VALUES" == "true" ]]; then
        if verify_secret_values "$secret_name"; then
            verification_results+=("values:✅")
        else
            verification_results+=("values:❌")
        fi
    else
        verification_results+=("values:⏭️")
    fi
    
    # IAM 策略验证
    if verify_iam_policies "$secret_name"; then
        verification_results+=("iam:✅")
    else
        verification_results+=("iam:⚠️")
    fi
    
    echo "${verification_results[*]}"
}

# 批量验证所有密钥
verify_all_secrets() {
    log_info "开始全面验证迁移结果..."
    
    # 获取目标项目的密钥列表进行验证
    local target_secrets
    if ! target_secrets=$(gcloud secrets list --project="$TARGET_PROJECT" --format="value(name)" | sed 's|.*/||'); then
        log_error "无法获取目标项目密钥列表"
        return 1
    fi
    
    local total_secrets
    total_secrets=$(echo "$target_secrets" | grep -c . || echo "0")
    
    if [[ $total_secrets -eq 0 ]]; then
        log_warning "目标项目中没有密钥"
        return 1
    fi
    
    log_info "开始验证 $total_secrets 个密钥..."
    
    local verified_count=0
    local failed_count=0
    local current=0
    
    # 创建验证日志
    local verification_log="$BACKUP_DIR/verification_log.json"
    echo "[]" > "$verification_log"
    
    while IFS= read -r secret_name; do
        if [[ -n "$secret_name" ]]; then
            ((current++))
            show_progress $current $total_secrets
            
            local start_time
            start_time=$(date +%s)
            
            local verification_result
            verification_result=$(comprehensive_secret_verification "$secret_name")
            
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            # 判断整体验证结果
            local overall_status="success"
            if [[ "$verification_result" == *"❌"* ]]; then
                overall_status="failed"
                ((failed_count++))
            else
                ((verified_count++))
            fi
            
            # 记录验证日志
            local log_entry
            log_entry=$(jq -n \
                --arg secret_name "$secret_name" \
                --arg status "$overall_status" \
                --arg details "$verification_result" \
                --argjson duration "$duration" \
                --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '{
                    secret_name: $secret_name,
                    status: $status,
                    verification_details: $details,
                    duration_seconds: $duration,
                    timestamp: $timestamp
                }')
            
            jq --argjson entry "$log_entry" '. += [$entry]' "$verification_log" > "${verification_log}.tmp"
            mv "${verification_log}.tmp" "$verification_log"
        fi
    done <<< "$target_secrets"
    
    complete_progress
    
    log_success "验证完成 - 通过: $verified_count, 失败: $failed_count"
    
    # 生成验证报告
    generate_verification_report "$verified_count" "$failed_count" "$verification_log"
    
    return 0
}

# 生成验证报告
generate_verification_report() {
    local verified_count=$1
    local failed_count=$2
    local verification_log=$3
    local report_file="$BACKUP_DIR/verification_report.txt"
    
    log_info "生成验证报告..."
    
    local total_count=$((verified_count + failed_count))
    local success_rate=0
    if [[ $total_count -gt 0 ]]; then
        success_rate=$(echo "scale=2; $verified_count * 100 / $total_count" | bc 2>/dev/null || echo "0")
    fi
    
    # 计算总验证时间
    local total_duration
    total_duration=$(jq '[.[].duration_seconds] | add' "$verification_log" 2>/dev/null || echo "0")
    
    cat > "$report_file" << EOF
# 迁移验证报告
验证时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 验证结果概览
验证通过: $verified_count 个密钥
验证失败: $failed_count 个密钥
总计: $total_count 个密钥
成功率: ${success_rate}%

## 验证配置
验证密钥值: $VERIFY_SECRET_VALUES
验证超时: $VERIFICATION_TIMEOUT 秒
总验证时间: ${total_duration} 秒

## 详细验证结果
EOF
    
    # 按验证项目统计
    local version_pass=0
    local version_fail=0
    local value_pass=0
    local value_fail=0
    local value_skip=0
    local iam_pass=0
    local iam_warn=0
    
    while IFS= read -r details; do
        if [[ -n "$details" ]]; then
            if [[ "$details" == *"versions:✅"* ]]; then ((version_pass++)); fi
            if [[ "$details" == *"versions:❌"* ]]; then ((version_fail++)); fi
            if [[ "$details" == *"values:✅"* ]]; then ((value_pass++)); fi
            if [[ "$details" == *"values:❌"* ]]; then ((value_fail++)); fi
            if [[ "$details" == *"values:⏭️"* ]]; then ((value_skip++)); fi
            if [[ "$details" == *"iam:✅"* ]]; then ((iam_pass++)); fi
            if [[ "$details" == *"iam:⚠️"* ]]; then ((iam_warn++)); fi
        fi
    done < <(jq -r '.[].verification_details' "$verification_log")
    
    cat >> "$report_file" << EOF

### 版本验证
通过: $version_pass 个密钥
失败: $version_fail 个密钥

### 值验证
通过: $value_pass 个密钥
失败: $value_fail 个密钥
跳过: $value_skip 个密钥

### IAM 策略验证
通过: $iam_pass 个密钥
警告: $iam_warn 个密钥

## 验证失败的密钥
EOF
    
    # 列出验证失败的密钥
    local failed_secrets
    failed_secrets=$(jq -r '.[] | select(.status == "failed") | .secret_name' "$verification_log")
    
    if [[ -n "$failed_secrets" ]]; then
        while IFS= read -r secret_name; do
            if [[ -n "$secret_name" ]]; then
                local details
                details=$(jq -r --arg name "$secret_name" '.[] | select(.secret_name == $name) | .verification_details' "$verification_log")
                echo "- $secret_name: $details" >> "$report_file"
            fi
        done <<< "$failed_secrets"
    else
        echo "无验证失败的密钥" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## 建议
EOF
    
    if [[ $failed_count -eq 0 ]]; then
        cat >> "$report_file" << EOF
✅ 所有密钥验证通过，迁移成功！

建议的后续步骤:
1. 更新应用程序配置指向新项目
2. 测试应用程序功能
3. 监控应用程序运行状态
4. 考虑清理源项目密钥
EOF
    else
        cat >> "$report_file" << EOF
⚠️  存在验证失败的密钥，建议:

1. 检查失败密钥的详细错误信息
2. 手动验证失败的密钥
3. 重新导入失败的密钥
4. 在修复所有问题后再进行应用切换

修复命令示例:
# 重新导入单个密钥
gcloud secrets versions add SECRET_NAME --project=$TARGET_PROJECT --data-file=backup/exported_secrets/SECRET_NAME/version_latest.txt

# 重新设置 IAM 策略
gcloud secrets set-iam-policy SECRET_NAME backup/exported_secrets/SECRET_NAME/iam_policy.json --project=$TARGET_PROJECT
EOF
    fi
    
    cat >> "$report_file" << EOF

## 验证详情
详细验证日志: $verification_log
比较报告: $(find "$BACKUP_DIR" -name "*comparison_report.txt" | head -1)

## 下一步
EOF
    
    if [[ $failed_count -eq 0 ]]; then
        echo "1. 运行应用配置更新: ./06-update-apps.sh" >> "$report_file"
        echo "2. 测试应用程序功能" >> "$report_file"
        echo "3. 监控生产环境" >> "$report_file"
    else
        echo "1. 修复验证失败的密钥" >> "$report_file"
        echo "2. 重新运行验证: ./05-verify.sh" >> "$report_file"
        echo "3. 确认所有问题解决后再进行应用切换" >> "$report_file"
    fi
    
    log_success "验证报告生成完成: $report_file"
    echo "$report_file"
}

# 更新迁移状态
update_migration_status() {
    local verification_success=$1
    local status_file="$BACKUP_DIR/migration_status.json"
    
    if [[ -f "$status_file" ]]; then
        local verify_status="completed"
        if [[ "$verification_success" != "true" ]]; then
            verify_status="failed"
        fi
        
        jq --arg status "$verify_status" '.stages.verify = $status | .last_updated = now | .verify_completed_at = now' "$status_file" > "${status_file}.tmp"
        mv "${status_file}.tmp" "$status_file"
        log_debug "迁移状态已更新"
    fi
}

# 主函数
main() {
    log_info "=== Secret Manager 迁移验证开始 ==="
    
    # 检查环境
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        log_error "未找到迁移状态文件，请先运行 ./01-setup.sh"
        exit 1
    fi
    
    # 检查导入阶段是否完成
    local import_status
    import_status=$(jq -r '.stages.import' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
    
    if [[ "$import_status" != "completed" ]]; then
        log_error "密钥导入阶段未完成，请先运行 ./04-import.sh"
        exit 1
    fi
    
    local verification_success=true
    
    # 1. 比较密钥列表
    log_info "步骤 1: 比较密钥列表"
    local comparison_report
    comparison_report=$(compare_secret_lists)
    
    # 2. 全面验证密钥
    log_info "步骤 2: 全面验证密钥"
    if ! verify_all_secrets; then
        verification_success=false
    fi
    
    # 3. 更新状态
    update_migration_status "$verification_success"
    
    log_success "=== Secret Manager 迁移验证完成 ==="
    
    echo ""
    echo "验证结果摘要："
    echo "📊 验证日志: $BACKUP_DIR/verification_log.json"
    echo "📄 验证报告: $BACKUP_DIR/verification_report.txt"
    echo "📋 比较报告: $comparison_report"
    echo ""
    
    if [[ "$verification_success" == "true" ]]; then
        echo "✅ 验证通过！可以安全地进行应用切换"
        echo ""
        echo "下一步："
        echo "1. 查看验证报告: cat $BACKUP_DIR/verification_report.txt"
        echo "2. 更新应用配置: ./06-update-apps.sh"
    else
        echo "⚠️  验证发现问题，请检查报告并修复"
        echo ""
        echo "建议："
        echo "1. 查看验证报告: cat $BACKUP_DIR/verification_report.txt"
        echo "2. 修复失败的密钥"
        echo "3. 重新运行验证: ./05-verify.sh"
    fi
}

# 执行主函数
main "$@"