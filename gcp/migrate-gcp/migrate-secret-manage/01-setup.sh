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