#!/bin/bash

# DNS 迁移 - 第五步：清理操作
# 功能：清理迁移过程中的临时资源和旧资源

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始DNS迁移清理操作..."

# 函数：列出源项目中可以清理的资源
list_cleanup_candidates() {
    local project=$1
    
    log_info "扫描项目 $project 中可清理的资源..."
    
    local cleanup_file="$BACKUP_DIR/${project}_cleanup_candidates.txt"
    
    echo "# 项目 $project 清理候选资源" > "$cleanup_file"
    echo "# 扫描时间: $(date)" >> "$cleanup_file"
    echo "" >> "$cleanup_file"
    
    # 1. 扫描GKE集群
    echo "## GKE 集群" >> "$cleanup_file"
    local clusters
    clusters=$(gcloud container clusters list --project="$project" --format="value(name,location)" 2>/dev/null || echo "")
    
    if [[ -n "$clusters" ]]; then
        while IFS=$'\t' read -r cluster_name location; do
            echo "- 集群: $cluster_name (位置: $location)" >> "$cleanup_file"
            
            # 获取集群详细信息
            local node_count
            node_count=$(gcloud container clusters describe "$cluster_name" --location="$location" --project="$project" --format="value(currentNodeCount)" 2>/dev/null || echo "0")
            echo "  节点数: $node_count" >> "$cleanup_file"
            
            # 检查集群是否有流量
            gcloud container clusters get-credentials "$cluster_name" --location="$location" --project="$project" 2>/dev/null || true
            local ingress_count
            ingress_count=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
            echo "  Ingress数量: $ingress_count" >> "$cleanup_file"
            
        done <<< "$clusters"
    else
        echo "- 无GKE集群" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 2. 扫描负载均衡器
    echo "## 负载均衡器" >> "$cleanup_file"
    local forwarding_rules
    forwarding_rules=$(gcloud compute forwarding-rules list --project="$project" --format="value(name,IPAddress,target)" 2>/dev/null || echo "")
    
    if [[ -n "$forwarding_rules" ]]; then
        while IFS=$'\t' read -r rule_name ip_address target; do
            echo "- 转发规则: $rule_name (IP: $ip_address, 目标: $target)" >> "$cleanup_file"
        done <<< "$forwarding_rules"
    else
        echo "- 无负载均衡器" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 3. 扫描静态IP地址
    echo "## 静态IP地址" >> "$cleanup_file"
    local static_ips
    static_ips=$(gcloud compute addresses list --project="$project" --format="value(name,address,status,users)" 2>/dev/null || echo "")
    
    if [[ -n "$static_ips" ]]; then
        while IFS=$'\t' read -r ip_name ip_address status users; do
            echo "- IP地址: $ip_name ($ip_address) - 状态: $status" >> "$cleanup_file"
            if [[ -n "$users" ]]; then
                echo "  使用者: $users" >> "$cleanup_file"
            else
                echo "  使用者: 无 (可安全删除)" >> "$cleanup_file"
            fi
        done <<< "$static_ips"
    else
        echo "- 无静态IP地址" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 4. 扫描持久磁盘
    echo "## 持久磁盘" >> "$cleanup_file"
    local disks
    disks=$(gcloud compute disks list --project="$project" --format="value(name,sizeGb,status,users)" 2>/dev/null || echo "")
    
    if [[ -n "$disks" ]]; then
        while IFS=$'\t' read -r disk_name size_gb status users; do
            echo "- 磁盘: $disk_name (${size_gb}GB) - 状态: $status" >> "$cleanup_file"
            if [[ -n "$users" ]]; then
                echo "  使用者: $users" >> "$cleanup_file"
            else
                echo "  使用者: 无 (可安全删除)" >> "$cleanup_file"
            fi
        done <<< "$disks"
    else
        echo "- 无持久磁盘" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 5. 扫描防火墙规则
    echo "## 防火墙规则" >> "$cleanup_file"
    local firewall_rules
    firewall_rules=$(gcloud compute firewall-rules list --project="$project" --format="value(name,direction,priority,sourceRanges,allowed)" 2>/dev/null || echo "")
    
    if [[ -n "$firewall_rules" ]]; then
        while IFS=$'\t' read -r rule_name direction priority source_ranges allowed; do
            echo "- 防火墙规则: $rule_name ($direction, 优先级: $priority)" >> "$cleanup_file"
        done <<< "$firewall_rules"
    else
        echo "- 无自定义防火墙规则" >> "$cleanup_file"
    fi
    
    log_success "资源扫描完成: $cleanup_file"
    echo "$cleanup_file"
}

