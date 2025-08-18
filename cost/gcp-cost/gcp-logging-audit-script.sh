#!/bin/bash
#
# gcp-logging-audit-script.sh - GCP 项目日志配置审计脚本
#
# 功能:
# 1. 审计 GCP 项目的日志配置
# 2. 检查日志桶、接收器、排除项配置
# 3. 分析 GKE 集群日志设置
# 4. 生成成本优化建议报告
#
# 使用方法:
# ./gcp-logging-audit-script.sh [PROJECT_ID]
#
# 如果不提供 PROJECT_ID，脚本将审计当前活动项目

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要的工具
check_prerequisites() {
    log_info "检查必要工具..."
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI 未安装或不在 PATH 中"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl 未安装，将跳过 GKE 集群检查"
    fi
    
    # 检查 gcloud 认证状态
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "gcloud 未认证，请运行 'gcloud auth login'"
        exit 1
    fi
    
    log_success "工具检查完成"
}

# 获取项目信息
get_project_info() {
    if [ -n "$1" ]; then
        PROJECT_ID="$1"
        gcloud config set project "$PROJECT_ID" > /dev/null 2>&1
    else
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            log_error "无法获取项目 ID，请提供项目 ID 作为参数"
            exit 1
        fi
    fi
    
    log_info "审计项目: $PROJECT_ID"
    
    # 验证项目访问权限
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        log_error "无法访问项目 $PROJECT_ID，请检查权限"
        exit 1
    fi
}

