#!/bin/bash

# Secret Manager 迁移 - 密钥导入脚本
# 功能：将导出的密钥导入到目标项目

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 导入单个密钥
import_secret() {
    local secret_name=$1
    local secret_dir="$BACKUP_DIR/exported_secrets/$secret_name"
    
    if [[ ! -d "$secret_dir" ]]; then
        log_error "密钥目录不存在: $secret_dir"
        return 1
    fi
    
    log_debug "导入密钥: $secret_name"
    
    # 读取密钥元数据
    local metadata_file="$secret_dir/secret_metadata.json"
    if [[ ! -f "$metadata_file" ]]; then
        log_error "密钥元数据文件不存在: $metadata_file"
        return 1
    fi
    
    # 检查密钥是否已存在
    local secret_exists=false
    if gcloud secrets describe "$secret_name" --project="$TARGET_PROJECT" &>/dev/null; then
        secret_exists=true
        log_warning "密钥 $secret_name 已存在，将添加新版本"
    fi
    
    # 创建密钥（如果不存在）
    if [[ "$secret_exists" == false ]]; then
        log_debug "创建密钥: $secret_name"
        
        # 提取创建参数
        local labels
        labels=$(jq -r '.labels // {} | to_entries | map("--set-label=\(.key)=\(.value)") | join(" ")' "$metadata_file")
        
        # 提取复制策略
        local replication_args=""
        local replication_type
        replication_type=$(jq -r '.replication | keys[0]' "$metadata_file")
        
        case "$replication_type" in
            "automatic")
                replication_args="--replication-policy=automatic"
                ;;
            "userManaged")
                # 用户管理的复制策略比较复杂，这里简化为自动复制
                log_warning "密钥 $secret_name 使用用户管理复制策略，将改为自动复制"
                replication_args="--replication-policy=automatic"
                ;;
            *)
                replication_args="--replication-policy=automatic"
                ;;
        esac
        
        # 构建创建命令
        local create_cmd="gcloud secrets create $secret_name --project=$TARGET_PROJECT $replication_args"
        
        if [[ -n "$labels" ]]; then
            create_cmd="$create_cmd $labels"
        fi
        
        if retry_command $RETRY_COUNT $RETRY_INTERVAL eval "$create_cmd"; then
            log_success "密钥创建成功: $secret_name"
        else
            log_error "密钥创建失败: $secret_name"
            return 1
        fi
    fi
    
    # 导入版本（按版本号排序）
    local version_files
    version_files=$(find "$secret_dir" -name "version_*.txt" | sort -V)
    
    local imported_versions=0
    local failed_versions=0
    local total_versions=0
    
    while IFS= read -r version_file; do
        if [[ -n "$version_file" && -f "$version_file" ]]; then
            ((total_versions++))
            local version_name
            version_name=$(basename "$version_file" .txt | sed 's/version_//')
            
            log_debug "导入版本: $secret_name/$version_name"
            
            # 检查版本文件大小
            local file_size
            file_size=$(stat -f%z "$version_file" 2>/dev/null || stat -c%s "$version_file" 2>/dev/null || echo "0")
            
            if [[ $file_size -eq 0 ]]; then
                log_warning "跳过空版本文件: $version_file"
                ((failed_versions++))
                continue
            fi
            
            # 导入版本
            if retry_command $RETRY_COUNT $RETRY_INTERVAL gcloud secrets versions add "$secret_name" --project="$TARGET_PROJECT" --data-file="$version_file"; then
                ((imported_versions++))
                log_debug "版本导入成功: $secret_name/$version_name"
            else
                ((failed_versions++))
                log_warning "版本导入失败: $secret_name/$version_name"
            fi
        fi
    done <<< "$version_files"
    
    # 导入 IAM 策略
    local iam_policy_file="$secret_dir/iam_policy.json"
    local iam_imported=false
    
    if [[ -f "$iam_policy_file" ]] && [[ "$(jq -r '.bindings // [] | length' "$iam_policy_file")" -gt 0 ]]; then
        log_debug "导入 IAM 策略: $secret_name"
        
        if retry_command $RETRY_COUNT $RETRY_INTERVAL gcloud secrets set-iam-policy "$secret_name" "$iam_policy_file" --project="$TARGET_PROJECT"; then
            log_debug "IAM 策略导入成功: $secret_name"
            iam_imported=true
        else
            log_warning "IAM 策略导入失败: $secret_name，可能需要手动配置"
        fi
    fi
    
    # 创建导入摘要
    local import_summary
    import_summary=$(jq -n \
        --arg secret_name "$secret_name" \
        --argjson total_versions "$total_versions" \
        --argjson imported_versions "$imported_versions" \
        --argjson failed_versions "$failed_versions" \
        --argjson iam_imported "$iam_imported" \
        --arg import_time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            secret_name: $secret_name,
            import_time: $import_time,
            total_versions: $total_versions,
            imported_versions: $imported_versions,
            failed_versions: $failed_versions,
            iam_imported: $iam_imported,
            success_rate: (if $total_versions > 0 then ($imported_versions / $total_versions * 100) else 0 end)
        }')
    
    echo "$import_summary" > "$secret_dir/import_summary.json"
    
    if [[ $failed_versions -eq 0 ]]; then
        log_success "密钥 $secret_name 导入完成 ($imported_versions/$total_versions 版本)"
        return 0
    else
        log_warning "密钥 $secret_name 部分导入失败 ($imported_versions/$total_versions 版本成功)"
        return 1
    fi
}