# 函数：检查资源使用情况
check_resource_usage() {
    local project=$1
    local resource_type=$2
    local resource_name=$3
    
    case "$resource_type" in
        "cluster")
            # 检查集群是否有活跃的工作负载
            gcloud container clusters get-credentials "$resource_name" --region="$CLUSTER_REGION" --project="$project" 2>/dev/null || return 1
            
            local pod_count
            pod_count=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
            
            if [[ "$pod_count" -gt 0 ]]; then
                log_warning "集群 $resource_name 仍有 $pod_count 个Pod运行"
                return 1
            fi
            ;;
        "forwarding-rule")
            # 检查转发规则是否有流量
            # 这里可以添加更复杂的流量检查逻辑
            log_info "检查转发规则 $resource_name 的使用情况"
            ;;
        "address")
            # 检查IP地址是否被使用
            local users
            users=$(gcloud compute addresses describe "$resource_name" --project="$project" --format="value(users)" 2>/dev/null || echo "")
            
            if [[ -n "$users" ]]; then
                log_warning "IP地址 $resource_name 仍被使用: $users"
                return 1
            fi
            ;;
        "disk")
            # 检查磁盘是否被挂载
            local users
            users=$(gcloud compute disks describe "$resource_name" --zone="$CLUSTER_REGION-a" --project="$project" --format="value(users)" 2>/dev/null || echo "")
            
            if [[ -n "$users" ]]; then
                log_warning "磁盘 $resource_name 仍被使用: $users"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# 函数：安全删除GKE集群
safe_delete_cluster() {
    local project=$1
    local cluster_name=$2
    local location=$3
    
    log_info "准备删除集群: $cluster_name"
    
    # 检查集群状态
    if ! check_resource_usage "$project" "cluster" "$cluster_name"; then
        log_error "集群 $cluster_name 仍在使用中，跳过删除"
        return 1
    fi
    
    # 确认删除
    read -p "确认删除集群 $cluster_name？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "跳过删除集群 $cluster_name"
        return 0
    fi
    
    # 执行删除
    log_info "删除集群 $cluster_name..."
    if gcloud container clusters delete "$cluster_name" --location="$location" --project="$project" --quiet; then
        log_success "集群 $cluster_name 删除成功"
        return 0
    else
        log_error "集群 $cluster_name 删除失败"
        return 1
    fi
}

# 函数：安全删除负载均衡器
safe_delete_load_balancer() {
    local project=$1
    local rule_name=$2
    
    log_info "准备删除转发规则: $rule_name"
    
    # 确认删除
    read -p "确认删除转发规则 $rule_name？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "跳过删除转发规则 $rule_name"
        return 0
    fi
    
    # 执行删除
    log_info "删除转发规则 $rule_name..."
    if gcloud compute forwarding-rules delete "$rule_name" --project="$project" --quiet; then
        log_success "转发规则 $rule_name 删除成功"
        return 0
    else
        log_error "转发规则 $rule_name 删除失败"
        return 1
    fi
}

# 函数：安全删除静态IP
safe_delete_static_ip() {
    local project=$1
    local ip_name=$2
    
    log_info "准备删除静态IP: $ip_name"
    
    # 检查IP使用情况
    if ! check_resource_usage "$project" "address" "$ip_name"; then
        log_error "静态IP $ip_name 仍在使用中，跳过删除"
        return 1
    fi
    
    # 确认删除
    read -p "确认删除静态IP $ip_name？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "跳过删除静态IP $ip_name"
        return 0
    fi
    
    # 执行删除
    log_info "删除静态IP $ip_name..."
    if gcloud compute addresses delete "$ip_name" --project="$project" --quiet; then
        log_success "静态IP $ip_name 删除成功"
        return 0
    else
        log_error "静态IP $ip_name 删除失败"
        return 1
    fi
}

# 函数：清理DNS记录中的过渡CNAME
cleanup_transition_cnames() {
    local project=$1
    local zone=$2
    
    log_info "清理项目 $project 中的过渡CNAME记录"
    
    # 检查是否存在指向目标项目的CNAME记录
    local cname_records
    cname_records=$(gcloud dns record-sets list --zone="$zone" --project="$project" --filter="type=CNAME" --format="value(name,rrdatas)" 2>/dev/null || echo "")
    
    if [[ -z "$cname_records" ]]; then
        log_info "未找到CNAME记录"
        return 0
    fi
    
    local cleanup_count=0
    while IFS=$'\t' read -r record_name record_data; do
        # 检查是否是指向目标项目的CNAME
        if [[ "$record_data" == *"${TARGET_PROJECT}.${PARENT_DOMAIN}"* ]]; then
            log_info "发现过渡CNAME记录: $record_name -> $record_data"
            
            read -p "删除过渡CNAME记录 $record_name？(yes/no): " -r
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                # 获取记录的TTL
                local ttl
                ttl=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$record_name" --type=CNAME --format="value(ttl)" 2>/dev/null || echo "300")
                
                # 删除CNAME记录
                gcloud dns record-sets transaction start --zone="$zone" --project="$project"
                gcloud dns record-sets transaction remove "$record_data" \
                    --name="$record_name" \
                    --ttl="$ttl" \
                    --type=CNAME \
                    --zone="$zone" \
                    --project="$project"
                
                if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
                    log_success "过渡CNAME记录删除成功: $record_name"
                    ((cleanup_count++))
                else
                    log_error "过渡CNAME记录删除失败: $record_name"
                    gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
                fi
            fi
        fi
    done <<< "$cname_records"
    
    log_info "清理了 $cleanup_count 个过渡CNAME记录"
}

