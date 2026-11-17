# Shell Scripts Collection

Generated on: 2025-09-01 14:48:56
Directory: /Users/lex/git/knowledge/gcp/migrate-gcp/migrate-secret-manage

## `01-setup.sh`

```bash
#!/bin/bash

# Secret Manager 迁移 - 环境准备脚本
# 功能：检查环境、验证权限、准备迁移环境

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 检查必要的 IAM 权限
check_iam_permissions() {
    local project=$1
    local required_roles=(
        "roles/secretmanager.admin"
        "roles/iam.securityReviewer"
    )
    
    log_info "检查项目 $project 的 IAM 权限..."
    
    local current_user
    current_user=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    
    if [[ -z "$current_user" ]]; then
        log_error "无法获取当前认证用户"
        return 1
    fi
    
    log_info "当前用户: $current_user"
    
    # 获取用户的 IAM 策略
    local user_roles
    user_roles=$(gcloud projects get-iam-policy "$project" --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:$current_user" 2>/dev/null || echo "")
    
    local missing_roles=()
    for role in "${required_roles[@]}"; do
        if ! echo "$user_roles" | grep -q "$role"; then
            missing_roles+=("$role")
        fi
    done
    
    if [[ ${#missing_roles[@]} -gt 0 ]]; then
        log_warning "缺少以下权限："
        for role in "${missing_roles[@]}"; do
            log_warning "  - $role"
        done
        
        echo ""
        echo "请联系项目管理员添加权限，或运行以下命令："
        for role in "${missing_roles[@]}"; do
            echo "gcloud projects add-iam-policy-binding $project \\"
            echo "  --member=\"user:$current_user\" \\"
            echo "  --role=\"$role\""
        done
        
        read -p "是否继续？权限不足可能导致迁移失败 (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        log_success "权限检查通过: $project"
    fi
    
    return 0
}

# 检查项目配额
check_project_quotas() {
    local project=$1
    
    log_info "检查项目 $project 的配额..."
    
    # 检查 Secret Manager 配额
    local secret_count
    secret_count=$(gcloud secrets list --project="$project" --format="value(name)" | wc -l)
    
    log_info "当前密钥数量: $secret_count"
    
    # Secret Manager 默认配额通常很高，这里主要是信息展示
    if [[ $secret_count -gt 1000 ]]; then
        log_warning "密钥数量较多 ($secret_count)，迁移可能需要较长时间"
    fi
    
    return 0
}

# 创建迁移环境
setup_migration_environment() {
    log_info "设置迁移环境..."
    
    # 创建必要目录
    setup_directories
    
    # 创建迁移状态文件
    local status_file="$BACKUP_DIR/migration_status.json"
    cat > "$status_file" << EOF
{
    "migration_id": "$(date +%Y%m%d_%H%M%S)",
    "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "source_project": "$SOURCE_PROJECT",
    "target_project": "$TARGET_PROJECT",
    "status": "initialized",
    "stages": {
        "setup": "completed",
        "discover": "pending",
        "export": "pending",
        "import": "pending",
        "verify": "pending",
        "update": "pending"
    }
}
EOF
    
    log_success "迁移状态文件创建: $status_file"
    
    # 创建配置备份
    cp "$SCRIPT_DIR/config.sh" "$BACKUP_DIR/config_backup.sh"
    log_success "配置文件已备份"
    
    return 0
}

# 测试 Secret Manager 连接
test_secret_manager_connection() {
    local project=$1
    
    log_info "测试 Secret Manager 连接: $project"
    
    # 尝试列出密钥（限制数量以加快速度）
    if gcloud secrets list --project="$project" --limit=1 &>/dev/null; then
        log_success "Secret Manager 连接正常: $project"
    else
        log_error "Secret Manager 连接失败: $project"
        return 1
    fi
    
    return 0
}

# 检查网络连接
check_network_connectivity() {
    log_info "检查网络连接..."
    
    local endpoints=(
        "secretmanager.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if curl -s --max-time 5 "https://$endpoint" >/dev/null 2>&1; then
            log_success "网络连接正常: $endpoint"
        else
            log_warning "网络连接可能有问题: $endpoint"
        fi
    done
    
    return 0
}

# 生成环境报告
generate_environment_report() {
    local report_file="$BACKUP_DIR/environment_report.txt"
    
    log_info "生成环境报告..."
    
    cat > "$report_file" << EOF
# Secret Manager 迁移环境报告
生成时间: $(date)
迁移ID: $(jq -r '.migration_id' "$BACKUP_DIR/migration_status.json")

## 基本信息
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT
执行用户: $(gcloud auth list --filter=status:ACTIVE --format="value(account)")
gcloud 版本: $(gcloud version --format="value(Google Cloud SDK)")

## 工具版本
EOF
    
    echo "gcloud: $(gcloud version --format="value(Google Cloud SDK)" | head -1)" >> "$report_file"
    echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo "未安装")" >> "$report_file"
    echo "jq: $(jq --version 2>/dev/null || echo "未安装")" >> "$report_file"
    
    cat >> "$report_file" << EOF

## 项目信息
### 源项目 ($SOURCE_PROJECT)
EOF
    
    # 源项目信息
    gcloud projects describe "$SOURCE_PROJECT" --format="value(name,projectNumber,lifecycleState)" >> "$report_file" 2>/dev/null || echo "无法获取项目信息" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "密钥数量: $(gcloud secrets list --project="$SOURCE_PROJECT" --format="value(name)" | wc -l)" >> "$report_file"
    
    cat >> "$report_file" << EOF

### 目标项目 ($TARGET_PROJECT)
EOF
    
    # 目标项目信息
    gcloud projects describe "$TARGET_PROJECT" --format="value(name,projectNumber,lifecycleState)" >> "$report_file" 2>/dev/null || echo "无法获取项目信息" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "密钥数量: $(gcloud secrets list --project="$TARGET_PROJECT" --format="value(name)" | wc -l)" >> "$report_file"
    
    cat >> "$report_file" << EOF

## 配置信息
批量大小: $BATCH_SIZE
重试次数: $RETRY_COUNT
验证密钥值: $VERIFY_SECRET_VALUES
调试模式: $DEBUG

## 备份目录
$BACKUP_DIR

## 下一步
1. 检查环境报告
2. 运行密钥发现: ./02-discover.sh
3. 导出密钥: ./03-export.sh
EOF
    
    log_success "环境报告生成完成: $report_file"
    echo "$report_file"
}

# 主函数
main() {
    log_info "=== Secret Manager 迁移环境准备开始 ==="
    
    # 1. 基础检查
    log_info "步骤 1: 基础环境检查"
    check_prerequisites
    validate_config
    
    # 2. 项目访问验证
    log_info "步骤 2: 项目访问验证"
    verify_project_access "$SOURCE_PROJECT"
    verify_project_access "$TARGET_PROJECT"
    
    # 3. API 检查
    log_info "步骤 3: Secret Manager API 检查"
    check_secret_manager_api "$SOURCE_PROJECT"
    check_secret_manager_api "$TARGET_PROJECT"
    
    # 4. 权限检查
    log_info "步骤 4: IAM 权限检查"
    check_iam_permissions "$SOURCE_PROJECT"
    check_iam_permissions "$TARGET_PROJECT"
    
    # 5. 配额检查
    log_info "步骤 5: 项目配额检查"
    check_project_quotas "$SOURCE_PROJECT"
    check_project_quotas "$TARGET_PROJECT"
    
    # 6. 连接测试
    log_info "步骤 6: 服务连接测试"
    test_secret_manager_connection "$SOURCE_PROJECT"
    test_secret_manager_connection "$TARGET_PROJECT"
    check_network_connectivity
    
    # 7. 环境设置
    log_info "步骤 7: 迁移环境设置"
    setup_migration_environment
    
    # 8. 生成报告
    log_info "步骤 8: 生成环境报告"
    local report_file
    report_file=$(generate_environment_report)
    
    log_success "=== Secret Manager 迁移环境准备完成 ==="
    
    echo ""
    echo "环境准备摘要："
    echo "✅ 基础工具检查通过"
    echo "✅ 项目访问验证通过"
    echo "✅ Secret Manager API 已启用"
    echo "✅ 迁移环境已设置"
    echo ""
    echo "备份目录: $BACKUP_DIR"
    echo "环境报告: $report_file"
    echo ""
    echo "下一步："
    echo "1. 查看环境报告: cat $report_file"
    echo "2. 运行密钥发现: ./02-discover.sh"
}

# 执行主函数
main "$@"
```