# 审计日志桶配置
audit_log_buckets() {
    log_info "=== 审计日志桶配置 ==="
    
    echo "项目: $PROJECT_ID"
    echo "时间: $(date)"
    echo ""
    
    # 获取日志桶列表
    log_info "获取日志桶列表..."
    buckets_output=$(gcloud logging buckets list --project="$PROJECT_ID" --format="table(name,retentionDays,location,lifecycleState)" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$buckets_output" ]; then
        echo "$buckets_output"
        echo ""
        
        # 分析保留策略
        log_info "分析保留策略..."
        while IFS= read -r line; do
            if [[ "$line" =~ _Default.*([0-9]+) ]]; then
                retention_days=$(echo "$line" | grep -o '[0-9]\+' | head -1)
                if [ "$retention_days" -gt 30 ]; then
                    log_warning "默认桶保留期较长: ${retention_days} 天，考虑缩短以节省成本"
                elif [ "$retention_days" -le 7 ]; then
                    log_success "默认桶保留期已优化: ${retention_days} 天"
                fi
            fi
        done <<< "$buckets_output"
    else
        log_warning "无法获取日志桶信息或项目无自定义日志桶"
    fi
    
    echo ""
}

# 审计日志接收器配置
audit_log_sinks() {
    log_info "=== 审计日志接收器配置 ==="
    
    # 获取接收器列表
    sinks_output=$(gcloud logging sinks list --project="$PROJECT_ID" --format="table(name,destination,filter)" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$sinks_output" ]; then
        echo "$sinks_output"
        echo ""
        
        # 检查是否有归档接收器
        if echo "$sinks_output" | grep -q "storage.googleapis.com"; then
            log_success "发现 GCS 归档接收器，有助于长期成本控制"
        else
            log_warning "未发现 GCS 归档接收器，考虑设置长期归档以降低存储成本"
        fi
        
        if echo "$sinks_output" | grep -q "bigquery.googleapis.com"; then
            log_info "发现 BigQuery 接收器，注意查询成本"
        fi
    else
        log_warning "无法获取接收器信息或项目无自定义接收器"
    fi
    
    echo ""
}

# 审计排除项配置
audit_exclusions() {
    log_info "=== 审计排除项配置 ==="
    
    # 获取全局排除项
    exclusions_output=$(gcloud logging exclusions list --project="$PROJECT_ID" --format="table(name,filter,disabled)" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$exclusions_output" ]; then
        echo "$exclusions_output"
        echo ""
        
        exclusion_count=$(echo "$exclusions_output" | wc -l)
        if [ "$exclusion_count" -gt 1 ]; then
            log_success "发现 $((exclusion_count-1)) 个排除项，有助于成本控制"
        else
            log_warning "未发现排除项，考虑添加过滤器以减少日志注入成本"
        fi
    else
        log_warning "无法获取排除项信息或项目无排除项配置"
    fi
    
    echo ""
}

# 审计 GKE 集群配置
audit_gke_clusters() {
    log_info "=== 审计 GKE 集群日志配置 ==="
    
    # 获取 GKE 集群列表
    clusters=$(gcloud container clusters list --project="$PROJECT_ID" --format="value(name,location)" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$clusters" ]; then
        while IFS=$'\t' read -r cluster_name location; do
            if [ -n "$cluster_name" ] && [ -n "$location" ]; then
                log_info "检查集群: $cluster_name (位置: $location)"
                
                # 获取集群日志配置
                logging_config=$(gcloud container clusters describe "$cluster_name" \
                    --location="$location" \
                    --project="$PROJECT_ID" \
                    --format="value(loggingConfig.enableComponents)" 2>/dev/null)
                
                if [ -n "$logging_config" ]; then
                    echo "  日志组件: $logging_config"
                    
                    if [[ "$logging_config" == *"SYSTEM_COMPONENTS"* ]] && [[ "$logging_config" == *"WORKLOADS"* ]]; then
                        log_warning "  集群启用了完整日志收集，考虑在非生产环境中禁用 WORKLOADS"
                    elif [[ "$logging_config" == *"SYSTEM_COMPONENTS"* ]]; then
                        log_success "  集群仅启用系统日志，成本已优化"
                    else
                        log_info "  集群日志配置: $logging_config"
                    fi
                else
                    log_warning "  无法获取集群日志配置"
                fi
                
                # 检查集群监控配置
                monitoring_config=$(gcloud container clusters describe "$cluster_name" \
                    --location="$location" \
                    --project="$PROJECT_ID" \
                    --format="value(monitoringConfig.enableComponents)" 2>/dev/null)
                
                if [ -n "$monitoring_config" ]; then
                    echo "  监控组件: $monitoring_config"
                fi
                
                echo ""
            fi
        done <<< "$clusters"
    else
        log_info "项目中未发现 GKE 集群"
    fi
    
    echo ""
}

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

# 生成成本优化建议
generate_recommendations() {
    log_info "=== 成本优化建议 ==="
    
    echo "基于审计结果，以下是成本优化建议："
    echo ""
    
    echo "1. 日志保留策略优化:"
    echo "   - 非生产环境建议保留 7-14 天"
    echo "   - 生产环境根据合规要求设置 30-90 天"
    echo "   - 使用自定义日志桶实现差异化保留策略"
    echo ""
    
    echo "2. 排除过滤器建议:"
    echo "   - 添加健康检查日志过滤器"
    echo "   - 过滤低严重性日志（DEBUG, INFO）"
    echo "   - 排除系统组件噪音日志"
    echo ""
    
    echo "3. GKE 集群优化:"
    echo "   - 非生产环境考虑仅启用 SYSTEM_COMPONENTS"
    echo "   - 优化应用日志级别配置"
    echo "   - 实施容器级日志过滤"
    echo ""
    
    echo "4. 审计日志优化:"
    echo "   - 审查并禁用非必要的数据访问日志"
    echo "   - 在非生产环境中禁用详细审计日志"
    echo ""
    
    echo "5. 归档策略:"
    echo "   - 设置 GCS 归档接收器用于长期存储"
    echo "   - 使用 Archive 存储类别降低长期成本"
    echo ""
    
    echo "6. 监控和告警:"
    echo "   - 设置日志量监控指标"
    echo "   - 配置成本异常告警"
    echo "   - 建立定期审查流程"
    echo ""
}

# 生成配置脚本
generate_config_scripts() {
    log_info "=== 生成配置脚本 ==="
    
    # 创建优化脚本目录
    mkdir -p "./gcp-logging-optimization"
    
    # 生成日志桶创建脚本
    cat > "./gcp-logging-optimization/create-optimized-buckets.sh" << 'EOF'
#!/bin/bash
# 创建优化的日志桶配置

PROJECT_ID=${1:-$(gcloud config get-value project)}

echo "为项目 $PROJECT_ID 创建优化的日志桶..."

# 开发环境日志桶 - 7天保留
gcloud logging buckets create dev-logs-bucket \
  --location=global \
  --retention-days=7 \
  --description="Development environment logs with 7-day retention" \
  --project="$PROJECT_ID"

# 测试环境日志桶 - 14天保留
gcloud logging buckets create test-logs-bucket \
  --location=global \
  --retention-days=14 \
  --description="Test environment logs with 14-day retention" \
  --project="$PROJECT_ID"

# 生产环境日志桶 - 90天保留
gcloud logging buckets create prod-logs-bucket \
  --location=global \
  --retention-days=90 \
  --description="Production environment logs with 90-day retention" \
  --project="$PROJECT_ID"

echo "日志桶创建完成"
EOF

    # 生成排除过滤器脚本
    cat > "./gcp-logging-optimization/create-exclusion-filters.sh" << 'EOF'
#!/bin/bash
# 创建成本优化的排除过滤器

PROJECT_ID=${1:-$(gcloud config get-value project)}

echo "为项目 $PROJECT_ID 创建排除过滤器..."

# 排除健康检查日志
gcloud logging exclusions create exclude-health-checks \
  --description="Exclude Kubernetes health check logs" \
  --log-filter='resource.type="k8s_container" AND httpRequest.userAgent =~ "kube-probe"' \
  --project="$PROJECT_ID"

# 排除低严重性日志（非生产环境）
gcloud logging exclusions create exclude-low-severity \
  --description="Exclude low severity logs in non-production" \
  --log-filter='resource.type="k8s_container" AND severity < WARNING AND resource.labels.project_id!="prod-project-id"' \
  --project="$PROJECT_ID"

# 排除 Istio 代理日志
gcloud logging exclusions create exclude-istio-proxy \
  --description="Exclude Istio proxy container logs" \
  --log-filter='resource.type="k8s_container" AND resource.labels.container_name="istio-proxy"' \
  --project="$PROJECT_ID"

echo "排除过滤器创建完成"
EOF

    # 生成 GCS 归档脚本
    cat > "./gcp-logging-optimization/setup-gcs-archive.sh" << 'EOF'
#!/bin/bash
# 设置 GCS 归档

PROJECT_ID=${1:-$(gcloud config get-value project)}
BUCKET_NAME="${PROJECT_ID}-log-archive"

echo "为项目 $PROJECT_ID 设置 GCS 归档..."

# 创建归档存储桶
gsutil mb -c ARCHIVE -l us-central1 "gs://$BUCKET_NAME"

# 创建归档接收器
gcloud logging sinks create archive-to-gcs \
  "storage.googleapis.com/$BUCKET_NAME" \
  --log-filter='severity>=INFO' \
  --project="$PROJECT_ID"

# 设置生命周期策略
cat > lifecycle.json << 'LIFECYCLE_EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
      "condition": {"age": 30}
    }
  ]
}
LIFECYCLE_EOF

gsutil lifecycle set lifecycle.json "gs://$BUCKET_NAME"
rm lifecycle.json

echo "GCS 归档设置完成"
EOF

    # 设置脚本执行权限
    chmod +x "./gcp-logging-optimization/"*.sh
    
    log_success "配置脚本已生成到 ./gcp-logging-optimization/ 目录"
}

# 主函数
main() {
    echo "========================================"
    echo "    GCP 日志配置审计脚本"
    echo "========================================"
    echo ""
    
    check_prerequisites
    get_project_info "$1"
    
    # 执行审计
    audit_log_buckets
    audit_log_sinks
    audit_exclusions
    audit_gke_clusters
    audit_audit_logs
    
    # 生成建议和脚本
    generate_recommendations
    generate_config_scripts
    
    echo "========================================"
    log_success "审计完成！"
    echo "详细的配置脚本已生成到 ./gcp-logging-optimization/ 目录"
    echo "请根据建议调整您的日志配置以优化成本"
    echo "========================================"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi