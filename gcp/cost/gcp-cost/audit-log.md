- abc
- audit 高成本日志对我们来说不是很合适
- ”storage.googleapis.com"
- "bigquery.googleapis.com"
- "compute.googleapis.com

```bash
# 检查审计日志配置
audit_audit_logs() {
    log_info "=== 审计审计日志配置 ==="

    # 检查最近的审计日志量
    log_info "检查最近 24 小时的审计日志量..."

    audit_log_count=$(gcloud logging read \
        'protoPayload.serviceName!="" AND timestamp>="'$(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%SZ)'"' \
        --project="$PROJECT_ID" \
        --limit=1000 \
        --format="value(timestamp)" 2>/dev/null | wc -l)

    if [ "$audit_log_count" -gt 0 ]; then
        echo "  最近 24 小时审计日志条数: $audit_log_count"

        if [ "$audit_log_count" -gt 10000 ]; then
            log_warning "  审计日志量较大，检查是否启用了不必要的数据访问日志"
        else
            log_success "  审计日志量在合理范围内"
        fi
    else
        log_info "  未发现审计日志或查询权限不足"
    fi

    # 检查常见的高成本审计日志
    log_info "检查高成本审计日志类型..."

    high_cost_services=("storage.googleapis.com" "bigquery.googleapis.com" "compute.googleapis.com")

    for service in "${high_cost_services[@]}"; do
        service_log_count=$(gcloud logging read \
            'protoPayload.serviceName="'$service'" AND protoPayload.methodName!~".*list.*" AND timestamp>="'$(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%SZ)'"' \
            --project="$PROJECT_ID" \
            --limit=100 \
            --format="value(timestamp)" 2>/dev/null | wc -l)

        if [ "$service_log_count" -gt 50 ]; then
            log_warning "  $service 审计日志较多: $service_log_count 条，考虑优化"
        elif [ "$service_log_count" -gt 0 ]; then
            log_info "  $service 审计日志: $service_log_count 条"
        fi
    done

    echo ""
}

```
