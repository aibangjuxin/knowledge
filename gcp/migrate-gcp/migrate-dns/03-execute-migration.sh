#!/bin/bash

# DNS 迁移 - 第三步：执行DNS切换
# 功能：将源项目的DNS记录切换为CNAME指向目标项目

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始执行DNS迁移切换..."

# 函数：降低DNS记录的TTL
reduce_dns_ttl() {
    local project=$1
    local zone=$2
    local domain_name=$3
    local new_ttl=$4
    
    log_info "降低域名 $domain_name 的TTL至 $new_ttl 秒"
    
    # 获取当前记录信息
    local current_record
    current_record=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,ttl,rrdatas)" 2>/dev/null || echo "")
    
    if [[ -z "$current_record" ]]; then
        log_error "域名 $domain_name 的记录不存在"
        return 1
    fi
    
    IFS=$'\t' read -r record_type current_ttl record_data <<< "$current_record"
    
    if [[ "$current_ttl" -le "$new_ttl" ]]; then
        log_info "域名 $domain_name 的TTL已经是 $current_ttl 秒，无需降低"
        return 0
    fi
    
    # 开始事务
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    
    # 删除旧记录
    gcloud dns record-sets transaction remove "$record_data" \
        --name="$domain_name" \
        --ttl="$current_ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 添加新记录（相同数据，但TTL更低）
    gcloud dns record-sets transaction add "$record_data" \
        --name="$domain_name" \
        --ttl="$new_ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 执行事务
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "域名 $domain_name TTL降低成功: $current_ttl -> $new_ttl"
        return 0
    else
        log_error "域名 $domain_name TTL降低失败"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：备份当前DNS记录
backup_current_dns_records() {
    local project=$1
    local zone=$2
    
    log_info "备份项目 $project 的当前DNS记录"
    
    local backup_file="$BACKUP_DIR/${project}_dns_backup_$(date +%Y%m%d_%H%M%S).json"
    gcloud dns record-sets list --zone="$zone" --project="$project" --format=json > "$backup_file"
    
    log_success "DNS记录备份完成: $backup_file"
    echo "$backup_file"
}

# 函数：将DNS记录从A/CNAME切换为CNAME指向目标项目
switch_dns_to_cname() {
    local project=$1
    local zone=$2
    local domain_name=$3
    local target_domain=$4
    local ttl=${5:-$MIGRATION_TTL}
    
    log_info "切换域名 $domain_name -> $target_domain"
    
    # 获取当前记录信息
    local current_record
    current_record=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,ttl,rrdatas)" 2>/dev/null || echo "")
    
    if [[ -z "$current_record" ]]; then
        log_error "域名 $domain_name 的记录不存在"
        return 1
    fi
    
    IFS=$'\t' read -r record_type current_ttl record_data <<< "$current_record"
    
    log_info "当前记录: $domain_name ($record_type) -> $record_data (TTL: $current_ttl)"
    
    # 开始事务
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    
    # 删除当前记录
    gcloud dns record-sets transaction remove "$record_data" \
        --name="$domain_name" \
        --ttl="$current_ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 添加新的CNAME记录
    gcloud dns record-sets transaction add "$target_domain" \
        --name="$domain_name" \
        --ttl="$ttl" \
        --type=CNAME \
        --zone="$zone" \
        --project="$project"
    
    # 执行事务
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "DNS切换成功: $domain_name -> $target_domain"
        return 0
    else
        log_error "DNS切换失败: $domain_name"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：验证DNS切换结果
verify_dns_migration() {
    local domain_name=$1
    local expected_target=$2
    local timeout=${3:-$VALIDATION_TIMEOUT}
    
    log_info "验证域名 $domain_name 的DNS切换结果"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # 使用多个DNS服务器进行验证
        local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
        local success_count=0
        
        for dns_server in "${dns_servers[@]}"; do
            local resolved_cname
            resolved_cname=$(dig +short CNAME "$domain_name" "@$dns_server" 2>/dev/null | sed 's/\.$//' || echo "")
            
            if [[ "$resolved_cname" == "${expected_target%.*}" ]]; then
                ((success_count++))
            fi
        done
        
        # 如果大多数DNS服务器都返回正确结果，认为验证成功
        if [[ $success_count -ge 2 ]]; then
            log_success "域名 $domain_name DNS切换验证成功"
            return 0
        fi
        
        log_info "等待DNS传播... (${success_count}/${#dns_servers[@]} 服务器已更新)"
        sleep 10
    done
    
    log_warning "域名 $domain_name DNS切换验证超时，但这可能是正常的DNS传播延迟"
    return 1
}

