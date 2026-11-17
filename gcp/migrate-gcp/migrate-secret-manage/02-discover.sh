#!/bin/bash

# Secret Manager 迁移 - 密钥发现脚本
# 功能：发现和分析源项目中的所有密钥

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 发现所有密钥
discover_secrets() {
    local project=$1
    local output_file="$BACKUP_DIR/${project}_secrets_inventory.json"
    
    log_info "发现项目 $project 中的密钥..."
    
    if ! gcloud secrets list --project="$project" --format=json > "$output_file"; then
        log_error "无法获取项目 $project 的密钥列表"
        return 1
    fi
    
    local secret_count
    secret_count=$(jq length "$output_file")
    log_success "发现 $secret_count 个密钥，保存到: $output_file"
    
    echo "$output_file"
}

# 分析单个密钥的详细信息
analyze_secret_detail() {
    local project=$1
    local secret_name=$2
    
    log_debug "分析密钥: $secret_name"
    
    local secret_info="{}"
    local versions_info="[]"
    local iam_policy="{}"
    
    # 获取密钥基本信息
    if ! secret_info=$(gcloud secrets describe "$secret_name" --project="$project" --format=json 2>/dev/null); then
        log_warning "无法获取密钥 $secret_name 的基本信息"
        secret_info="{\"error\": \"access_denied\"}"
    fi
    
    # 获取版本信息
    if ! versions_info=$(gcloud secrets versions list "$secret_name" --project="$project" --format=json 2>/dev/null); then
        log_warning "无法获取密钥 $secret_name 的版本信息"
        versions_info="[]"
    fi
    
    # 获取 IAM 策略
    if ! iam_policy=$(gcloud secrets get-iam-policy "$secret_name" --project="$project" --format=json 2>/dev/null); then
        log_debug "密钥 $secret_name 没有自定义 IAM 策略"
        iam_policy="{}"
    fi
    
    # 合并信息
    local combined_info
    combined_info=$(jq -n \
        --argjson secret "$secret_info" \
        --argjson versions "$versions_info" \
        --argjson iam "$iam_policy" \
        --arg name "$secret_name" \
        '{
            name: $name,
            secret: $secret,
            versions: $versions,
            iam_policy: $iam,
            analysis: {
                version_count: ($versions | length),
                has_iam_policy: ($iam.bindings != null and ($iam.bindings | length) > 0),
                labels: ($secret.labels // {}),
                replication: ($secret.replication.automatic != null)
            }
        }')
    
    echo "$combined_info"
}

# 批量分析密钥详情
analyze_secrets_details() {
    local project=$1
    local secrets_file=$2
    local details_file="$BACKUP_DIR/${project}_secrets_details.json"
    
    log_info "分析密钥详细信息..."
    
    local secret_names
    secret_names=$(jq -r '.[].name | split("/")[-1]' "$secrets_file")
    
    local total_secrets
    total_secrets=$(echo "$secret_names" | wc -l)
    
    if [[ $total_secrets -eq 0 ]]; then
        log_warning "没有发现任何密钥"
        echo "[]" > "$details_file"
        echo "$details_file"
        return 0
    fi
    
    log_info "开始分析 $total_secrets 个密钥的详细信息..."
    
    echo "[]" > "$details_file"
    
    local current=0
    while IFS= read -r secret_name; do
        if [[ -n "$secret_name" ]]; then
            ((current++))
            show_progress $current $total_secrets
            
            local secret_detail
            if secret_detail=$(analyze_secret_detail "$project" "$secret_name"); then
                # 添加到详情文件
                jq --argjson new_secret "$secret_detail" '. += [$new_secret]' "$details_file" > "${details_file}.tmp"
                mv "${details_file}.tmp" "$details_file"
            else
                log_warning "跳过密钥 $secret_name（分析失败）"
            fi
        fi
    done <<< "$secret_names"
    
    complete_progress
    log_success "密钥详情分析完成: $details_file"
    echo "$details_file"
}

# 生成密钥统计报告
generate_statistics_report() {
    local details_file=$1
    local stats_file="$BACKUP_DIR/secrets_statistics.json"
    
    log_info "生成密钥统计信息..."
    
    local stats
    stats=$(jq '{
        total_secrets: length,
        secrets_with_iam: [.[] | select(.analysis.has_iam_policy)] | length,
        secrets_with_labels: [.[] | select(.analysis.labels | length > 0)] | length,
        automatic_replication: [.[] | select(.analysis.replication)] | length,
        total_versions: [.[].analysis.version_count] | add,
        version_distribution: [.[].analysis.version_count] | group_by(.) | map({versions: .[0], count: length}),
        label_summary: [.[].analysis.labels | to_entries[]] | group_by(.key) | map({label: .[0].key, count: length, values: [.[].value] | unique}),
        secrets_by_version_count: {
            single_version: [.[] | select(.analysis.version_count == 1)] | length,
            multiple_versions: [.[] | select(.analysis.version_count > 1)] | length,
            max_versions: [.[].analysis.version_count] | max
        }
    }' "$details_file")
    
    echo "$stats" > "$stats_file"
    
    log_success "统计信息生成完成: $stats_file"
    echo "$stats_file"
}

# 生成迁移分析报告
generate_migration_analysis() {
    local secrets_file=$1
    local details_file=$2
    local stats_file=$3
    local report_file="$BACKUP_DIR/migration_analysis_report.txt"
    
    log_info "生成迁移分析报告..."
    
    local total_secrets
    total_secrets=$(jq length "$secrets_file")
    
    local total_versions
    total_versions=$(jq '.total_versions // 0' "$stats_file")
    
    local secrets_with_iam
    secrets_with_iam=$(jq '.secrets_with_iam // 0' "$stats_file")
    
    local secrets_with_labels
    secrets_with_labels=$(jq '.secrets_with_labels // 0' "$stats_file")
    
    cat > "$report_file" << EOF
# Secret Manager 迁移分析报告
生成时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 密钥概览
总密钥数量: $total_secrets
总版本数量: $total_versions
平均版本数: $(echo "scale=2; $total_versions / $total_secrets" | bc 2>/dev/null || echo "N/A")

## 权限分析
有自定义 IAM 策略的密钥: $secrets_with_iam
有标签的密钥: $secrets_with_labels

## 版本分布
EOF
    
    # 版本分布详情
    jq -r '.version_distribution[] | "  \(.versions) 个版本: \(.count) 个密钥"' "$stats_file" >> "$report_file"
    
    cat >> "$report_file" << EOF

## 标签统计
EOF
    
    # 标签统计
    if [[ $(jq '.label_summary | length' "$stats_file") -gt 0 ]]; then
        jq -r '.label_summary[] | "  \(.label): \(.count) 个密钥, 值: \(.values | join(", "))"' "$stats_file" >> "$report_file"
    else
        echo "  无标签" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## 复制策略
自动复制: $(jq '.automatic_replication' "$stats_file") 个密钥
用户管理复制: $((total_secrets - $(jq '.automatic_replication' "$stats_file"))) 个密钥

## 迁移复杂度评估
EOF
    
    # 评估迁移复杂度
    local complexity="简单"
    if [[ $total_secrets -gt 100 ]]; then
        complexity="中等"
    fi
    if [[ $total_secrets -gt 500 ]]; then
        complexity="复杂"
    fi
    if [[ $secrets_with_iam -gt $((total_secrets / 2)) ]]; then
        complexity="复杂"
    fi
    
    cat >> "$report_file" << EOF
复杂度: $complexity

评估依据:
- 密钥数量: $total_secrets $(if [[ $total_secrets -gt 100 ]]; then echo "(大量)"; else echo "(适中)"; fi)
- IAM 策略: $secrets_with_iam $(if [[ $secrets_with_iam -gt $((total_secrets / 2)) ]]; then echo "(复杂)"; else echo "(简单)"; fi)
- 版本数量: $total_versions $(if [[ $total_versions -gt $((total_secrets * 3)) ]]; then echo "(多版本)"; else echo "(标准)"; fi)

## 预估迁移时间
EOF
    
    # 预估迁移时间
    local estimated_minutes=$((total_secrets / 10 + total_versions / 50))
    if [[ $estimated_minutes -lt 5 ]]; then
        estimated_minutes=5
    fi
    
    echo "预估时间: $estimated_minutes 分钟" >> "$report_file"
    echo "建议批量大小: $BATCH_SIZE" >> "$report_file"
    
    cat >> "$report_file" << EOF

## 潜在问题
EOF
    
    # 识别潜在问题
    local issues=()
    
    if [[ $secrets_with_iam -gt 0 ]]; then
        issues+=("- $secrets_with_iam 个密钥有自定义 IAM 策略，需要验证目标项目权限")
    fi
    
    local max_versions
    max_versions=$(jq '.secrets_by_version_count.max_versions // 0' "$stats_file")
    if [[ $max_versions -gt 10 ]]; then
        issues+=("- 存在版本数量较多的密钥（最多 $max_versions 个版本），可能影响迁移速度")
    fi
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "  无明显问题" >> "$report_file"
    else
        for issue in "${issues[@]}"; do
            echo "$issue" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## 建议
1. 在低峰期执行迁移
2. 分批处理密钥以避免 API 限制
3. 验证目标项目的 IAM 权限配置
4. 准备应用程序配置更新计划

## 下一步
1. 检查此报告
2. 运行导出脚本: ./03-export.sh
3. 运行导入脚本: ./04-import.sh
EOF
    
    log_success "迁移分析报告生成完成: $report_file"
    echo "$report_file"
}

# 检查目标项目现有密钥
check_target_project_conflicts() {
    local target_secrets_file="$BACKUP_DIR/${TARGET_PROJECT}_existing_secrets.json"
    
    log_info "检查目标项目现有密钥..."
    
    if ! gcloud secrets list --project="$TARGET_PROJECT" --format=json > "$target_secrets_file"; then
        log_error "无法获取目标项目密钥列表"
        return 1
    fi
    
    local existing_count
    existing_count=$(jq length "$target_secrets_file")
    
    if [[ $existing_count -gt 0 ]]; then
        log_warning "目标项目已存在 $existing_count 个密钥"
        
        # 检查名称冲突
        local source_secrets_file="$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json"
        local conflicts
        conflicts=$(jq -r --slurpfile target "$target_secrets_file" '
            [.[].name | split("/")[-1]] as $source |
            [$target[0][].name | split("/")[-1]] as $target_names |
            $source | map(select(. as $item | $target_names | index($item))) | .[]
        ' "$source_secrets_file" 2>/dev/null || echo "")
        
        if [[ -n "$conflicts" ]]; then
            log_warning "发现名称冲突的密钥:"
            echo "$conflicts" | while read -r conflict; do
                if [[ -n "$conflict" ]]; then
                    log_warning "  - $conflict"
                fi
            done
            
            echo ""
            read -p "目标项目存在同名密钥，继续将会覆盖现有密钥。是否继续？(y/n): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "用户取消操作"
                return 1
            fi
        fi
    else
        log_success "目标项目无现有密钥，无冲突"
    fi
    
    return 0
}

# 更新迁移状态
update_migration_status() {
    local status_file="$BACKUP_DIR/migration_status.json"
    
    if [[ -f "$status_file" ]]; then
        jq '.stages.discover = "completed" | .last_updated = now | .discovery_completed_at = now' "$status_file" > "${status_file}.tmp"
        mv "${status_file}.tmp" "$status_file"
        log_debug "迁移状态已更新"
    fi
}

# 主函数
main() {
    log_info "=== Secret Manager 密钥发现开始 ==="
    
    # 检查环境
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        log_error "未找到迁移状态文件，请先运行 ./01-setup.sh"
        exit 1
    fi
    
    # 1. 发现源项目密钥
    log_info "步骤 1: 发现源项目密钥"
    local secrets_file
    secrets_file=$(discover_secrets "$SOURCE_PROJECT")
    
    # 2. 分析密钥详情
    log_info "步骤 2: 分析密钥详细信息"
    local details_file
    details_file=$(analyze_secrets_details "$SOURCE_PROJECT" "$secrets_file")
    
    # 3. 生成统计信息
    log_info "步骤 3: 生成统计信息"
    local stats_file
    stats_file=$(generate_statistics_report "$details_file")
    
    # 4. 检查目标项目冲突
    log_info "步骤 4: 检查目标项目冲突"
    check_target_project_conflicts
    
    # 5. 生成分析报告
    log_info "步骤 5: 生成迁移分析报告"
    local report_file
    report_file=$(generate_migration_analysis "$secrets_file" "$details_file" "$stats_file")
    
    # 6. 更新状态
    update_migration_status
    
    log_success "=== Secret Manager 密钥发现完成 ==="
    
    echo ""
    echo "发现结果摘要："
    echo "📊 密钥清单: $secrets_file"
    echo "📋 详细信息: $details_file"
    echo "📈 统计数据: $stats_file"
    echo "📄 分析报告: $report_file"
    echo ""
    echo "下一步："
    echo "1. 查看分析报告: cat $report_file"
    echo "2. 运行密钥导出: ./03-export.sh"
}

# 执行主函数
main "$@"