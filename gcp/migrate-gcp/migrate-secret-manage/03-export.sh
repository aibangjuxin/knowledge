#!/bin/bash

# Secret Manager 迁移 - 密钥导出脚本
# 功能：导出源项目中的所有密钥数据

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 导出单个密钥的所有版本
export_secret_versions() {
    local project=$1
    local secret_name=$2
    local export_dir="$BACKUP_DIR/exported_secrets"
    
    mkdir -p "$export_dir"
    
    log_debug "导出密钥: $secret_name"
    
    local secret_export_dir="$export_dir/$secret_name"
    mkdir -p "$secret_export_dir"
    
    # 获取所有版本（按创建时间排序）
    local versions
    if ! versions=$(gcloud secrets versions list "$secret_name" --project="$project" --sort-by=createTime --format="value(name)" 2>/dev/null); then
        log_error "无法获取密钥 $secret_name 的版本列表"
        return 1
    fi
    
    if [[ -z "$versions" ]]; then
        log_warning "密钥 $secret_name 没有可用版本"
        return 1
    fi
    
    local version_count=0
    local exported_versions=0
    local failed_versions=0
    
    # 导出每个版本
    while IFS= read -r version; do
        if [[ -n "$version" ]]; then
            ((version_count++))
            log_debug "导出版本: $secret_name/$version"
            
            local version_file="$secret_export_dir/version_$version.txt"
            local metadata_file="$secret_export_dir/version_${version}_metadata.json"
            
            # 导出密钥值
            if retry_command $RETRY_COUNT $RETRY_INTERVAL gcloud secrets versions access "$version" --secret="$secret_name" --project="$project" > "$version_file" 2>/dev/null; then
                ((exported_versions++))
                log_debug "版本 $version 导出成功"
                
                # 导出版本元数据
                if gcloud secrets versions describe "$version" --secret="$secret_name" --project="$project" --format=json > "$metadata_file" 2>/dev/null; then
                    log_debug "版本 $version 元数据导出成功"
                else
                    log_warning "版本 $version 元数据导出失败"
                fi
            else
                ((failed_versions++))
                log_warning "版本 $version 导出失败"
                # 删除可能创建的空文件
                rm -f "$version_file"
            fi
        fi
    done <<< "$versions"
    
    # 导出密钥元数据
    if gcloud secrets describe "$secret_name" --project="$project" --format=json > "$secret_export_dir/secret_metadata.json" 2>/dev/null; then
        log_debug "密钥 $secret_name 元数据导出成功"
    else
        log_warning "密钥 $secret_name 元数据导出失败"
    fi
    
    # 导出 IAM 策略
    if gcloud secrets get-iam-policy "$secret_name" --project="$project" --format=json > "$secret_export_dir/iam_policy.json" 2>/dev/null; then
        log_debug "密钥 $secret_name IAM 策略导出成功"
    else
        log_debug "密钥 $secret_name 没有自定义 IAM 策略"
        echo '{}' > "$secret_export_dir/iam_policy.json"
    fi
    
    # 创建导出摘要
    local export_summary
    export_summary=$(jq -n \
        --arg secret_name "$secret_name" \
        --argjson total_versions "$version_count" \
        --argjson exported_versions "$exported_versions" \
        --argjson failed_versions "$failed_versions" \
        --arg export_time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            secret_name: $secret_name,
            export_time: $export_time,
            total_versions: $total_versions,
            exported_versions: $exported_versions,
            failed_versions: $failed_versions,
            success_rate: (if $total_versions > 0 then ($exported_versions / $total_versions * 100) else 0 end)
        }')
    
    echo "$export_summary" > "$secret_export_dir/export_summary.json"
    
    if [[ $failed_versions -eq 0 ]]; then
        log_success "密钥 $secret_name 导出完成 ($exported_versions/$version_count 版本)"
        return 0
    else
        log_warning "密钥 $secret_name 部分导出失败 ($exported_versions/$version_count 版本成功)"
        return 1
    fi
}

# 批量导出所有密钥
export_all_secrets() {
    local project=$1
    local secrets_file="$BACKUP_DIR/${project}_secrets_inventory.json"
    
    if [[ ! -f "$secrets_file" ]]; then
        log_error "密钥清单文件不存在: $secrets_file"
        log_error "请先运行 ./02-discover.sh"
        exit 1
    fi
    
    local secret_names
    secret_names=$(jq -r '.[].name | split("/")[-1]' "$secrets_file")
    
    local total_secrets
    total_secrets=$(echo "$secret_names" | wc -l)
    
    if [[ $total_secrets -eq 0 ]]; then
        log_warning "没有发现需要导出的密钥"
        return 0
    fi
    
    log_info "开始批量导出 $total_secrets 个密钥..."
    
    local exported_count=0
    local failed_count=0
    local current=0
    
    # 创建导出日志
    local export_log="$BACKUP_DIR/export_log.json"
    echo "[]" > "$export_log"
    
    while IFS= read -r secret_name; do
        if [[ -n "$secret_name" ]]; then
            ((current++))
            show_progress $current $total_secrets
            
            local start_time
            start_time=$(date +%s)
            
            if export_secret_versions "$project" "$secret_name"; then
                ((exported_count++))
                local status="success"
            else
                ((failed_count++))
                local status="failed"
            fi
            
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            # 记录导出日志
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
            
            jq --argjson entry "$log_entry" '. += [$entry]' "$export_log" > "${export_log}.tmp"
            mv "${export_log}.tmp" "$export_log"
            
            # 批量处理间隔
            if [[ $((current % BATCH_SIZE)) -eq 0 && $current -lt $total_secrets ]]; then
                log_debug "批量处理暂停 2 秒..."
                sleep 2
            fi
        fi
    done <<< "$secret_names"
    
    complete_progress
    
    log_success "导出完成 - 成功: $exported_count, 失败: $failed_count"
    
    # 创建导出清单
    create_export_manifest
    
    # 生成导出报告
    generate_export_report "$exported_count" "$failed_count" "$export_log"
    
    return 0
}