## `02-discover.sh`

```bash
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
```

## `03-export.sh`

```bash
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
```

## `04-import.sh`

```bash
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
```

## `05-verify.sh`

```bash
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
```

## `06-update-apps.sh`

```bash
#!/bin/bash

# Secret Manager 迁移 - 应用配置更新脚本
# 功能：更新应用程序配置以使用新项目的密钥

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 更新 Kubernetes 部署中的项目引用
update_k8s_deployments() {
    local namespace=$1
    
    log_info "更新 Kubernetes 命名空间 $namespace 中的 Secret Manager 项目引用..."
    
    # 检查命名空间是否存在
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log_warning "命名空间 $namespace 不存在，跳过"
        return 0
    fi
    
    # 获取所有部署
    local deployments
    deployments=$(kubectl get deployments -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [[ -z "$deployments" ]]; then
        log_info "命名空间 $namespace 中没有部署"
        return 0
    fi
    
    local updated_count=0
    local skipped_count=0
    
    while IFS= read -r deployment; do
        if [[ -n "$deployment" ]]; then
            log_debug "检查部署: $deployment"
            
            # 获取部署配置
            local deployment_yaml
            deployment_yaml=$(kubectl get "$deployment" -n "$namespace" -o yaml)
            
            # 检查是否包含源项目引用
            if echo "$deployment_yaml" | grep -q "projects/$SOURCE_PROJECT/secrets"; then
                log_info "发现项目引用，准备更新: $deployment"
                
                # 创建备份
                local backup_file="$BACKUP_DIR/k8s_backups/$(echo "${namespace}_${deployment}" | tr '/' '_').yaml"
                mkdir -p "$(dirname "$backup_file")"
                echo "$deployment_yaml" > "$backup_file"
                
                # 更新项目引用
                local updated_yaml
                updated_yaml=$(echo "$deployment_yaml" | sed "s|projects/$SOURCE_PROJECT/secrets|projects/$TARGET_PROJECT/secrets|g")
                
                # 应用更新
                if echo "$updated_yaml" | kubectl apply -f -; then
                    log_success "部署更新成功: $deployment"
                    ((updated_count++))
                else
                    log_error "部署更新失败: $deployment"
                    log_info "可以从备份恢复: kubectl apply -f $backup_file"
                fi
            else
                log_debug "部署无需更新: $deployment"
                ((skipped_count++))
            fi
        fi
    done <<< "$deployments"
    
    log_info "命名空间 $namespace 更新完成 - 更新: $updated_count, 跳过: $skipped_count"
}

# 更新 ConfigMaps 中的项目引用
update_k8s_configmaps() {
    local namespace=$1
    
    log_info "更新 Kubernetes 命名空间 $namespace 中的 ConfigMaps..."
    
    # 获取所有 ConfigMaps
    local configmaps
    configmaps=$(kubectl get configmaps -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [[ -z "$configmaps" ]]; then
        log_info "命名空间 $namespace 中没有 ConfigMaps"
        return 0
    fi
    
    local updated_count=0
    local skipped_count=0
    
    while IFS= read -r configmap; do
        if [[ -n "$configmap" ]]; then
            log_debug "检查 ConfigMap: $configmap"
            
            # 获取 ConfigMap 配置
            local configmap_yaml
            configmap_yaml=$(kubectl get "$configmap" -n "$namespace" -o yaml)
            
            # 检查是否包含源项目引用
            if echo "$configmap_yaml" | grep -q "$SOURCE_PROJECT"; then
                log_info "发现项目引用，准备更新: $configmap"
                
                # 创建备份
                local backup_file="$BACKUP_DIR/k8s_backups/$(echo "${namespace}_${configmap}" | tr '/' '_').yaml"
                mkdir -p "$(dirname "$backup_file")"
                echo "$configmap_yaml" > "$backup_file"
                
                # 更新项目引用
                local updated_yaml
                updated_yaml=$(echo "$configmap_yaml" | sed "s|$SOURCE_PROJECT|$TARGET_PROJECT|g")
                
                # 应用更新
                if echo "$updated_yaml" | kubectl apply -f -; then
                    log_success "ConfigMap 更新成功: $configmap"
                    ((updated_count++))
                else
                    log_error "ConfigMap 更新失败: $configmap"
                    log_info "可以从备份恢复: kubectl apply -f $backup_file"
                fi
            else
                log_debug "ConfigMap 无需更新: $configmap"
                ((skipped_count++))
            fi
        fi
    done <<< "$configmaps"
    
    log_info "ConfigMaps 更新完成 - 更新: $updated_count, 跳过: $skipped_count"
}

# 扫描并更新配置文件
scan_and_update_config_files() {
    local search_dir=${1:-.}
    
    log_info "扫描目录 $search_dir 中的配置文件..."
    
    local updated_files=()
    local total_files=0
    
    # 扫描配置文件
    for pattern in "${CONFIG_FILE_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            ((total_files++))
            
            if [[ -f "$file" ]]; then
                log_debug "检查文件: $file"
                
                # 检查文件是否包含源项目引用
                if grep -q "$SOURCE_PROJECT" "$file" 2>/dev/null; then
                    log_info "发现项目引用，准备更新: $file"
                    
                    # 创建备份
                    local backup_file="$BACKUP_DIR/config_backups/$(echo "$file" | tr '/' '_').bak"
                    mkdir -p "$(dirname "$backup_file")"
                    cp "$file" "$backup_file"
                    
                    # 更新文件内容
                    if sed -i.tmp "s|$SOURCE_PROJECT|$TARGET_PROJECT|g" "$file" && rm -f "${file}.tmp"; then
                        log_success "文件更新成功: $file"
                        updated_files+=("$file")
                    else
                        log_error "文件更新失败: $file"
                        log_info "可以从备份恢复: cp $backup_file $file"
                    fi
                fi
            fi
        done < <(find "$search_dir" -name "$pattern" -type f -print0 2>/dev/null)
    done
    
    log_info "配置文件扫描完成 - 总计: $total_files, 更新: ${#updated_files[@]}"
    
    # 生成更新文件列表
    if [[ ${#updated_files[@]} -gt 0 ]]; then
        local updated_files_list="$BACKUP_DIR/updated_config_files.txt"
        printf '%s\n' "${updated_files[@]}" > "$updated_files_list"
        log_success "更新文件列表: $updated_files_list"
    fi
}

# 生成环境变量更新指南
generate_env_update_guide() {
    local guide_file="$BACKUP_DIR/environment_variables_update_guide.txt"
    
    log_info "生成环境变量更新指南..."
    
    cat > "$guide_file" << EOF
# 环境变量更新指南
更新时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 需要更新的环境变量模式

### 1. 直接项目引用
旧值: projects/$SOURCE_PROJECT/secrets/secret-name/versions/latest
新值: projects/$TARGET_PROJECT/secrets/secret-name/versions/latest

### 2. 项目ID环境变量
旧值: GCP_PROJECT=$SOURCE_PROJECT
新值: GCP_PROJECT=$TARGET_PROJECT

旧值: GOOGLE_CLOUD_PROJECT=$SOURCE_PROJECT
新值: GOOGLE_CLOUD_PROJECT=$TARGET_PROJECT

### 3. Secret Manager 客户端配置
确保应用程序使用正确的项目ID初始化 Secret Manager 客户端

## 常见配置文件位置
- Kubernetes Deployments 和 ConfigMaps
- Docker Compose 文件 (docker-compose.yml)
- 应用程序配置文件 (.env, config.json, application.yml)
- CI/CD 管道配置 (.github/workflows/, .gitlab-ci.yml)
- Terraform 变量文件 (*.tf, *.tfvars)
- Helm Charts (values.yaml, templates/)

## 验证命令

### Kubernetes 环境
# 检查 Deployments
kubectl get deployments -A -o yaml | grep -i "$SOURCE_PROJECT"

# 检查 ConfigMaps
kubectl get configmaps -A -o yaml | grep -i "$SOURCE_PROJECT"

# 检查 Secrets
kubectl get secrets -A -o yaml | grep -i "$SOURCE_PROJECT"

### 本地环境
# 检查环境变量
env | grep -i "$SOURCE_PROJECT"

# 检查配置文件
grep -r "$SOURCE_PROJECT" . --include="*.yaml" --include="*.yml" --include="*.json" --include="*.env"

## 应用程序代码更新

### Python 示例
\`\`\`python
# 旧代码
from google.cloud import secretmanager
client = secretmanager.SecretManagerServiceClient()
name = f"projects/$SOURCE_PROJECT/secrets/my-secret/versions/latest"

# 新代码
from google.cloud import secretmanager
client = secretmanager.SecretManagerServiceClient()
name = f"projects/$TARGET_PROJECT/secrets/my-secret/versions/latest"
\`\`\`

### Node.js 示例
\`\`\`javascript
// 旧代码
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');
const client = new SecretManagerServiceClient();
const name = \`projects/$SOURCE_PROJECT/secrets/my-secret/versions/latest\`;

// 新代码
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');
const client = new SecretManagerServiceClient();
const name = \`projects/$TARGET_PROJECT/secrets/my-secret/versions/latest\`;
\`\`\`

### Go 示例
\`\`\`go
// 旧代码
name := "projects/$SOURCE_PROJECT/secrets/my-secret/versions/latest"

// 新代码
name := "projects/$TARGET_PROJECT/secrets/my-secret/versions/latest"
\`\`\`

## 测试验证

### 1. 功能测试
- 验证应用程序能够正常启动
- 测试所有依赖密钥的功能
- 检查日志中是否有错误信息

### 2. 连接测试
\`\`\`bash
# 测试密钥访问
gcloud secrets versions access latest --secret="my-secret" --project=$TARGET_PROJECT
\`\`\`

### 3. 监控检查
- 检查应用程序监控指标
- 验证错误率没有增加
- 确认性能指标正常

## 回滚计划

如果更新后出现问题，可以快速回滚：

### Kubernetes 回滚
\`\`\`bash
# 恢复 Deployment
kubectl apply -f $BACKUP_DIR/k8s_backups/

# 或使用 kubectl rollout
kubectl rollout undo deployment/my-app -n my-namespace
\`\`\`

### 配置文件回滚
\`\`\`bash
# 恢复配置文件
cp $BACKUP_DIR/config_backups/* /path/to/original/location/
\`\`\`

## 注意事项

1. **分批更新**: 建议分批更新应用程序，先更新非关键服务
2. **监控观察**: 更新后密切监控应用程序状态
3. **备份保留**: 保留所有备份文件直到确认迁移成功
4. **团队通知**: 及时通知相关团队配置更改
5. **文档更新**: 更新相关文档和运维手册

## 常见问题

### Q: 应用程序报告"权限被拒绝"错误
A: 检查目标项目中的 IAM 权限配置，确保服务账户有访问密钥的权限

### Q: 某些密钥无法访问
A: 验证密钥是否已成功迁移，检查密钥名称是否正确

### Q: 性能下降
A: 检查网络配置，确保应用程序能够高效访问新项目的 Secret Manager

EOF
    
    log_success "环境变量更新指南生成完成: $guide_file"
    echo "$guide_file"
}

# 生成应用切换检查清单
generate_app_switch_checklist() {
    local checklist_file="$BACKUP_DIR/app_switch_checklist.md"
    
    log_info "生成应用切换检查清单..."
    
    cat > "$checklist_file" << EOF
# 应用切换检查清单

## 迁移前检查
- [ ] 所有密钥已成功迁移到目标项目
- [ ] 密钥验证通过 (运行 ./05-verify.sh)
- [ ] 应用程序配置已更新
- [ ] 备份文件已创建
- [ ] 团队成员已通知

## 切换准备
- [ ] 选择合适的维护窗口
- [ ] 准备回滚计划
- [ ] 设置监控和告警
- [ ] 准备应急联系方式

## 切换步骤

### 1. Kubernetes 应用更新
- [ ] 更新 Deployments 中的项目引用
- [ ] 更新 ConfigMaps 中的配置
- [ ] 更新 Secrets 中的引用
- [ ] 验证 Pod 重启正常

### 2. 环境变量更新
- [ ] 更新系统环境变量
- [ ] 更新应用程序配置文件
- [ ] 更新 CI/CD 管道配置
- [ ] 更新 Docker 镜像配置

### 3. 应用程序代码更新
- [ ] 更新硬编码的项目ID
- [ ] 更新 Secret Manager 客户端配置
- [ ] 重新构建和部署应用程序
- [ ] 验证代码更改

### 4. 基础设施更新
- [ ] 更新 Terraform 配置
- [ ] 更新 Helm Charts
- [ ] 更新 Ansible Playbooks
- [ ] 更新其他 IaC 工具配置

## 切换后验证

### 应用程序验证
- [ ] 应用程序正常启动
- [ ] 所有服务健康检查通过
- [ ] 可以正常访问密钥
- [ ] 所有功能正常工作
- [ ] 日志无错误信息

### 性能验证
- [ ] 响应时间正常
- [ ] 吞吐量无明显下降
- [ ] 错误率在正常范围内
- [ ] 资源使用率正常

### 安全验证
- [ ] IAM 权限配置正确
- [ ] 密钥访问权限正常
- [ ] 审计日志记录正常
- [ ] 安全扫描无异常

## 监控检查
- [ ] 应用程序监控正常
- [ ] 基础设施监控正常
- [ ] 告警规则工作正常
- [ ] 日志收集正常

## 回滚计划

如果出现问题，按以下顺序执行回滚：

### 紧急回滚 (5分钟内)
1. **Kubernetes 回滚**
   \`\`\`bash
   kubectl apply -f $BACKUP_DIR/k8s_backups/
   \`\`\`

2. **配置文件回滚**
   \`\`\`bash
   # 恢复配置文件
   find $BACKUP_DIR/config_backups/ -name "*.bak" -exec bash -c 'cp "\$1" "\${1%.bak}"' _ {} \\;
   \`\`\`

3. **重启应用程序**
   \`\`\`bash
   kubectl rollout restart deployment/my-app -n my-namespace
   \`\`\`

### 完整回滚 (15分钟内)
1. 执行紧急回滚步骤
2. 恢复环境变量配置
3. 重新部署应用程序
4. 验证功能恢复

## 清理步骤（迁移成功后）

### 立即清理
- [ ] 验证所有应用程序正常运行 24 小时
- [ ] 确认无用户投诉或问题报告
- [ ] 检查监控指标稳定

### 1周后清理
- [ ] 删除源项目中的密钥（可选）
- [ ] 清理备份文件
- [ ] 更新文档和运维手册
- [ ] 归档迁移记录

### 1个月后清理
- [ ] 删除迁移相关的临时资源
- [ ] 清理旧的监控配置
- [ ] 更新灾难恢复计划

## 联系信息

### 技术团队
- 迁移负责人: _______________
- 应用开发团队: _______________
- 运维团队: _______________
- 安全团队: _______________

### 紧急联系
- 技术支持: _______________
- 值班电话: _______________
- 管理层联系: _______________

## 成功标准

### 技术指标
- [ ] 应用程序可用性 > 99.9%
- [ ] 响应时间无明显增加 (< 10% 增长)
- [ ] 错误率 < 0.1%
- [ ] 所有功能测试通过

### 业务指标
- [ ] 用户投诉数量无增加
- [ ] 业务功能正常
- [ ] 数据完整性保持
- [ ] 合规要求满足

## 经验教训记录

### 成功经验
- 记录迁移过程中的成功做法
- 总结有效的工具和方法
- 记录团队协作亮点

### 改进建议
- 记录遇到的问题和解决方案
- 提出流程改进建议
- 更新迁移最佳实践

---

**注意**: 此检查清单应根据具体应用程序和环境进行调整。建议在测试环境先完整执行一遍。
EOF
    
    log_success "应用切换检查清单生成完成: $checklist_file"
    echo "$checklist_file"
}

# 生成更新报告
generate_update_report() {
    local report_file="$BACKUP_DIR/app_update_report.txt"
    
    log_info "生成应用更新报告..."
    
    cat > "$report_file" << EOF
# 应用配置更新报告
更新时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 更新摘要
EOF
    
    # 统计 Kubernetes 更新
    local k8s_backups
    k8s_backups=$(find "$BACKUP_DIR/k8s_backups" -name "*.yaml" 2>/dev/null | wc -l || echo "0")
    echo "Kubernetes 资源更新: $k8s_backups 个文件" >> "$report_file"
    
    # 统计配置文件更新
    local config_backups
    config_backups=$(find "$BACKUP_DIR/config_backups" -name "*.bak" 2>/dev/null | wc -l || echo "0")
    echo "配置文件更新: $config_backups 个文件" >> "$report_file"
    
    cat >> "$report_file" << EOF

## 备份位置
Kubernetes 备份: $BACKUP_DIR/k8s_backups/
配置文件备份: $BACKUP_DIR/config_backups/

## 生成的指南
环境变量更新指南: $BACKUP_DIR/environment_variables_update_guide.txt
应用切换检查清单: $BACKUP_DIR/app_switch_checklist.md

## 验证建议
1. 检查所有更新的资源是否正常运行
2. 验证应用程序能够访问新项目的密钥
3. 监控应用程序日志和性能指标
4. 进行功能测试确保所有特性正常

## 回滚信息
如需回滚，请使用备份目录中的文件：
- Kubernetes: kubectl apply -f $BACKUP_DIR/k8s_backups/
- 配置文件: 从 $BACKUP_DIR/config_backups/ 恢复

## 后续步骤
1. 验证应用程序功能
2. 监控系统稳定性
3. 完成应用切换检查清单
4. 考虑清理源项目资源
EOF
    
    log_success "应用更新报告生成完成: $report_file"
    echo "$report_file"
}

# 更新迁移状态
update_migration_status() {
    local status_file="$BACKUP_DIR/migration_status.json"
    
    if [[ -f "$status_file" ]]; then
        jq '.stages.update = "completed" | .last_updated = now | .update_completed_at = now' "$status_file" > "${status_file}.tmp"
        mv "${status_file}.tmp" "$status_file"
        log_debug "迁移状态已更新"
    fi
}

# 主函数
main() {
    log_info "=== Secret Manager 应用配置更新开始 ==="
    
    # 检查环境
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        log_error "未找到迁移状态文件，请先运行 ./01-setup.sh"
        exit 1
    fi
    
    # 检查验证阶段是否完成
    local verify_status
    verify_status=$(jq -r '.stages.verify' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
    
    if [[ "$verify_status" != "completed" ]]; then
        log_warning "密钥验证阶段未完成，建议先运行 ./05-verify.sh"
        read -p "是否继续应用配置更新？(y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "用户取消操作"
            exit 0
        fi
    fi
    
    # 1. 更新 Kubernetes 资源
    log_info "步骤 1: 更新 Kubernetes 资源"
    
    # 检查是否有 kubectl 访问权限
    if kubectl version --client &>/dev/null; then
        read -p "是否更新 Kubernetes 部署中的项目引用？(y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for namespace in "${K8S_NAMESPACES[@]}"; do
                log_info "处理命名空间: $namespace"
                update_k8s_deployments "$namespace"
                update_k8s_configmaps "$namespace"
            done
        fi
    else
        log_warning "kubectl 不可用，跳过 Kubernetes 资源更新"
    fi
    
    # 2. 扫描和更新配置文件
    log_info "步骤 2: 扫描和更新配置文件"
    read -p "是否扫描当前目录的配置文件？(y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "请输入扫描目录 (默认: 当前目录): " -r scan_dir
        scan_dir=${scan_dir:-.}
        scan_and_update_config_files "$scan_dir"
    fi
    
    # 3. 生成更新指南
    log_info "步骤 3: 生成更新指南和检查清单"
    local env_guide
    env_guide=$(generate_env_update_guide)
    
    local checklist
    checklist=$(generate_app_switch_checklist)
    
    # 4. 生成更新报告
    log_info "步骤 4: 生成更新报告"
    local report_file
    report_file=$(generate_update_report)
    
    # 5. 更新状态
    update_migration_status
    
    log_success "=== Secret Manager 应用配置更新完成 ==="
    
    echo ""
    echo "更新结果摘要："
    echo "📋 环境变量指南: $env_guide"
    echo "✅ 切换检查清单: $checklist"
    echo "📄 更新报告: $report_file"
    echo "💾 备份目录: $BACKUP_DIR"
    echo ""
    echo "重要提醒："
    echo "1. 仔细阅读环境变量更新指南"
    echo "2. 按照检查清单逐步验证"
    echo "3. 在生产环境切换前进行充分测试"
    echo "4. 保留备份文件直到确认迁移成功"
    echo ""
    echo "下一步："
    echo "1. 查看更新指南: cat $env_guide"
    echo "2. 执行切换检查清单: cat $checklist"
    echo "3. 测试应用程序功能"
    echo "4. 监控生产环境稳定性"
}

# 执行主函数
main "$@"
```

