- gcp-logging-audit-script.sh
```bash
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

# 审计日志桶配置 this filter need re-fix 
audit_log_buckets() {
    log_info "=== 审计日志桶配置 ==="
    
    echo "项目: $PROJECT_ID"
    echo "时间: $(date)"
    echo ""
    
    # 获取日志桶列表
    log_info "获取日志桶列表..."
    # need fix thie one . 
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

# 审计排除项配置 this gcloud is a bugs 
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
audit_gke_clusterss() {
    log_info "=== 审计 GKE 集群日志配置 ==="
    
    # 获取 GKE 集群列表
    clusterss=$(gcloud container clusterss list --project="$PROJECT_ID" --format="value(name,location)" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$clusterss" ]; then
        while IFS=$'\t' read -r clusters_name location; do
            if [ -n "$clusters_name" ] && [ -n "$location" ]; then
                log_info "检查集群: $clusters_name (位置: $location)"
                
                # 获取集群日志配置
                logging_config=$(gcloud container clusterss describe "$clusters_name" \
                    --location="$location" \
                    --project="$PROJECT_ID" \
                    --format="value(loggingConfig.componentConfig.enableComponents)" 2>/dev/null)
                
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
                monitoring_config=$(gcloud container clusterss describe "$clusters_name" \
                    --location="$location" \
                    --project="$PROJECT_ID" \
                    --format="value(monitoringConfig.componentConfig.enableComponents)" 2>/dev/null)
                
                if [ -n "$monitoring_config" ]; then
                    echo "  监控组件: $monitoring_config"
                fi
                
                echo ""
            fi
        done <<< "$clusterss"
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
    # audit_exclusions need re-debug this one   
    audit_gke_clusterss
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
```
- another 
- gcp-logging-quick-setup.sh
```bash
#!/bin/bash
#
# gcp-logging-quick-setup.sh - GCP 日志成本优化快速设置脚本
#
# 此脚本提供了快速设置 GCP 日志成本优化的交互式界面
# 支持多环境配置和一键部署
#
# 使用方法:
# ./gcp-logging-quick-setup.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_header() {
    echo -e "${PURPLE}$1${NC}"
}

# 显示欢迎信息
show_welcome() {
    clear
    log_header "========================================"
    log_header "    GCP 日志成本优化快速设置工具"
    log_header "========================================"
    echo ""
    echo "此工具将帮助您："
    echo "1. 审计当前日志配置"
    echo "2. 设置成本优化策略"
    echo "3. 部署 Terraform 配置"
    echo "4. 生成监控和告警"
    echo ""
}

# 检查必要工具
check_tools() {
    log_info "检查必要工具..."
    
    local missing_tools=()
    
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        echo ""
        echo "请安装缺少的工具后重新运行此脚本"
        echo ""
        echo "安装指南:"
        echo "- gcloud: https://cloud.google.com/sdk/docs/install"
        echo "- terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        echo "- python3: https://www.python.org/downloads/"
        exit 1
    fi
    
    log_success "所有必要工具已安装"
}

# 获取项目信息
get_project_info() {
    echo ""
    log_info "配置项目信息..."
    
    # 获取当前项目
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -n "$current_project" ]; then
        echo "当前活动项目: $current_project"
        read -p "是否使用当前项目? (y/n): " use_current
        if [[ $use_current =~ ^[Yy]$ ]]; then
            PROJECT_ID="$current_project"
        fi
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        read -p "请输入 GCP 项目 ID: " PROJECT_ID
    fi
    
    # 验证项目访问权限
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        log_error "无法访问项目 $PROJECT_ID，请检查权限"
        exit 1
    fi
    
    log_success "项目配置完成: $PROJECT_ID"
}

# 选择环境类型
select_environment() {
    echo ""
    log_info "选择环境类型..."
    
    echo "请选择环境类型:"
    echo "1) 开发环境 (dev) - 7天保留，ERROR+级别，激进成本优化"
    echo "2) 测试环境 (test) - 14天保留，WARNING+级别，中等成本优化"
    echo "3) 预生产环境 (staging) - 30天保留，INFO+级别，保守成本优化"
    echo "4) 生产环境 (prod) - 90天保留，INFO+级别，最小成本优化"
    
    while true; do
        read -p "请选择 (1-4): " env_choice
        case $env_choice in
            1) ENVIRONMENT="dev"; break;;
            2) ENVIRONMENT="test"; break;;
            3) ENVIRONMENT="staging"; break;;
            4) ENVIRONMENT="prod"; break;;
            *) echo "请输入有效选项 (1-4)";;
        esac
    done
    
    log_success "环境类型: $ENVIRONMENT"
}

# 配置优化选项
configure_optimization() {
    echo ""
    log_info "配置优化选项..."
    
    # GCS 归档
    read -p "是否启用 GCS 归档? (y/n): " enable_archive
    if [[ $enable_archive =~ ^[Yy]$ ]]; then
        ENABLE_GCS_ARCHIVE="true"
    else
        ENABLE_GCS_ARCHIVE="false"
    fi
    
    # 成本优化过滤器
    read -p "是否启用成本优化过滤器? (y/n): " enable_filters
    if [[ $enable_filters =~ ^[Yy]$ ]]; then
        ENABLE_FILTERS="true"
    else
        ENABLE_FILTERS="false"
    fi
    
    log_success "优化选项配置完成"
}

# 运行审计
run_audit() {
    echo ""
    log_info "运行日志配置审计..."
    
    if [ -f "./gcp-logging-audit-script.sh" ]; then
        ./gcp-logging-audit-script.sh "$PROJECT_ID"
    else
        log_warning "审计脚本不存在，跳过审计步骤"
    fi
}

# 部署 Terraform 配置
deploy_terraform() {
    echo ""
    log_info "部署 Terraform 配置..."
    
    if [ ! -f "./gcp-logging-terraform-module.tf" ]; then
        log_error "Terraform 模块文件不存在"
        return 1
    fi
    
    # 创建 terraform.tfvars 文件
    cat > terraform.tfvars << EOF
project_id = "$PROJECT_ID"
environment = "$ENVIRONMENT"
enable_gcs_archive = $ENABLE_GCS_ARCHIVE
enable_cost_optimization_filters = $ENABLE_FILTERS
EOF
    
    log_info "初始化 Terraform..."
    terraform init
    
    log_info "规划部署..."
    terraform plan
    
    echo ""
    read -p "是否继续部署? (y/n): " deploy_confirm
    if [[ $deploy_confirm =~ ^[Yy]$ ]]; then
        log_info "开始部署..."
        terraform apply -auto-approve
        log_success "Terraform 部署完成"
    else
        log_info "跳过部署"
    fi
}

# 运行成本分析
run_cost_analysis() {
    echo ""
    log_info "运行成本分析..."
    
    if [ ! -f "./gcp-logging-cost-analysis.py" ]; then
        log_warning "成本分析脚本不存在，跳过分析步骤"
        return
    fi
    
    # 检查 Python 依赖
    log_info "检查 Python 依赖..."
    if ! python3 -c "import google.cloud.logging, pandas, matplotlib" 2>/dev/null; then
        log_warning "缺少 Python 依赖，尝试安装..."
        pip3 install google-cloud-logging google-cloud-monitoring pandas matplotlib
    fi
    
    # 运行分析
    log_info "开始成本分析..."
    python3 gcp-logging-cost-analysis.py "$PROJECT_ID" --days 30 --output-dir ./reports/
    
    log_success "成本分析完成，报告保存在 ./reports/ 目录"
}

# 生成配置摘要
generate_summary() {
    echo ""
    log_header "========================================"
    log_header "           配置摘要"
    log_header "========================================"
    
    echo "项目 ID: $PROJECT_ID"
    echo "环境类型: $ENVIRONMENT"
    echo "GCS 归档: $ENABLE_GCS_ARCHIVE"
    echo "成本优化过滤器: $ENABLE_FILTERS"
    echo ""
    
    # 预期成本节省
    case $ENVIRONMENT in
        "dev")
            echo "预期成本节省: 70-80%"
            echo "保留策略: 7天"
            echo "日志级别: ERROR+"
            ;;
        "test")
            echo "预期成本节省: 60-70%"
            echo "保留策略: 14天"
            echo "日志级别: WARNING+"
            ;;
        "staging")
            echo "预期成本节省: 30-40%"
            echo "保留策略: 30天"
            echo "日志级别: INFO+"
            ;;
        "prod")
            echo "预期成本节省: 20-30%"
            echo "保留策略: 90天"
            echo "日志级别: INFO+"
            ;;
    esac
    
    echo ""
    log_header "========================================"
}

# 显示后续步骤
show_next_steps() {
    echo ""
    log_info "后续步骤建议:"
    echo ""
    echo "1. 监控成本变化:"
    echo "   - 查看 GCP 控制台的计费报告"
    echo "   - 使用生成的监控指标"
    echo ""
    echo "2. 定期审查:"
    echo "   - 每月运行成本分析脚本"
    echo "   - 根据需要调整过滤器"
    echo ""
    echo "3. 扩展到其他项目:"
    echo "   - 使用相同配置部署到其他环境"
    echo "   - 根据项目特点调整参数"
    echo ""
    echo "4. 持续优化:"
    echo "   - 监控日志量变化"
    echo "   - 根据业务需求调整策略"
    echo ""
}

# 主菜单
show_menu() {
    while true; do
        echo ""
        log_header "========================================"
        log_header "           主菜单"
        log_header "========================================"
        echo "1) 完整设置流程（推荐）"
        echo "2) 仅运行审计"
        echo "3) 仅部署 Terraform"
        echo "4) 仅运行成本分析"
        echo "5) 显示配置摘要"
        echo "6) 退出"
        echo ""
        
        read -p "请选择操作 (1-6): " menu_choice
        
        case $menu_choice in
            1)
                get_project_info
                select_environment
                configure_optimization
                run_audit
                deploy_terraform
                run_cost_analysis
                generate_summary
                show_next_steps
                break
                ;;
            2)
                get_project_info
                run_audit
                ;;
            3)
                get_project_info
                select_environment
                configure_optimization
                deploy_terraform
                ;;
            4)
                get_project_info
                run_cost_analysis
                ;;
            5)
                if [ -n "$PROJECT_ID" ]; then
                    generate_summary
                else
                    log_warning "请先配置项目信息"
                fi
                ;;
            6)
                log_info "退出程序"
                exit 0
                ;;
            *)
                log_error "请输入有效选项 (1-6)"
                ;;
        esac
    done
}

# 主函数
main() {
    show_welcome
    check_tools
    show_menu
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```
- gcp-logging-quick-setup.sh
```bash
#!/usr/bin/env python3
"""
GCP 日志成本分析脚本

此脚本用于分析 GCP 项目的日志成本，包括：
1. 获取日志使用量统计
2. 分析成本趋势
3. 生成优化建议报告
4. 预测成本节省效果

依赖:
- google-cloud-logging
- google-cloud-billing
- google-cloud-monitoring
- pandas
- matplotlib

安装依赖:
pip install google-cloud-logging google-cloud-billing google-cloud-monitoring pandas matplotlib
"""

import os
import sys
import json
import argparse
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import pandas as pd
import matplotlib.pyplot as plt
from google.cloud import logging
from google.cloud import monitoring_v3
from google.oauth2 import service_account
import warnings
warnings.filterwarnings('ignore')

class GCPLoggingCostAnalyzer:
    """GCP 日志成本分析器"""
    
    def __init__(self, project_id: str, credentials_path: Optional[str] = None):
        """
        初始化分析器
        
        Args:
            project_id: GCP 项目 ID
            credentials_path: 服务账号密钥文件路径（可选）
        """
        self.project_id = project_id
        
        # 初始化客户端
        if credentials_path:
            credentials = service_account.Credentials.from_service_account_file(credentials_path)
            self.logging_client = logging.Client(project=project_id, credentials=credentials)
            self.monitoring_client = monitoring_v3.MetricServiceClient(credentials=credentials)
        else:
            self.logging_client = logging.Client(project=project_id)
            self.monitoring_client = monitoring_v3.MetricServiceClient()
        
        # 成本常量（美元）
        self.INGESTION_COST_PER_GIB = 0.50
        self.STORAGE_COST_PER_GIB_MONTH = 0.01
        self.FREE_TIER_GIB = 50
        
        print(f"✅ 已初始化项目 {project_id} 的日志成本分析器")
    
    def get_log_volume_stats(self, days: int = 30) -> Dict:
        """
        获取指定天数内的日志量统计
        
        Args:
            days: 分析的天数
            
        Returns:
            包含日志量统计的字典
        """
        print(f"📊 分析最近 {days} 天的日志量...")
        
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)
        
        # 构建查询过滤器
        filter_str = f'timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"'
        
        stats = {
            'total_entries': 0,
            'by_resource_type': {},
            'by_severity': {},
            'by_day': {},
            'estimated_size_gib': 0
        }
        
        try:
            # 获取日志条目
            entries = self.logging_client.list_entries(filter_=filter_str, page_size=1000)
            
            for entry in entries:
                stats['total_entries'] += 1
                
                # 按资源类型统计
                resource_type = entry.resource.type if entry.resource else 'unknown'
                stats['by_resource_type'][resource_type] = stats['by_resource_type'].get(resource_type, 0) + 1
                
                # 按严重性统计
                severity = entry.severity.name if entry.severity else 'UNKNOWN'
                stats['by_severity'][severity] = stats['by_severity'].get(severity, 0) + 1
                
                # 按日期统计
                day = entry.timestamp.date().isoformat()
                stats['by_day'][day] = stats['by_day'].get(day, 0) + 1
                
                # 估算大小（每条日志平均 1KB）
                stats['estimated_size_gib'] += 0.001 / 1024  # 1KB to GiB
        
        except Exception as e:
            print(f"⚠️  获取日志统计时出错: {e}")
            return stats
        
        print(f"✅ 分析完成，共处理 {stats['total_entries']} 条日志")
        return stats
    
    def analyze_cost_by_resource_type(self, stats: Dict) -> pd.DataFrame:
        """
        按资源类型分析成本
        
        Args:
            stats: 日志量统计数据
            
        Returns:
            成本分析 DataFrame
        """
        print("💰 分析各资源类型的成本...")
        
        resource_data = []
        total_size_gib = stats['estimated_size_gib']
        
        for resource_type, count in stats['by_resource_type'].items():
            # 计算该资源类型的大小占比
            size_ratio = count / stats['total_entries'] if stats['total_entries'] > 0 else 0
            size_gib = total_size_gib * size_ratio
            
            # 计算成本
            ingestion_cost = max(0, size_gib - self.FREE_TIER_GIB) * self.INGESTION_COST_PER_GIB
            storage_cost = size_gib * self.STORAGE_COST_PER_GIB_MONTH
            total_cost = ingestion_cost + storage_cost
            
            resource_data.append({
                'resource_type': resource_type,
                'log_count': count,
                'size_gib': round(size_gib, 3),
                'ingestion_cost': round(ingestion_cost, 2),
                'storage_cost': round(storage_cost, 2),
                'total_cost': round(total_cost, 2),
                'percentage': round(size_ratio * 100, 1)
            })
        
        df = pd.DataFrame(resource_data)
        df = df.sort_values('total_cost', ascending=False)
        
        return df
    
    def generate_optimization_recommendations(self, cost_df: pd.DataFrame, stats: Dict) -> List[Dict]:
        """
        生成成本优化建议
        
        Args:
            cost_df: 成本分析 DataFrame
            stats: 日志量统计
            
        Returns:
            优化建议列表
        """
        print("🎯 生成成本优化建议...")
        
        recommendations = []
        
        # 1. 高成本资源类型建议
        high_cost_resources = cost_df[cost_df['total_cost'] > 10].head(3)
        if not high_cost_resources.empty:
            for _, row in high_cost_resources.iterrows():
                recommendations.append({
                    'type': 'high_cost_resource',
                    'priority': 'HIGH',
                    'resource_type': row['resource_type'],
                    'current_cost': row['total_cost'],
                    'recommendation': f"考虑为 {row['resource_type']} 添加排除过滤器，当前月成本约 ${row['total_cost']}",
                    'potential_savings': round(row['total_cost'] * 0.6, 2)
                })
        
        # 2. 日志级别优化建议
        severity_stats = stats['by_severity']
        debug_info_count = severity_stats.get('DEBUG', 0) + severity_stats.get('INFO', 0)
        total_count = stats['total_entries']
        
        if debug_info_count > total_count * 0.5:  # 超过50%是DEBUG/INFO日志
            potential_savings = (debug_info_count / total_count) * stats['estimated_size_gib'] * self.INGESTION_COST_PER_GIB
            recommendations.append({
                'type': 'severity_filter',
                'priority': 'HIGH',
                'recommendation': f"过滤 DEBUG/INFO 级别日志可显著降低成本，占比 {round(debug_info_count/total_count*100, 1)}%",
                'potential_savings': round(potential_savings, 2)
            })
        
        # 3. 保留策略建议
        if stats['estimated_size_gib'] > 100:  # 大于100GB
            storage_savings = stats['estimated_size_gib'] * self.STORAGE_COST_PER_GIB_MONTH * 0.75  # 假设缩短75%保留时间
            recommendations.append({
                'type': 'retention_policy',
                'priority': 'MEDIUM',
                'recommendation': "考虑缩短非生产环境的日志保留期至7-14天",
                'potential_savings': round(storage_savings, 2)
            })
        
        # 4. GKE 特定建议
        gke_cost = cost_df[cost_df['resource_type'].str.contains('k8s', na=False)]['total_cost'].sum()
        if gke_cost > 20:
            recommendations.append({
                'type': 'gke_optimization',
                'priority': 'HIGH',
                'recommendation': f"GKE 日志成本较高 (${gke_cost:.2f})，建议实施健康检查过滤和容器日志优化",
                'potential_savings': round(gke_cost * 0.5, 2)
            })
        
        return recommendations
    
    def create_cost_visualization(self, cost_df: pd.DataFrame, stats: Dict, output_dir: str = "./"):
        """
        创建成本可视化图表
        
        Args:
            cost_df: 成本分析 DataFrame
            stats: 日志量统计
            output_dir: 输出目录
        """
        print("📈 生成成本可视化图表...")
        
        # 设置中文字体
        plt.rcParams['font.sans-serif'] = ['SimHei', 'Arial Unicode MS', 'DejaVu Sans']
        plt.rcParams['axes.unicode_minus'] = False
        
        # 创建子图
        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 12))
        fig.suptitle(f'GCP 日志成本分析报告 - 项目: {self.project_id}', fontsize=16, fontweight='bold')
        
        # 1. 按资源类型的成本分布
        top_resources = cost_df.head(8)
        ax1.pie(top_resources['total_cost'], labels=top_resources['resource_type'], autopct='%1.1f%%')
        ax1.set_title('按资源类型的成本分布')
        
        # 2. 按严重性的日志量分布
        severity_data = pd.Series(stats['by_severity'])
        ax2.bar(severity_data.index, severity_data.values)
        ax2.set_title('按严重性的日志量分布')
        ax2.set_xlabel('严重性级别')
        ax2.set_ylabel('日志条数')
        plt.setp(ax2.xaxis.get_majorticklabels(), rotation=45)
        
        # 3. 每日日志量趋势
        daily_data = pd.Series(stats['by_day']).sort_index()
        ax3.plot(daily_data.index, daily_data.values, marker='o')
        ax3.set_title('每日日志量趋势')
        ax3.set_xlabel('日期')
        ax3.set_ylabel('日志条数')
        plt.setp(ax3.xaxis.get_majorticklabels(), rotation=45)
        
        # 4. 成本构成分析
        total_ingestion = cost_df['ingestion_cost'].sum()
        total_storage = cost_df['storage_cost'].sum()
        cost_breakdown = pd.Series({
            '注入成本': total_ingestion,
            '存储成本': total_storage
        })
        ax4.pie(cost_breakdown.values, labels=cost_breakdown.index, autopct='%1.1f%%')
        ax4.set_title('成本构成分析')
        
        plt.tight_layout()
        
        # 保存图表
        output_path = os.path.join(output_dir, f'gcp_logging_cost_analysis_{self.project_id}.png')
        plt.savefig(output_path, dpi=300, bbox_inches='tight')
        print(f"📊 图表已保存到: {output_path}")
        
        plt.show()
    
    def generate_report(self, days: int = 30, output_dir: str = "./") -> str:
        """
        生成完整的成本分析报告
        
        Args:
            days: 分析天数
            output_dir: 输出目录
            
        Returns:
            报告文件路径
        """
        print("📋 生成完整成本分析报告...")
        
        # 获取数据
        stats = self.get_log_volume_stats(days)
        cost_df = self.analyze_cost_by_resource_type(stats)
        recommendations = self.generate_optimization_recommendations(cost_df, stats)
        
        # 生成报告
        report = {
            'project_id': self.project_id,
            'analysis_period': f'{days} days',
            'generated_at': datetime.utcnow().isoformat(),
            'summary': {
                'total_log_entries': stats['total_entries'],
                'estimated_size_gib': round(stats['estimated_size_gib'], 3),
                'estimated_monthly_cost': round(cost_df['total_cost'].sum(), 2),
                'top_cost_resource': cost_df.iloc[0]['resource_type'] if not cost_df.empty else 'N/A'
            },
            'cost_breakdown': cost_df.to_dict('records'),
            'log_statistics': stats,
            'optimization_recommendations': recommendations,
            'potential_total_savings': round(sum(r.get('potential_savings', 0) for r in recommendations), 2)
        }
        
        # 保存 JSON 报告
        report_path = os.path.join(output_dir, f'gcp_logging_cost_report_{self.project_id}_{datetime.now().strftime("%Y%m%d")}.json')
        with open(report_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        # 生成可视化图表
        if not cost_df.empty:
            self.create_cost_visualization(cost_df, stats, output_dir)
        
        # 打印摘要
        self.print_summary(report)
        
        print(f"📄 完整报告已保存到: {report_path}")
        return report_path
    
    def print_summary(self, report: Dict):
        """打印报告摘要"""
        print("\n" + "="*60)
        print("📊 GCP 日志成本分析摘要")
        print("="*60)
        
        summary = report['summary']
        print(f"项目 ID: {report['project_id']}")
        print(f"分析期间: {report['analysis_period']}")
        print(f"总日志条数: {summary['total_log_entries']:,}")
        print(f"估算大小: {summary['estimated_size_gib']} GiB")
        print(f"估算月成本: ${summary['estimated_monthly_cost']}")
        print(f"主要成本来源: {summary['top_cost_resource']}")
        
        print(f"\n🎯 优化建议数量: {len(report['optimization_recommendations'])}")
        print(f"💰 潜在总节省: ${report['potential_total_savings']}")
        
        print("\n📋 主要建议:")
        for i, rec in enumerate(report['optimization_recommendations'][:3], 1):
            print(f"{i}. [{rec['priority']}] {rec['recommendation']}")
            if 'potential_savings' in rec:
                print(f"   💰 潜在节省: ${rec['potential_savings']}")
        
        print("="*60)

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='GCP 日志成本分析工具')
    parser.add_argument('project_id', help='GCP 项目 ID')
    parser.add_argument('--days', type=int, default=30, help='分析天数 (默认: 30)')
    parser.add_argument('--credentials', help='服务账号密钥文件路径')
    parser.add_argument('--output-dir', default='./', help='输出目录 (默认: 当前目录)')
    
    args = parser.parse_args()
    
    try:
        # 创建分析器
        analyzer = GCPLoggingCostAnalyzer(args.project_id, args.credentials)
        
        # 生成报告
        report_path = analyzer.generate_report(args.days, args.output_dir)
        
        print(f"\n✅ 分析完成！报告已保存到: {report_path}")
        
    except Exception as e:
        print(f"❌ 分析过程中出错: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
```