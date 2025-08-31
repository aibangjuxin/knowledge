#!/bin/bash

# DNS 迁移 - 第四步：回滚操作
# 功能：将DNS记录回滚到迁移前的状态

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始DNS迁移回滚操作..."

# 函数：列出可用的备份文件
list_backup_files() {
    log_info "查找可用的备份文件..."
    
    local backup_files=()
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$BACKUP_DIR" -name "*_dns_backup_*.json" -print0 2>/dev/null || true)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_error "未找到DNS备份文件"
        return 1
    fi
    
    echo "可用的备份文件:"
    for i in "${!backup_files[@]}"; do
        local file="${backup_files[$i]}"
        local timestamp=$(basename "$file" | sed 's/.*_dns_backup_\(.*\)\.json/\1/')
        echo "$((i+1)). $file (时间: $timestamp)"
    done
    
    echo ""
    read -p "请选择要回滚的备份文件编号 (1-${#backup_files[@]}): " -r backup_choice
    
    if [[ "$backup_choice" =~ ^[0-9]+$ ]] && [[ "$backup_choice" -ge 1 ]] && [[ "$backup_choice" -le ${#backup_files[@]} ]]; then
        echo "${backup_files[$((backup_choice-1))]}"
    else
        log_error "无效的选择"
        return 1
    fi
}

# 函数：解析备份文件中的DNS记录
parse_backup_records() {
    local backup_file=$1
    local domain_filter=$2
    
    log_info "解析备份文件中的DNS记录: $backup_file"
    
    # 提取指定域名的记录
    jq -r --arg domain "$domain_filter" '
        .[] | 
        select(.name == $domain) | 
        "\(.name):\(.type):\(.ttl):\(.rrdatas | join(","))"
    ' "$backup_file"
}

# 函数：恢复单个DNS记录
restore_dns_record() {
    local project=$1
    local zone=$2
    local domain_name=$3
    local record_type=$4
    local ttl=$5
    local record_data=$6
    
    log_info "恢复DNS记录: $domain_name ($record_type)"
    
    # 获取当前记录（如果存在）
    local current_record
    current_record=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,ttl,rrdatas)" 2>/dev/null || echo "")
    
    # 开始事务
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    
    # 如果当前存在记录，先删除
    if [[ -n "$current_record" ]]; then
        IFS=$'\t' read -r current_type current_ttl current_data <<< "$current_record"
        log_info "删除当前记录: $domain_name ($current_type) -> $current_data"
        
        gcloud dns record-sets transaction remove "$current_data" \
            --name="$domain_name" \
            --ttl="$current_ttl" \
            --type="$current_type" \
            --zone="$zone" \
            --project="$project"
    fi
    
    # 添加备份的记录
    log_info "恢复记录: $domain_name ($record_type) -> $record_data (TTL: $ttl)"
    gcloud dns record-sets transaction add "$record_data" \
        --name="$domain_name" \
        --ttl="$ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 执行事务
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "DNS记录恢复成功: $domain_name"
        return 0
    else
        log_error "DNS记录恢复失败: $domain_name"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：验证回滚结果
verify_rollback() {
    local domain_name=$1
    local expected_type=$2
    local expected_data=$3
    local timeout=${4:-$VALIDATION_TIMEOUT}
    
    log_info "验证回滚结果: $domain_name"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local current_record
        current_record=$(gcloud dns record-sets list --zone="$SOURCE_ZONE" --project="$SOURCE_PROJECT" --name="$domain_name" --format="value(type,rrdatas)" 2>/dev/null || echo "")
        
        if [[ -n "$current_record" ]]; then
            IFS=$'\t' read -r record_type record_data <<< "$current_record"
            
            if [[ "$record_type" == "$expected_type" && "$record_data" == "$expected_data" ]]; then
                log_success "回滚验证成功: $domain_name"
                return 0
            fi
        fi
        
        log_info "等待DNS记录更新..."
        sleep 10
    done
    
    log_warning "回滚验证超时: $domain_name"
    return 1
}

# 函数：测试回滚后的服务可用性
test_rollback_service() {
    local domain_name=$1
    local timeout=${2:-30}
    
    log_info "测试回滚后服务可用性: $domain_name"
    
    # 移除域名末尾的点
    local clean_domain="${domain_name%.*}"
    
    # 等待DNS传播
    log_info "等待DNS传播 (60秒)..."
    sleep 60
    
    for endpoint in "${HEALTH_CHECK_ENDPOINTS[@]}"; do
        local url="https://${clean_domain}${endpoint}"
        log_info "测试端点: $url"
        
        if curl -s --max-time "$timeout" --fail "$url" >/dev/null 2>&1; then
            log_success "回滚后端点可访问: $url"
            return 0
        else
            log_warning "回滚后端点不可访问: $url"
        fi
    done
    
    # 基本连通性测试
    local url="https://${clean_domain}/"
    if curl -s --max-time "$timeout" -I "$url" 2>/dev/null | grep -q "HTTP"; then
        log_success "回滚后基本连通性正常: $url"
        return 0
    else
        log_error "回滚后服务不可访问: $clean_domain"
        return 1
    fi
}

# 函数：生成回滚报告
generate_rollback_report() {
    local rollback_results=("$@")
    
    log_info "生成回滚报告..."
    
    local report_file="$BACKUP_DIR/rollback_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# DNS 迁移回滚报告
# 执行时间: $(date)
# 源项目: $SOURCE_PROJECT
# 目标项目: $TARGET_PROJECT

## 回滚结果摘要
EOF
    
    local success_count=0
    local total_count=${#DOMAIN_MAPPINGS[@]}
    
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local result="${rollback_results[$i]:-UNKNOWN}"
        
        echo "- $source_domain: $result" >> "$report_file"
        
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    cat >> "$report_file" << EOF

## 统计信息
- 总计域名: $total_count
- 成功回滚: $success_count
- 失败数量: $((total_count - success_count))
- 成功率: $(( success_count * 100 / total_count ))%

## 回滚后状态
所有域名已恢复到迁移前的状态。

## 后续步骤
1. 验证所有服务功能正常
2. 分析迁移失败的原因
3. 修复问题后重新规划迁移
4. 更新迁移计划和文档

## 注意事项
- 目标项目的资源仍然存在，可以保留用于下次迁移
- 建议保留此次的日志和报告用于问题分析
EOF
    
    log_success "回滚报告生成完成: $report_file"
    echo "$report_file"
}

# 函数：交互式确认回滚
confirm_rollback() {
    echo ""
    echo "=== DNS 迁移回滚确认 ==="
    echo "警告: 此操作将把以下域名回滚到迁移前的状态:"
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}"
        echo "  $source_domain"
    done
    
    echo ""
    echo "回滚后，流量将重新指向源项目 ($SOURCE_PROJECT)"
    echo ""
    read -p "确认执行回滚操作？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "用户取消回滚操作"
        exit 0
    fi
}

# 主执行流程
main() {
    log_info "=== DNS 迁移回滚阶段开始 ==="
    
    # 交互式确认
    confirm_rollback
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    
    # 1. 选择备份文件
    log_info "步骤 1: 选择备份文件"
    local backup_file
    backup_file=$(list_backup_files)
    
    if [[ -z "$backup_file" ]]; then
        log_error "未选择有效的备份文件"
        exit 1
    fi
    
    log_info "使用备份文件: $backup_file"
    
    # 2. 执行回滚操作
    log_info "步骤 2: 执行DNS记录回滚"
    local rollback_results=()
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        # 从备份文件中获取原始记录
        local backup_record
        backup_record=$(parse_backup_records "$backup_file" "$source_domain")
        
        if [[ -n "$backup_record" ]]; then
            IFS=':' read -r domain_name record_type ttl record_data <<< "$backup_record"
            
            if restore_dns_record "$SOURCE_PROJECT" "$SOURCE_ZONE" "$domain_name" "$record_type" "$ttl" "$record_data"; then
                rollback_results+=("SUCCESS")
            else
                rollback_results+=("FAILED")
            fi
        else
            log_error "在备份文件中未找到域名 $source_domain 的记录"
            rollback_results+=("NOT_FOUND")
        fi
    done
    
    # 3. 验证回滚结果
    log_info "步骤 3: 验证回滚结果"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${rollback_results[$i]}" == "SUCCESS" ]]; then
            # 从备份文件获取预期的记录信息用于验证
            local backup_record
            backup_record=$(parse_backup_records "$backup_file" "$source_domain")
            
            if [[ -n "$backup_record" ]]; then
                IFS=':' read -r domain_name record_type ttl record_data <<< "$backup_record"
                verify_rollback "$domain_name" "$record_type" "$record_data"
            fi
        fi
    done
    
    # 4. 测试服务可用性
    log_info "步骤 4: 测试回滚后服务可用性"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${rollback_results[$i]}" == "SUCCESS" ]]; then
            test_rollback_service "$source_domain"
        fi
    done
    
    # 5. 生成回滚报告
    log_info "步骤 5: 生成回滚报告"
    local report_file
    report_file=$(generate_rollback_report "${rollback_results[@]}")
    
    log_success "=== DNS 迁移回滚阶段完成 ==="
    log_info "使用的备份: $backup_file"
    log_info "回滚报告: $report_file"
    
    # 统计结果
    local success_count=0
    for result in "${rollback_results[@]}"; do
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    echo ""
    echo "回滚结果: $success_count/${#DOMAIN_MAPPINGS[@]} 个域名回滚成功"
    
    if [[ $success_count -eq ${#DOMAIN_MAPPINGS[@]} ]]; then
        log_success "所有域名回滚成功！"
        echo "建议："
        echo "1. 验证所有服务功能正常"
        echo "2. 分析迁移失败原因"
        echo "3. 修复问题后重新规划迁移"
    else
        log_error "部分域名回滚失败，请手动检查和修复"
    fi
}

# 执行主函数
main "$@"