## `config.sh`

```bash
#!/bin/bash

# GCP Secret Manager 迁移配置文件
# 请根据实际环境修改以下配置

# ==================== 基础项目配置 ====================

# 源项目ID（当前存储密钥的项目）
export SOURCE_PROJECT="your-source-project-id"

# 目标项目ID（要迁移到的项目）
export TARGET_PROJECT="your-target-project-id"

# ==================== 备份和日志配置 ====================

# 备份目录（相对路径，会自动创建时间戳子目录）
export BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"

# 日志文件路径
export LOG_FILE="$BACKUP_DIR/migration.log"

# 是否启用调试模式
export DEBUG=true

# ==================== 迁移配置 ====================

# 批量处理大小（一次处理的密钥数量）
export BATCH_SIZE=10

# 重试次数
export RETRY_COUNT=3

# 重试间隔（秒）
export RETRY_INTERVAL=5

# ==================== 验证配置 ====================

# 是否验证密钥值（可能会增加迁移时间）
export VERIFY_SECRET_VALUES=true

# 验证超时时间（秒）
export VERIFICATION_TIMEOUT=300

# ==================== 应用配置 ====================

# Kubernetes 命名空间列表（用于更新应用配置）
export K8S_NAMESPACES=("default" "production" "staging")

# 需要更新的配置文件模式
export CONFIG_FILE_PATTERNS=(
    "*.yaml"
    "*.yml"
    "*.json"
    "*.env"
)

# ==================== 颜色输出配置 ====================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# ==================== 函数定义 ====================

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
    fi
}

# 检查必要工具
check_prerequisites() {
    local tools=("gcloud" "jq" "kubectl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "以下工具未安装: ${missing_tools[*]}"
        echo "安装指南："
        echo "  gcloud: https://cloud.google.com/sdk/docs/install"
        echo "  kubectl: gcloud components install kubectl"
        echo "  jq: sudo apt-get install jq (Ubuntu) 或 brew install jq (macOS)"
        return 1
    fi
    
    # 检查 gcloud 认证
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud 未认证，请运行 'gcloud auth login'"
        return 1
    fi
    
    log_success "所有必要工具检查通过"
    return 0
}

# 创建必要目录
setup_directories() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/exported_secrets"
    mkdir -p "$BACKUP_DIR/k8s_backups"
    
    if [[ "$DEBUG" == "true" ]]; then
        log_debug "创建备份目录: $BACKUP_DIR"
        log_debug "日志文件: $LOG_FILE"
    fi
}

# 验证项目访问权限
verify_project_access() {
    local project=$1
    
    if ! gcloud projects describe "$project" &>/dev/null; then
        log_error "无法访问项目: $project"
        echo "请检查："
        echo "1. 项目ID是否正确"
        echo "2. 是否有项目访问权限"
        echo "3. gcloud 是否已正确认证"
        return 1
    fi
    
    log_success "项目访问验证通过: $project"
    return 0
}

# 检查 Secret Manager API
check_secret_manager_api() {
    local project=$1
    
    if ! gcloud services list --project="$project" --filter="name:secretmanager.googleapis.com" --format="value(name)" | grep -q secretmanager; then
        log_warning "项目 $project 未启用 Secret Manager API，正在启用..."
        if gcloud services enable secretmanager.googleapis.com --project="$project"; then
            log_success "Secret Manager API 已启用: $project"
        else
            log_error "无法启用 Secret Manager API: $project"
            return 1
        fi
    else
        log_success "Secret Manager API 已启用: $project"
    fi
    
    return 0
}

# 验证配置完整性
validate_config() {
    local errors=()
    
    # 检查必需的配置项
    [[ -z "$SOURCE_PROJECT" ]] && errors+=("SOURCE_PROJECT 未设置")
    [[ -z "$TARGET_PROJECT" ]] && errors+=("TARGET_PROJECT 未设置")
    [[ -z "$BACKUP_DIR" ]] && errors+=("BACKUP_DIR 未设置")
    [[ -z "$LOG_FILE" ]] && errors+=("LOG_FILE 未设置")
    
    # 检查项目ID格式
    if [[ ! "$SOURCE_PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        errors+=("SOURCE_PROJECT 格式不正确")
    fi
    
    if [[ ! "$TARGET_PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        errors+=("TARGET_PROJECT 格式不正确")
    fi
    
    # 检查源项目和目标项目不能相同
    if [[ "$SOURCE_PROJECT" == "$TARGET_PROJECT" ]]; then
        errors+=("源项目和目标项目不能相同")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "配置验证失败："
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_success "配置验证通过"
    return 0
}

# 重试机制
retry_command() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        else
            if [[ $attempt -lt $max_attempts ]]; then
                log_warning "命令执行失败，${delay}秒后重试 (尝试 $attempt/$max_attempts)"
                sleep "$delay"
            else
                log_error "命令执行失败，已达到最大重试次数 ($max_attempts)"
                return 1
            fi
        fi
        ((attempt++))
    done
}

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r${CYAN}[进度]${NC} ["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $remaining | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# 完成进度显示
complete_progress() {
    echo ""
}

# ==================== 初始化检查 ====================

# 如果直接执行此配置文件，进行基本验证
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Secret Manager 迁移工具配置验证"
    echo "=================================="
    
    setup_directories
    
    if validate_config && check_prerequisites; then
        echo ""
        log_success "配置验证完成，可以开始迁移"
        echo ""
        echo "下一步："
        echo "1. 修改配置文件中的项目ID"
        echo "2. 运行: ./migrate-secrets.sh setup"
    else
        echo ""
        log_error "配置验证失败，请修复后重试"
        exit 1
    fi
fi
```