# 批量导入所有密钥
import_all_secrets() {
    local export_dir="$BACKUP_DIR/exported_secrets"
    
    if [[ ! -d "$export_dir" ]]; then
        log_error "导出目录不存在: $export_dir"
        log_error "请先运行 ./03-export.sh"
        exit 1
    fi
    
    # 获取所有密钥目录
    local secret_dirs
    secret_dirs=$(find "$export_dir" -maxdepth 1 -type d -not -path "$export_dir" | sort)
    
    local total_secrets
    total_secrets=$(echo "$secret_dirs" | wc -l)
    
    if [[ $total_secrets -eq 0 ]]; then
        log_warning "没有发现需要导入的密钥"
        return 0
    fi
    
    log_info "开始批量导入 $total_secrets 个密钥到项目: $TARGET_PROJECT"
    
    local imported_count=0
    local failed_count=0
    local current=0
    
    # 创建导入日志
    local import_log="$BACKUP_DIR/import_log.json"
    echo "[]" > "$import_log"
    
    while IFS= read -r secret_dir; do
        if [[ -n "$secret_dir" && -d "$secret_dir" ]]; then
            ((current++))
            show_progress $current $total_secrets
            
            local secret_name
            secret_name=$(basename "$secret_dir")
            
            local start_time
            start_time=$(date +%s)
            
            if import_secret "$secret_name"; then
                ((imported_count++))
                local status="success"
            else
                ((failed_count++))
                local status="failed"
            fi
            
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            # 记录导入日志
            local log_entry
            log_entry=$(jq -n \
                --arg secret_name "$secret_name" \
                --arg status "$status" \
                --argjson duration "$duration" \
                --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '{
                    secret_name: $secret_name,
                    status: $status,
                    duration_seconds: $duration,
                    timestamp: $timestamp
                }')
            
            jq --argjson entry "$log_entry" '. += [$entry]' "$import_log" > "${import_log}.tmp"
            mv "${import_log}.tmp" "$import_log"
            
            # 批量处理间隔
            if [[ $((current % BATCH_SIZE)) -eq 0 && $current -lt $total_secrets ]]; then
                log_debug "批量处理暂停 2 秒..."
                sleep 2
            fi
        fi
    done <<< "$secret_dirs"
    
    complete_progress
    
    log_success "导入完成 - 成功: $imported_count, 失败: $failed_count"
    
    # 生成导入报告
    generate_import_report "$imported_count" "$failed_count" "$import_log"
    
    return 0
}

# 生成导入报告
generate_import_report() {
    local imported_count=$1
    local failed_count=$2
    local import_log=$3
    local report_file="$BACKUP_DIR/import_report.txt"
    
    log_info "生成导入报告..."
    
    local total_count=$((imported_count + failed_count))
    local success_rate=0
    if [[ $total_count -gt 0 ]]; then
        success_rate=$(echo "scale=2; $imported_count * 100 / $total_count" | bc 2>/dev/null || echo "0")
    fi
    
    # 计算总导入时间
    local total_duration
    total_duration=$(jq '[.[].duration_seconds] | add' "$import_log" 2>/dev/null || echo "0")
    
    # 计算平均导入时间
    local avg_duration=0
    if [[ $total_count -gt 0 ]]; then
        avg_duration=$(echo "scale=2; $total_duration / $total_count" | bc 2>/dev/null || echo "0")
    fi
    
    # 统计版本导入情况
    local total_versions=0
    local imported_versions=0
    local failed_versions=0
    
    for summary_file in "$BACKUP_DIR/exported_secrets"/*/import_summary.json; do
        if [[ -f "$summary_file" ]]; then
            local versions
            versions=$(jq -r '.total_versions' "$summary_file" 2>/dev/null || echo "0")
            total_versions=$((total_versions + versions))
            
            local imported
            imported=$(jq -r '.imported_versions' "$summary_file" 2>/dev/null || echo "0")
            imported_versions=$((imported_versions + imported))
            
            local failed
            failed=$(jq -r '.failed_versions' "$summary_file" 2>/dev/null || echo "0")
            failed_versions=$((failed_versions + failed))
        fi
    done
    
    cat > "$report_file" << EOF
# Secret Manager 导入报告
导入时间: $(date)
目标项目: $TARGET_PROJECT

## 导入统计
成功导入: $imported_count 个密钥
导入失败: $failed_count 个密钥
总计: $total_count 个密钥
成功率: ${success_rate}%

## 版本统计
总版本数: $total_versions
成功导入版本: $imported_versions
失败版本: $failed_versions
版本成功率: $(echo "scale=2; $imported_versions * 100 / $total_versions" | bc 2>/dev/null || echo "0")%

## 性能统计
总导入时间: ${total_duration} 秒
平均导入时间: ${avg_duration} 秒/密钥
批量大小: $BATCH_SIZE

## IAM 策略导入
EOF
    
    # 统计 IAM 策略导入情况
    local iam_imported=0
    for summary_file in "$BACKUP_DIR/exported_secrets"/*/import_summary.json; do
        if [[ -f "$summary_file" ]]; then
            local iam_status
            iam_status=$(jq -r '.iam_imported' "$summary_file" 2>/dev/null || echo "false")
            if [[ "$iam_status" == "true" ]]; then
                ((iam_imported++))
            fi
        fi
    done
    
    echo "成功导入 IAM 策略: $iam_imported 个密钥" >> "$report_file"
    
    # 添加失败的密钥列表
    if [[ $failed_count -gt 0 ]]; then
        echo "" >> "$report_file"
        echo "### 导入失败的密钥" >> "$report_file"
        jq -r '.[] | select(.status == "failed") | "- \(.secret_name)"' "$import_log" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## 导入后验证
请运行以下命令验证导入结果:
gcloud secrets list --project=$TARGET_PROJECT

## 后续步骤
1. 验证所有密钥和版本: ./05-verify.sh
2. 测试应用程序访问
3. 更新应用程序配置: ./06-update-apps.sh
4. 清理源项目密钥（可选）

## 注意事项
- 用户管理的复制策略已转换为自动复制
- 部分 IAM 策略可能需要手动调整
- 建议在生产环境切换前进行全面测试
EOF
    
    log_success "导入报告生成完成: $report_file"
    echo "$report_file"
}