# 函数：测试目标服务的可用性
test_target_service_availability() {
    local domain_name=$1
    local timeout=${2:-30}
    
    log_info "测试目标服务可用性: $domain_name"
    
    # 移除域名末尾的点
    local clean_domain="${domain_name%.*}"
    
    for endpoint in "${HEALTH_CHECK_ENDPOINTS[@]}"; do
        local url="https://${clean_domain}${endpoint}"
        log_info "测试端点: $url"
        
        if curl -s --max-time "$timeout" --fail "$url" >/dev/null 2>&1; then
            log_success "端点 $url 可访问"
            return 0
        else
            log_warning "端点 $url 不可访问或响应异常"
        fi
    done
    
    # 如果健康检查端点都不可用，尝试基本的连通性测试
    local url="https://${clean_domain}/"
    if curl -s --max-time "$timeout" -I "$url" 2>/dev/null | grep -q "HTTP"; then
        log_success "基本连通性测试通过: $url"
        return 0
    else
        log_error "目标服务不可访问: $clean_domain"
        return 1
    fi
}

# 函数：生成迁移报告
generate_migration_report() {
    local migration_results=("$@")
    
    log_info "生成迁移报告..."
    
    local report_file="$BACKUP_DIR/migration_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# DNS 迁移执行报告
# 执行时间: $(date)
# 源项目: $SOURCE_PROJECT
# 目标项目: $TARGET_PROJECT

## 迁移结果摘要
EOF
    
    local success_count=0
    local total_count=${#DOMAIN_MAPPINGS[@]}
    
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}."
        local result="${migration_results[$i]:-UNKNOWN}"
        
        echo "- $source_domain -> $target_domain: $result" >> "$report_file"
        
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    cat >> "$report_file" << EOF

## 统计信息
- 总计域名: $total_count
- 成功迁移: $success_count
- 失败数量: $((total_count - success_count))
- 成功率: $(( success_count * 100 / total_count ))%

## 后续步骤
1. 监控目标服务的流量和性能指标
2. 验证所有应用功能正常
3. 在确认稳定后，考虑清理源项目资源
4. 更新内部文档和配置

## 回滚信息
如需回滚，请执行: ./04-rollback.sh
备份文件位置: $BACKUP_DIR
EOF
    
    log_success "迁移报告生成完成: $report_file"
    echo "$report_file"
}

# 函数：交互式确认
confirm_migration() {
    echo ""
    echo "=== DNS 迁移确认 ==="
    echo "源项目: $SOURCE_PROJECT"
    echo "目标项目: $TARGET_PROJECT"
    echo "将要迁移的域名:"
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}"
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}"
        echo "  $source_domain -> $target_domain"
    done
    
    echo ""
    read -p "确认执行DNS迁移？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "用户取消迁移操作"
        exit 0
    fi
}

# 主执行流程
main() {
    log_info "=== DNS 迁移执行阶段开始 ==="
    
    # 交互式确认
    confirm_migration
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    verify_project_access "$TARGET_PROJECT"
    
    # 1. 备份当前DNS记录
    log_info "步骤 1: 备份当前DNS记录"
    local backup_file
    backup_file=$(backup_current_dns_records "$SOURCE_PROJECT" "$SOURCE_ZONE")
    
    # 2. 降低TTL（如果需要）
    log_info "步骤 2: 降低DNS记录TTL"
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        reduce_dns_ttl "$SOURCE_PROJECT" "$SOURCE_ZONE" "$source_domain" "$MIGRATION_TTL"
    done
    
    # 等待TTL生效
    log_info "等待TTL更新生效 (60秒)..."
    sleep 60
    
    # 3. 执行DNS切换
    log_info "步骤 3: 执行DNS切换"
    local migration_results=()
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}."
        
        if switch_dns_to_cname "$SOURCE_PROJECT" "$SOURCE_ZONE" "$source_domain" "$target_domain"; then
            migration_results+=("SUCCESS")
        else
            migration_results+=("FAILED")
        fi
    done
    
    # 4. 验证DNS切换结果
    log_info "步骤 4: 验证DNS切换结果"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${migration_results[$i]}" == "SUCCESS" ]]; then
            verify_dns_migration "$source_domain" "$target_domain"
        fi
    done
    
    # 5. 测试目标服务可用性
    log_info "步骤 5: 测试目标服务可用性"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${migration_results[$i]}" == "SUCCESS" ]]; then
            test_target_service_availability "$source_domain"
        fi
    done
    
    # 6. 生成迁移报告
    log_info "步骤 6: 生成迁移报告"
    local report_file
    report_file=$(generate_migration_report "${migration_results[@]}")
    
    log_success "=== DNS 迁移执行阶段完成 ==="
    log_info "备份文件: $backup_file"
    log_info "迁移报告: $report_file"
    
    # 统计结果
    local success_count=0
    for result in "${migration_results[@]}"; do
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    echo ""
    echo "迁移结果: $success_count/${#DOMAIN_MAPPINGS[@]} 个域名迁移成功"
    
    if [[ $success_count -eq ${#DOMAIN_MAPPINGS[@]} ]]; then
        log_success "所有域名迁移成功！"
        echo "建议："
        echo "1. 监控目标服务24-48小时"
        echo "2. 验证所有应用功能"
        echo "3. 考虑运行清理脚本: ./05-cleanup.sh"
    else
        log_warning "部分域名迁移失败，请检查日志并考虑回滚"
        echo "回滚命令: ./04-rollback.sh"
    fi
}

# 执行主函数
main "$@"