## `migrate-secrets.sh`

```bash
#!/bin/bash

# Secret Manager 迁移主控制脚本
# 功能：统一管理整个 Secret Manager 迁移流程

set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
source "$SCRIPT_DIR/config.sh"

# 显示帮助信息
show_help() {
    cat << EOF
Secret Manager 迁移工具 - GCP 跨项目密钥迁移自动化脚本

用法: $0 [选项] [阶段]

阶段:
  setup       环境准备和权限检查
  discover    发现和分析源项目中的密钥
  export      导出源项目中的所有密钥
  import      导入密钥到目标项目
  verify      验证迁移结果
  update      更新应用程序配置
  all         执行完整迁移流程 (setup -> discover -> export -> import -> verify)
  status      显示当前迁移状态

选项:
  -h, --help              显示此帮助信息
  -s, --source PROJECT    源项目ID (覆盖配置文件)
  -t, --target PROJECT    目标项目ID (覆盖配置文件)
  -d, --dry-run          干运行模式，只显示将要执行的操作
  -v, --verbose          详细输出模式
  -f, --force            强制执行，跳过确认提示
  --batch-size SIZE      批量处理大小 (默认: $BATCH_SIZE)
  --no-verify-values     跳过密钥值验证以加快速度

示例:
  $0 setup                                    # 环境准备
  $0 discover                                 # 发现密钥
  $0 export                                   # 导出密钥
  $0 import                                   # 导入密钥
  $0 verify                                   # 验证结果
  $0 update                                   # 更新应用配置
  $0 all                                      # 执行完整迁移流程
  $0 status                                   # 查看迁移状态
  
  $0 -s source-proj -t target-proj all       # 指定项目执行完整迁移
  $0 --dry-run import                         # 干运行导入
  $0 --force --no-verify-values verify       # 强制验证但跳过值检查
  $0 --batch-size 5 export                   # 使用较小批量大小导出

配置:
  在执行前，请确保已正确配置 config.sh 文件中的以下参数:
  - SOURCE_PROJECT: 源项目ID
  - TARGET_PROJECT: 目标项目ID
  - 其他相关配置参数

注意事项:
  1. 确保已安装并配置 gcloud、kubectl 工具
  2. 确保对源项目和目标项目有足够的权限
  3. 建议先在测试环境验证整个流程
  4. 迁移前请做好备份和回滚准备
EOF
}

# 显示当前配置
show_config() {
    echo "=== 当前配置 ==="
    echo "源项目: ${SOURCE_PROJECT:-未设置}"
    echo "目标项目: ${TARGET_PROJECT:-未设置}"
    echo "批量大小: ${BATCH_SIZE:-未设置}"
    echo "验证密钥值: ${VERIFY_SECRET_VALUES:-未设置}"
    echo "备份目录: ${BACKUP_DIR:-未设置}"
    echo "日志文件: ${LOG_FILE:-未设置}"
    echo ""
}

# 显示迁移状态
show_migration_status() {
    log_info "检查迁移状态..."
    
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        echo "❌ 未找到迁移状态文件"
        echo "请先运行: $0 setup"
        return 1
    fi
    
    echo "=== 迁移状态 ==="
    
    local migration_id
    migration_id=$(jq -r '.migration_id' "$BACKUP_DIR/migration_status.json")
    echo "迁移ID: $migration_id"
    
    local start_time
    start_time=$(jq -r '.start_time' "$BACKUP_DIR/migration_status.json")
    echo "开始时间: $start_time"
    
    echo ""
    echo "各阶段状态:"
    
    local stages=("setup" "discover" "export" "import" "verify" "update")
    for stage in "${stages[@]}"; do
        local status
        status=$(jq -r ".stages.$stage" "$BACKUP_DIR/migration_status.json")
        
        case "$status" in
            "completed")
                echo "  ✅ $stage: 已完成"
                ;;
            "failed")
                echo "  ❌ $stage: 失败"
                ;;
            "pending")
                echo "  ⏳ $stage: 待执行"
                ;;
            *)
                echo "  ❓ $stage: 未知状态"
                ;;
        esac
    done
    
    echo ""
    
    # 显示统计信息
    if [[ -f "$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json" ]]; then
        local total_secrets
        total_secrets=$(jq length "$BACKUP_DIR/${SOURCE_PROJECT}_secrets_inventory.json")
        echo "发现的密钥数量: $total_secrets"
    fi
    
    if [[ -f "$BACKUP_DIR/export_log.json" ]]; then
        local exported_count
        exported_count=$(jq '[.[] | select(.status == "success")] | length' "$BACKUP_DIR/export_log.json")
        echo "已导出密钥数量: $exported_count"
    fi
    
    if [[ -f "$BACKUP_DIR/import_log.json" ]]; then
        local imported_count
        imported_count=$(jq '[.[] | select(.status == "success")] | length' "$BACKUP_DIR/import_log.json")
        echo "已导入密钥数量: $imported_count"
    fi
    
    if [[ -f "$BACKUP_DIR/verification_log.json" ]]; then
        local verified_count
        verified_count=$(jq '[.[] | select(.status == "success")] | length' "$BACKUP_DIR/verification_log.json")
        echo "验证通过密钥数量: $verified_count"
    fi
    
    echo ""
    echo "备份目录: $BACKUP_DIR"
    
    # 建议下一步操作
    local next_stage=""
    for stage in "${stages[@]}"; do
        local status
        status=$(jq -r ".stages.$stage" "$BACKUP_DIR/migration_status.json")
        if [[ "$status" == "pending" ]]; then
            next_stage="$stage"
            break
        fi
    done
    
    if [[ -n "$next_stage" ]]; then
        echo "建议下一步: $0 $next_stage"
    else
        echo "✅ 所有阶段已完成！"
    fi
}

# 检查阶段依赖
check_stage_dependencies() {
    local stage=$1
    
    if [[ ! -f "$BACKUP_DIR/migration_status.json" && "$stage" != "setup" ]]; then
        log_error "未找到迁移状态文件，请先运行: $0 setup"
        return 1
    fi
    
    case "$stage" in
        "discover")
            local setup_status
            setup_status=$(jq -r '.stages.setup' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$setup_status" != "completed" ]]; then
                log_error "环境准备未完成，请先运行: $0 setup"
                return 1
            fi
            ;;
        "export")
            local discover_status
            discover_status=$(jq -r '.stages.discover' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$discover_status" != "completed" ]]; then
                log_error "密钥发现未完成，请先运行: $0 discover"
                return 1
            fi
            ;;
        "import")
            local export_status
            export_status=$(jq -r '.stages.export' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$export_status" != "completed" ]]; then
                log_error "密钥导出未完成，请先运行: $0 export"
                return 1
            fi
            ;;
        "verify")
            local import_status
            import_status=$(jq -r '.stages.import' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$import_status" != "completed" ]]; then
                log_error "密钥导入未完成，请先运行: $0 import"
                return 1
            fi
            ;;
        "update")
            local verify_status
            verify_status=$(jq -r '.stages.verify' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
            if [[ "$verify_status" != "completed" ]]; then
                log_warning "密钥验证未完成，建议先运行: $0 verify"
                if [[ "$FORCE_MODE" != "true" ]]; then
                    read -p "是否继续？(y/n): " -r
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        return 1
                    fi
                fi
            fi
            ;;
    esac
    
    return 0
}

# 执行单个阶段
execute_stage() {
    local stage=$1
    local script_file=""
    
    case "$stage" in
        "setup")
            script_file="$SCRIPT_DIR/01-setup.sh"
            ;;
        "discover")
            script_file="$SCRIPT_DIR/02-discover.sh"
            ;;
        "export")
            script_file="$SCRIPT_DIR/03-export.sh"
            ;;
        "import")
            script_file="$SCRIPT_DIR/04-import.sh"
            ;;
        "verify")
            script_file="$SCRIPT_DIR/05-verify.sh"
            ;;
        "update")
            script_file="$SCRIPT_DIR/06-update-apps.sh"
            ;;
        *)
            log_error "未知阶段: $stage"
            return 1
            ;;
    esac
    
    if [[ ! -f "$script_file" ]]; then
        log_error "脚本文件不存在: $script_file"
        return 1
    fi
    
    log_info "执行阶段: $stage"
    log_info "脚本文件: $script_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] 将要执行: $script_file"
        return 0
    fi
    
    # 检查阶段依赖
    if [[ "$FORCE_MODE" != "true" ]]; then
        if ! check_stage_dependencies "$stage"; then
            return 1
        fi
    fi
    
    # 执行脚本
    if bash "$script_file"; then
        log_success "阶段 $stage 执行成功"
        return 0
    else
        log_error "阶段 $stage 执行失败"
        return 1
    fi
}

# 执行完整迁移流程
execute_full_migration() {
    log_info "开始执行完整 Secret Manager 迁移流程..."
    
    local stages=("setup" "discover" "export" "import" "verify")
    
    for stage in "${stages[@]}"; do
        log_info "=== 执行阶段: $stage ==="
        
        if ! execute_stage "$stage"; then
            log_error "阶段 $stage 失败，停止执行"
            echo ""
            echo "故障排除建议："
            echo "1. 检查错误日志: $LOG_FILE"
            echo "2. 查看迁移状态: $0 status"
            echo "3. 修复问题后重新运行失败的阶段: $0 $stage"
            echo "4. 或从失败点继续: $0 ${stages[*]:$((${#stages[@]}-1))}"
            return 1
        fi
        
        # 在阶段之间添加暂停，让用户有机会检查结果
        if [[ "$FORCE_MODE" != "true" && "$stage" != "verify" ]]; then
            echo ""
            read -p "阶段 $stage 完成，按回车键继续下一阶段..." -r
        fi
    done
    
    log_success "完整 Secret Manager 迁移流程执行成功！"
    echo ""
    echo "🎉 迁移完成！"
    echo ""
    echo "后续步骤："
    echo "1. 查看验证报告: cat $BACKUP_DIR/verification_report.txt"
    echo "2. 更新应用配置: $0 update"
    echo "3. 测试应用程序功能"
    echo "4. 监控生产环境稳定性"
}

# 解析命令行参数
DRY_RUN=false
VERBOSE=false
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--source)
            export SOURCE_PROJECT="$2"
            shift 2
            ;;
        -t|--target)
            export TARGET_PROJECT="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            export DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --batch-size)
            export BATCH_SIZE="$2"
            shift 2
            ;;
        --no-verify-values)
            export VERIFY_SECRET_VALUES=false
            shift
            ;;
        setup|discover|export|import|verify|update|all|status)
            STAGE="$1"
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 初始化
setup_directories

# 显示配置信息
if [[ "$VERBOSE" == "true" ]]; then
    show_config
fi

# 检查必要参数
if [[ -z "${STAGE:-}" ]]; then
    echo "错误: 请指定要执行的阶段"
    echo ""
    show_help
    exit 1
fi

# 验证配置（除了 status 命令）
if [[ "$STAGE" != "status" ]]; then
    if [[ -z "${SOURCE_PROJECT:-}" || -z "${TARGET_PROJECT:-}" ]]; then
        echo "错误: 请在 config.sh 中设置 SOURCE_PROJECT 和 TARGET_PROJECT"
        echo "或使用 -s 和 -t 参数指定"
        exit 1
    fi
    
    if ! validate_config; then
        exit 1
    fi
fi

# 主执行逻辑
case "$STAGE" in
    "all")
        execute_full_migration
        ;;
    "status")
        show_migration_status
        ;;
    *)
        execute_stage "$STAGE"
        ;;
esac
```