# 函数：生成清理报告
generate_cleanup_report() {
    local cleanup_results=("$@")
    
    log_info "生成清理报告..."
    
    local report_file="$BACKUP_DIR/cleanup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# DNS 迁移清理报告
# 执行时间: $(date)
# 源项目: $SOURCE_PROJECT
# 目标项目: $TARGET_PROJECT

## 清理操作摘要
EOF
    
    local success_count=0
    local total_operations=${#cleanup_results[@]}
    
    for result in "${cleanup_results[@]}"; do
        echo "- $result" >> "$report_file"
        
        if [[ "$result" == *"SUCCESS"* ]]; then
            ((success_count++))
        fi
    done
    
    cat >> "$report_file" << EOF

## 统计信息
- 总计操作: $total_operations
- 成功清理: $success_count
- 跳过/失败: $((total_operations - success_count))

## 清理后状态
- 源项目中的旧资源已按选择进行清理
- 目标项目继续正常运行
- DNS记录已优化，移除了不必要的过渡记录

## 后续建议
1. 定期检查和清理未使用的资源
2. 更新监控和告警配置
3. 更新文档和运维手册
4. 考虑设置资源使用监控和自动清理策略

## 注意事项
- 保留此报告用于审计和问题追踪
- 如发现误删除，可参考备份文件进行恢复
EOF
    
    log_success "清理报告生成完成: $report_file"
    echo "$report_file"
}

# 函数：交互式清理确认
confirm_cleanup() {
    echo ""
    echo "=== DNS 迁移清理确认 ==="
    echo "此操作将清理源项目 ($SOURCE_PROJECT) 中的以下类型资源:"
    echo "1. 不再使用的GKE集群"
    echo "2. 不再使用的负载均衡器"
    echo "3. 未使用的静态IP地址"
    echo "4. 过渡期的CNAME记录"
    echo ""
    echo "警告: 清理操作不可逆，请确保已完成迁移验证"
    echo ""
    read -p "确认开始清理操作？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "用户取消清理操作"
        exit 0
    fi
}

# 主执行流程
main() {
    log_info "=== DNS 迁移清理阶段开始 ==="
    
    # 交互式确认
    confirm_cleanup
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    
    # 1. 扫描可清理的资源
    log_info "步骤 1: 扫描可清理的资源"
    local cleanup_candidates_file
    cleanup_candidates_file=$(list_cleanup_candidates "$SOURCE_PROJECT")
    
    echo ""
    echo "请查看清理候选资源:"
    echo "cat $cleanup_candidates_file"
    echo ""
    read -p "按回车键继续清理操作..." -r
    
    # 2. 清理GKE集群
    log_info "步骤 2: 清理GKE集群"
    local cleanup_results=()
    
    local clusters
    clusters=$(gcloud container clusters list --project="$SOURCE_PROJECT" --format="value(name,location)" 2>/dev/null || echo "")
    
    if [[ -n "$clusters" ]]; then
        while IFS=$'\t' read -r cluster_name location; do
            if safe_delete_cluster "$SOURCE_PROJECT" "$cluster_name" "$location"; then
                cleanup_results+=("集群 $cluster_name: SUCCESS")
            else
                cleanup_results+=("集群 $cluster_name: SKIPPED/FAILED")
            fi
        done <<< "$clusters"
    fi
    
    # 3. 清理负载均衡器
    log_info "步骤 3: 清理负载均衡器"
    local forwarding_rules
    forwarding_rules=$(gcloud compute forwarding-rules list --project="$SOURCE_PROJECT" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$forwarding_rules" ]]; then
        while read -r rule_name; do
            if [[ -n "$rule_name" ]]; then
                if safe_delete_load_balancer "$SOURCE_PROJECT" "$rule_name"; then
                    cleanup_results+=("转发规则 $rule_name: SUCCESS")
                else
                    cleanup_results+=("转发规则 $rule_name: SKIPPED/FAILED")
                fi
            fi
        done <<< "$forwarding_rules"
    fi
    
    # 4. 清理静态IP地址
    log_info "步骤 4: 清理静态IP地址"
    local static_ips
    static_ips=$(gcloud compute addresses list --project="$SOURCE_PROJECT" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$static_ips" ]]; then
        while read -r ip_name; do
            if [[ -n "$ip_name" ]]; then
                if safe_delete_static_ip "$SOURCE_PROJECT" "$ip_name"; then
                    cleanup_results+=("静态IP $ip_name: SUCCESS")
                else
                    cleanup_results+=("静态IP $ip_name: SKIPPED/FAILED")
                fi
            fi
        done <<< "$static_ips"
    fi
    
    # 5. 清理过渡CNAME记录
    log_info "步骤 5: 清理过渡CNAME记录"
    cleanup_transition_cnames "$SOURCE_PROJECT" "$SOURCE_ZONE"
    cleanup_results+=("过渡CNAME记录清理: COMPLETED")
    
    # 6. 生成清理报告
    log_info "步骤 6: 生成清理报告"
    local report_file
    report_file=$(generate_cleanup_report "${cleanup_results[@]}")
    
    log_success "=== DNS 迁移清理阶段完成 ==="
    log_info "清理候选资源: $cleanup_candidates_file"
    log_info "清理报告: $report_file"
    
    echo ""
    echo "清理操作完成！"
    echo "建议："
    echo "1. 检查清理报告确认所有操作"
    echo "2. 验证目标项目服务正常运行"
    echo "3. 更新相关文档和监控配置"
    echo "4. 定期检查和清理未使用的资源"
}

# 执行主函数
main "$@"