# 创建导出清单
create_export_manifest() {
    local export_manifest="$BACKUP_DIR/export_manifest.json"
    local export_dir="$BACKUP_DIR/exported_secrets"
    
    log_info "创建导出清单..."
    
    local manifest
    manifest=$(find "$export_dir" -type f \( -name "*.txt" -o -name "*.json" \) | jq -R -s '
        split("\n")[:-1] | 
        map(select(length > 0)) |
        map({
            file_path: .,
            file_name: (. | split("/")[-1]),
            secret_name: (. | split("/")[-2]),
            file_type: (if (. | endswith(".txt")) then "secret_data" 
                       elif (. | contains("metadata")) then "metadata"
                       elif (. | contains("iam_policy")) then "iam_policy"
                       elif (. | contains("summary")) then "summary"
                       else "unknown" end),
            file_size: 0
        })
    ')
    
    echo "$manifest" > "$export_manifest"
    
    # 添加文件大小信息
    while IFS= read -r file_path; do
        if [[ -n "$file_path" && -f "$file_path" ]]; then
            local file_size
            file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
            
            jq --arg path "$file_path" --argjson size "$file_size" '
                map(if .file_path == $path then .file_size = $size else . end)
            ' "$export_manifest" > "${export_manifest}.tmp"
            mv "${export_manifest}.tmp" "$export_manifest"
        fi
    done < <(jq -r '.[].file_path' "$export_manifest")
    
    log_success "导出清单创建完成: $export_manifest"
}

# 生成导出报告
generate_export_report() {
    local exported_count=$1
    local failed_count=$2
    local export_log=$3
    local report_file="$BACKUP_DIR/export_report.txt"
    
    log_info "生成导出报告..."
    
    local total_count=$((exported_count + failed_count))
    local success_rate=0
    if [[ $total_count -gt 0 ]]; then
        success_rate=$(echo "scale=2; $exported_count * 100 / $total_count" | bc 2>/dev/null || echo "0")
    fi
    
    # 计算总导出时间
    local total_duration
    total_duration=$(jq '[.[].duration_seconds] | add' "$export_log" 2>/dev/null || echo "0")
    
    # 计算平均导出时间
    local avg_duration=0
    if [[ $total_count -gt 0 ]]; then
        avg_duration=$(echo "scale=2; $total_duration / $total_count" | bc 2>/dev/null || echo "0")
    fi
    
    cat > "$report_file" << EOF
# Secret Manager 导出报告
导出时间: $(date)
源项目: $SOURCE_PROJECT

## 导出统计
成功导出: $exported_count 个密钥
导出失败: $failed_count 个密钥
总计: $total_count 个密钥
成功率: ${success_rate}%

## 性能统计
总导出时间: ${total_duration} 秒
平均导出时间: ${avg_duration} 秒/密钥
批量大小: $BATCH_SIZE

## 导出详情
EOF
    
    # 添加失败的密钥列表
    if [[ $failed_count -gt 0 ]]; then
        echo "" >> "$report_file"
        echo "### 导出失败的密钥" >> "$report_file"
        jq -r '.[] | select(.status == "failed") | "- \(.secret_name)"' "$export_log" >> "$report_file"
    fi
    
    # 添加导出文件统计
    echo "" >> "$report_file"
    echo "### 导出文件统计" >> "$report_file"
    
    local manifest_file="$BACKUP_DIR/export_manifest.json"
    if [[ -f "$manifest_file" ]]; then
        local total_files
        total_files=$(jq length "$manifest_file")
        echo "总文件数: $total_files" >> "$report_file"
        
        local total_size
        total_size=$(jq '[.[].file_size] | add' "$manifest_file")
        echo "总大小: $total_size 字节" >> "$report_file"
        
        echo "" >> "$report_file"
        echo "按类型分布:" >> "$report_file"
        jq -r 'group_by(.file_type) | .[] | "\(.[0].file_type): \(length) 个文件"' "$manifest_file" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## 导出位置
导出目录: $BACKUP_DIR/exported_secrets
清单文件: $BACKUP_DIR/export_manifest.json
日志文件: $export_log

## 验证建议
1. 检查导出清单确认所有文件
2. 验证关键密钥的导出内容
3. 确认 IAM 策略导出完整

## 下一步
1. 检查导出报告和日志
2. 运行导入脚本: ./04-import.sh
3. 验证迁移结果: ./05-verify.sh
EOF
    
    log_success "导出报告生成完成: $report_file"
    echo "$report_file"
}

# 验证导出完整性
verify_export_integrity() {
    local export_dir="$BACKUP_DIR/exported_secrets"
    
    log_info "验证导出完整性..."
    
    local secrets_file="$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json"
    local expected_secrets
    expected_secrets=$(jq -r '.[].name | split("/")[-1]' "$secrets_file")
    
    local verification_results=()
    
    while IFS= read -r secret_name; do
        if [[ -n "$secret_name" ]]; then
            local secret_dir="$export_dir/$secret_name"
            
            if [[ ! -d "$secret_dir" ]]; then
                verification_results+=("❌ $secret_name: 导出目录不存在")
                continue
            fi
            
            # 检查必要文件
            local required_files=("secret_metadata.json" "iam_policy.json" "export_summary.json")
            local missing_files=()
            
            for file in "${required_files[@]}"; do
                if [[ ! -f "$secret_dir/$file" ]]; then
                    missing_files+=("$file")
                fi
            done
            
            # 检查版本文件
            local version_files
            version_files=$(find "$secret_dir" -name "version_*.txt" | wc -l)
            
            if [[ $version_files -eq 0 ]]; then
                missing_files+=("version files")
            fi
            
            if [[ ${#missing_files[@]} -eq 0 ]]; then
                verification_results+=("✅ $secret_name: 完整 ($version_files 个版本)")
            else
                verification_results+=("⚠️  $secret_name: 缺少文件 - ${missing_files[*]}")
            fi
        fi
    done <<< "$expected_secrets"
    
    # 输出验证结果
    echo ""
    log_info "导出完整性验证结果:"
    for result in "${verification_results[@]}"; do
        echo "  $result"
    done
    echo ""
    
    return 0
}

# 更新迁移状态
update_migration_status() {
    local status_file="$BACKUP_DIR/migration_status.json"
    
    if [[ -f "$status_file" ]]; then
        jq '.stages.export = "completed" | .last_updated = now | .export_completed_at = now' "$status_file" > "${status_file}.tmp"
        mv "${status_file}.tmp" "$status_file"
        log_debug "迁移状态已更新"
    fi
}

# 主函数
main() {
    log_info "=== Secret Manager 密钥导出开始 ==="
    
    # 检查环境
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        log_error "未找到迁移状态文件，请先运行 ./01-setup.sh"
        exit 1
    fi
    
    # 检查发现阶段是否完成
    local discovery_status
    discovery_status=$(jq -r '.stages.discover' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
    
    if [[ "$discovery_status" != "completed" ]]; then
        log_error "密钥发现阶段未完成，请先运行 ./02-discover.sh"
        exit 1
    fi
    
    # 1. 批量导出密钥
    log_info "步骤 1: 批量导出密钥"
    export_all_secrets "$SOURCE_PROJECT"
    
    # 2. 验证导出完整性
    log_info "步骤 2: 验证导出完整性"
    verify_export_integrity
    
    # 3. 更新状态
    update_migration_status
    
    log_success "=== Secret Manager 密钥导出完成 ==="
    
    echo ""
    echo "导出结果摘要："
    echo "📁 导出目录: $BACKUP_DIR/exported_secrets"
    echo "📋 导出清单: $BACKUP_DIR/export_manifest.json"
    echo "📊 导出日志: $BACKUP_DIR/export_log.json"
    echo "📄 导出报告: $BACKUP_DIR/export_report.txt"
    echo ""
    echo "下一步："
    echo "1. 查看导出报告: cat $BACKUP_DIR/export_report.txt"
    echo "2. 运行密钥导入: ./04-import.sh"
}

# 执行主函数
main "$@"