# 验证导入结果
verify_import_results() {
    log_info "验证导入结果..."
    
    # 获取目标项目密钥列表
    local target_secrets
    if ! target_secrets=$(gcloud secrets list --project="$TARGET_PROJECT" --format="value(name)" | sed 's|.*/||'); then
        log_error "无法获取目标项目密钥列表"
        return 1
    fi
    
    local target_count
    target_count=$(echo "$target_secrets" | wc -l)
    
    # 获取源项目密钥列表
    local source_secrets_file="$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json"
    local source_count
    source_count=$(jq length "$source_secrets_file")
    
    log_info "源项目密钥数量: $source_count"
    log_info "目标项目密钥数量: $target_count"
    
    # 检查缺失的密钥
    local missing_secrets=()
    while IFS= read -r source_secret; do
        if [[ -n "$source_secret" ]]; then
            if ! echo "$target_secrets" | grep -q "^$source_secret$"; then
                missing_secrets+=("$source_secret")
            fi
        fi
    done < <(jq -r '.[].name | split("/")[-1]' "$source_secrets_file")
    
    if [[ ${#missing_secrets[@]} -gt 0 ]]; then
        log_warning "以下密钥未成功导入:"
        for secret in "${missing_secrets[@]}"; do
            log_warning "  - $secret"
        done
    else
        log_success "所有密钥都已成功导入"
    fi
    
    return 0
}

# 更新迁移状态
update_migration_status() {
    local status_file="$BACKUP_DIR/migration_status.json"
    
    if [[ -f "$status_file" ]]; then
        jq '.stages.import = "completed" | .last_updated = now | .import_completed_at = now' "$status_file" > "${status_file}.tmp"
        mv "${status_file}.tmp" "$status_file"
        log_debug "迁移状态已更新"
    fi
}

# 主函数
main() {
    log_info "=== Secret Manager 密钥导入开始 ==="
    
    # 检查环境
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        log_error "未找到迁移状态文件，请先运行 ./01-setup.sh"
        exit 1
    fi
    
    # 检查导出阶段是否完成
    local export_status
    export_status=$(jq -r '.stages.export' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
    
    if [[ "$export_status" != "completed" ]]; then
        log_error "密钥导出阶段未完成，请先运行 ./03-export.sh"
        exit 1
    fi
    
    # 确认导入操作
    echo ""
    echo "⚠️  即将开始密钥导入操作"
    echo "源项目: $SOURCE_PROJECT"
    echo "目标项目: $TARGET_PROJECT"
    echo ""
    read -p "确认继续导入？(y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消导入操作"
        exit 0
    fi
    
    # 1. 批量导入密钥
    log_info "步骤 1: 批量导入密钥"
    import_all_secrets
    
    # 2. 验证导入结果
    log_info "步骤 2: 验证导入结果"
    verify_import_results
    
    # 3. 更新状态
    update_migration_status
    
    log_success "=== Secret Manager 密钥导入完成 ==="
    
    echo ""
    echo "导入结果摘要："
    echo "📊 导入日志: $BACKUP_DIR/import_log.json"
    echo "📄 导入报告: $BACKUP_DIR/import_report.txt"
    echo ""
    echo "下一步："
    echo "1. 查看导入报告: cat $BACKUP_DIR/import_report.txt"
    echo "2. 运行迁移验证: ./05-verify.sh"
}

# 执行主函数
main "$@"