#!/opt/homebrew/bin/bash

# Optimized GKE Namespace Statistics Script - Fast execution with migration focus
# Usage: ./get-ns-stats-optimized.sh -n <namespace> [-o output_dir]

set -e

# Default values
NAMESPACE=""
OUTPUT_DIR="./migration-info"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    echo "Usage: $0 -n <namespace> [-o output_directory]"
    echo "  -n: Kubernetes namespace to analyze"
    echo "  -o: Output directory (default: ./migration-info)"
    echo "  -h: Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:o:h" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Check if namespace is provided
if [ -z "$NAMESPACE" ]; then
    print_error "命名空间是必需的!"
    usage
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/namespace-${NAMESPACE}-stats-${TIMESTAMP}.md"

print_info "开始分析命名空间: $NAMESPACE"

# Check dependencies
check_dependencies() {
    for cmd in kubectl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "$cmd 未安装或不在PATH中"
            exit 1
        fi
    done
}

# Check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "命名空间 '$NAMESPACE' 不存在!"
        exit 1
    fi
}

# Optimized resource fetching with error handling
fetch_all_resources_optimized() {
    print_info "获取所有资源数据..."
    
    # Helper function to safely get resources
    safe_kubectl_get() {
        local resource_type="$1"
        local namespace="$2"
        if kubectl get "$resource_type" -n "$namespace" -o json 2>/dev/null; then
            return 0
        else
            # Check if it's a known optional resource
            if [[ "$resource_type" =~ (vpa|networkpolicies) ]]; then
                print_warning "资源类型 '$resource_type' 不可用，已跳过"
            fi
            echo '{"items":[]}'
        fi
    }
    
    # Use kubectl get to fetch resources with error handling
    {
        echo "=== WORKLOADS ==="
        safe_kubectl_get "deployments,daemonsets,statefulsets,jobs,cronjobs" "$NAMESPACE"
        echo "=== SERVICES ==="
        safe_kubectl_get "services" "$NAMESPACE"
        echo "=== CONFIG ==="
        safe_kubectl_get "configmaps,secrets,serviceaccounts" "$NAMESPACE"
        echo "=== STORAGE ==="
        safe_kubectl_get "persistentvolumeclaims" "$NAMESPACE"
        echo "=== NETWORKING ==="
        safe_kubectl_get "ingress" "$NAMESPACE"
        # Try to get networkpolicies separately as they may not exist
        kubectl get networkpolicies -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}'
        echo "=== SCALING ==="
        safe_kubectl_get "hpa" "$NAMESPACE"
        # Try VPA separately as it may not be installed
        kubectl get vpa -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}'
        echo "=== MIGRATION_SPECIFIC ==="
        safe_kubectl_get "rolebindings,roles" "$NAMESPACE"
        safe_kubectl_get "pods" "$NAMESPACE"
    } > /tmp/all_resources.json
    
    print_success "所有资源获取完成"
}

# Parse and split the combined JSON into separate files
parse_resources() {
    print_info "解析资源数据..."
    
    # Extract different resource types from the combined output with safer parsing
    if [ -f /tmp/all_resources.json ]; then
        # Create empty JSON files first
        echo '{"items":[]}' > /tmp/workloads.json
        echo '{"items":[]}' > /tmp/services.json
        echo '{"items":[]}' > /tmp/config.json
        echo '{"items":[]}' > /tmp/storage.json
        echo '{"items":[]}' > /tmp/networking.json
        echo '{"items":[]}' > /tmp/scaling.json
        echo '{"items":[]}' > /tmp/migration.json
        
        # Parse each section if it exists
        if grep -q "=== WORKLOADS ===" /tmp/all_resources.json; then
            awk '/=== WORKLOADS ===/,/=== SERVICES ===/' /tmp/all_resources.json | sed '1d;$d' > /tmp/workloads.json || echo '{"items":[]}' > /tmp/workloads.json
        fi
        
        if grep -q "=== SERVICES ===" /tmp/all_resources.json; then
            awk '/=== SERVICES ===/,/=== CONFIG ===/' /tmp/all_resources.json | sed '1d;$d' > /tmp/services.json || echo '{"items":[]}' > /tmp/services.json
        fi
        
        if grep -q "=== CONFIG ===" /tmp/all_resources.json; then
            awk '/=== CONFIG ===/,/=== STORAGE ===/' /tmp/all_resources.json | sed '1d;$d' > /tmp/config.json || echo '{"items":[]}' > /tmp/config.json
        fi
        
        if grep -q "=== STORAGE ===" /tmp/all_resources.json; then
            awk '/=== STORAGE ===/,/=== NETWORKING ===/' /tmp/all_resources.json | sed '1d;$d' > /tmp/storage.json || echo '{"items":[]}' > /tmp/storage.json
        fi
        
        if grep -q "=== NETWORKING ===" /tmp/all_resources.json; then
            awk '/=== NETWORKING ===/,/=== SCALING ===/' /tmp/all_resources.json | sed '1d;$d' > /tmp/networking.json || echo '{"items":[]}' > /tmp/networking.json
        fi
        
        if grep -q "=== SCALING ===" /tmp/all_resources.json; then
            awk '/=== SCALING ===/,/=== MIGRATION_SPECIFIC ===/' /tmp/all_resources.json | sed '1d;$d' > /tmp/scaling.json || echo '{"items":[]}' > /tmp/scaling.json
        fi
        
        if grep -q "=== MIGRATION_SPECIFIC ===" /tmp/all_resources.json; then
            awk '/=== MIGRATION_SPECIFIC ===/' /tmp/all_resources.json | tail -n +2 > /tmp/migration.json || echo '{"items":[]}' > /tmp/migration.json
        fi
    fi
}

# Single comprehensive jq query for workload analysis
analyze_workloads_comprehensive() {
    print_info "分析工作负载..."
    
    # Single jq command to extract all workload information
    jq -r '
    # Function to get container info from different workload types
    def get_containers:
        if .kind == "CronJob" then
            .spec.jobTemplate.spec.template.spec.containers[]?
        else
            .spec.template.spec.containers[]?
        end;
    
    # Function to get pod template spec
    def get_pod_spec:
        if .kind == "CronJob" then
            .spec.jobTemplate.spec.template.spec
        else
            .spec.template.spec
        end;
    
    .items[] |
    {
        kind: .kind,
        name: .metadata.name,
        # Extract images
        images: [get_containers | .image],
        # Extract service accounts
        serviceAccount: (get_pod_spec | .serviceAccountName // "default"),
        # Extract ports
        ports: [get_containers | .ports[]? | (.containerPort|tostring) + "/" + (.protocol // "TCP")],
        # Extract probes
        livenessProbes: [get_containers | select(.livenessProbe) | 
            if .livenessProbe.httpGet then "httpGet"
            elif .livenessProbe.tcpSocket then "tcpSocket"
            elif .livenessProbe.exec then "exec"
            else "unknown" end],
        readinessProbes: [get_containers | select(.readinessProbe) | 
            if .readinessProbe.httpGet then "httpGet"
            elif .readinessProbe.tcpSocket then "tcpSocket"
            elif .readinessProbe.exec then "exec"
            else "unknown" end],
        startupProbes: [get_containers | select(.startupProbe) | 
            if .startupProbe.httpGet then "httpGet"
            elif .startupProbe.tcpSocket then "tcpSocket"
            elif .startupProbe.exec then "exec"
            else "unknown" end],
        # Extract resources
        cpuRequests: [get_containers | select(.resources.requests.cpu) | .resources.requests.cpu],
        memoryRequests: [get_containers | select(.resources.requests.memory) | .resources.requests.memory],
        cpuLimits: [get_containers | select(.resources.limits.cpu) | .resources.limits.cpu],
        memoryLimits: [get_containers | select(.resources.limits.memory) | .resources.limits.memory],
        # Extract volumes
        volumes: [get_pod_spec | .volumes[]? | keys[] | select(. != "name")],
        # Extract security context
        securityContext: (get_pod_spec | .securityContext),
        # Extract node selectors and affinity (important for migration)
        nodeSelector: (get_pod_spec | .nodeSelector),
        affinity: (get_pod_spec | .affinity),
        tolerations: [get_pod_spec | .tolerations[]?]
    }' /tmp/workloads.json > /tmp/workload_analysis.json
}

# Generate statistics from analyzed data
generate_statistics() {
    print_info "生成统计报告..."
    
    # Initialize report
    cat > "$REPORT_FILE" << EOF
# Kubernetes命名空间统计报告

**命名空间:** $NAMESPACE  
**集群:** $(kubectl config current-context)  
**生成时间:** $(date)  

---

EOF

    # 1. 容器镜像统计
    echo "## 1. 容器镜像统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Extract and count images
    jq -r '.images[]' /tmp/workload_analysis.json | sort | uniq -c | sort -nr > /tmp/image_stats.txt
    
    echo "### 镜像使用次数统计" >> "$REPORT_FILE"
    echo "| 使用次数 | 镜像 |" >> "$REPORT_FILE"
    echo "|---------|------|" >> "$REPORT_FILE"
    while read -r count image; do
        echo "| $count | $image |" >> "$REPORT_FILE"
    done < /tmp/image_stats.txt
    echo "" >> "$REPORT_FILE"
    
    # Registry distribution
    echo "### 镜像仓库分布" >> "$REPORT_FILE"
    echo "| 使用次数 | 仓库 |" >> "$REPORT_FILE"
    echo "|---------|------|" >> "$REPORT_FILE"
    awk '{print $2}' /tmp/image_stats.txt | sed 's|/.*||' | sort | uniq -c | sort -nr | while read -r count registry; do
        echo "| $count | $registry |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    local total_images=$(wc -l < /tmp/image_stats.txt)
    echo "**唯一镜像总数:** $total_images" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 2. 健康探针统计
    echo "## 2. 健康探针统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    for probe_type in "livenessProbes" "readinessProbes" "startupProbes"; do
        # Convert probe type name to display name
        case $probe_type in
            "livenessProbes") probe_name="Liveness" ;;
            "readinessProbes") probe_name="Readiness" ;;
            "startupProbes") probe_name="Startup" ;;
        esac
        echo "### ${probe_name} 探针类型分布" >> "$REPORT_FILE"
        echo "| 使用次数 | 探针类型 |" >> "$REPORT_FILE"
        echo "|---------|----------|" >> "$REPORT_FILE"
        jq -r ".$probe_type[]" /tmp/workload_analysis.json | sort | uniq -c | sort -nr | while read -r count probe; do
            echo "| $count | $probe |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    done
    
    # 3. Service Account统计
    echo "## 3. Service Account统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### Service Account使用频率" >> "$REPORT_FILE"
    echo "| 使用次数 | Service Account |" >> "$REPORT_FILE"
    echo "|---------|-----------------|" >> "$REPORT_FILE"
    jq -r '.serviceAccount' /tmp/workload_analysis.json | sort | uniq -c | sort -nr | while read -r count sa; do
        echo "| $count | $sa |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # 4. 端口统计
    echo "## 4. 容器端口统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### 端口使用分布" >> "$REPORT_FILE"
    echo "| 使用次数 | 端口 | 协议 |" >> "$REPORT_FILE"
    echo "|---------|------|------|" >> "$REPORT_FILE"
    jq -r '.ports[]' /tmp/workload_analysis.json | sort | uniq -c | sort -nr | while read -r count port_proto; do
        local port=$(echo "$port_proto" | cut -d'/' -f1)
        local proto=$(echo "$port_proto" | cut -d'/' -f2)
        echo "| $count | $port | $proto |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # 5. Service统计
    echo "## 5. Service类型统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ -s /tmp/services.json ] && [ "$(jq '.items | length' /tmp/services.json)" -gt 0 ]; then
        echo "### Service类型分布" >> "$REPORT_FILE"
        echo "| 使用次数 | Service类型 |" >> "$REPORT_FILE"
        echo "|---------|-------------|" >> "$REPORT_FILE"
        jq -r '.items[].spec.type' /tmp/services.json | sort | uniq -c | sort -nr | while read -r count svc_type; do
            echo "| $count | $svc_type |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        echo "### Service端口分布" >> "$REPORT_FILE"
        echo "| 使用次数 | 端口 |" >> "$REPORT_FILE"
        echo "|---------|------|" >> "$REPORT_FILE"
        jq -r '.items[].spec.ports[].port' /tmp/services.json | sort -n | uniq -c | sort -nr | while read -r count port; do
            echo "| $count | $port |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    else
        echo "未找到Service资源" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    # 6. 资源需求统计
    echo "## 6. 资源需求统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # CPU/Memory requests and limits
    for resource_type in "cpuRequests" "memoryRequests" "cpuLimits" "memoryLimits"; do
        resource_name=$(echo $resource_type | sed 's/cpu/CPU /' | sed 's/memory/内存 /' | sed 's/Requests/请求/' | sed 's/Limits/限制/')
        echo "### ${resource_name}分布" >> "$REPORT_FILE"
        echo "| 使用次数 | ${resource_name} |" >> "$REPORT_FILE"
        echo "|---------|------------|" >> "$REPORT_FILE"
        jq -r ".$resource_type[]" /tmp/workload_analysis.json | sort | uniq -c | sort -nr | while read -r count resource; do
            echo "| $count | $resource |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    done
    
    # 7. 存储卷统计
    echo "## 7. 存储卷类型统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### 卷类型分布" >> "$REPORT_FILE"
    echo "| 使用次数 | 卷类型 |" >> "$REPORT_FILE"
    echo "|---------|--------|" >> "$REPORT_FILE"
    jq -r '.volumes[]' /tmp/workload_analysis.json | sort | uniq -c | sort -nr | while read -r count vol_type; do
        echo "| $count | $vol_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Migration-specific analysis
analyze_migration_requirements() {
    print_info "分析迁移需求..."
    
    echo "## 8. 迁移关键信息" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Node selectors and affinity
    echo "### 节点选择器和亲和性配置" >> "$REPORT_FILE"
    echo "| 工作负载 | 节点选择器 | 亲和性配置 |" >> "$REPORT_FILE"
    echo "|---------|-----------|------------|" >> "$REPORT_FILE"
    jq -r '. | select(.nodeSelector or .affinity) | 
        [.kind + "/" + .name, 
         (.nodeSelector | if . then tostring else "无" end), 
         (.affinity | if . then "是" else "无" end)] | @tsv' /tmp/workload_analysis.json | while IFS=$'\t' read -r workload nodesel affinity; do
        echo "| $workload | $nodesel | $affinity |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Tolerations
    echo "### 容忍度配置" >> "$REPORT_FILE"
    echo "| 工作负载 | 容忍度数量 |" >> "$REPORT_FILE"
    echo "|---------|-----------|" >> "$REPORT_FILE"
    jq -r '. | select(.tolerations | length > 0) | 
        [.kind + "/" + .name, (.tolerations | length)] | @tsv' /tmp/workload_analysis.json | while IFS=$'\t' read -r workload toleration_count; do
        echo "| $workload | $toleration_count |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # PVC analysis
    if [ -s /tmp/storage.json ] && [ "$(jq '.items | length' /tmp/storage.json)" -gt 0 ]; then
        echo "### 持久卷声明 (PVC)" >> "$REPORT_FILE"
        echo "| PVC名称 | 存储类 | 访问模式 | 大小 |" >> "$REPORT_FILE"
        echo "|---------|--------|----------|------|" >> "$REPORT_FILE"
        jq -r '.items[] | [.metadata.name, (.spec.storageClassName // "default"), (.spec.accessModes | join(",")), .spec.resources.requests.storage] | @tsv' /tmp/storage.json | while IFS=$'\t' read -r name sc mode size; do
            echo "| $name | $sc | $mode | $size |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Security contexts
    echo "### 安全上下文配置" >> "$REPORT_FILE"
    echo "| 工作负载 | 特权模式 | 用户ID | 组ID |" >> "$REPORT_FILE"
    echo "|---------|----------|--------|------|" >> "$REPORT_FILE"
    jq -r '. | select(.securityContext) | 
        [.kind + "/" + .name, 
         (.securityContext.privileged // false), 
         (.securityContext.runAsUser // "未设置"), 
         (.securityContext.runAsGroup // "未设置")] | @tsv' /tmp/workload_analysis.json | while IFS=$'\t' read -r workload privileged user group; do
        echo "| $workload | $privileged | $user | $group |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # RBAC analysis
    if [ -s /tmp/migration.json ]; then
        echo "### RBAC配置" >> "$REPORT_FILE"
        echo "| 类型 | 名称 | 主题类型 | 主题名称 |" >> "$REPORT_FILE"
        echo "|------|------|----------|----------|" >> "$REPORT_FILE"
        jq -r '.items[] | select(.kind == "RoleBinding") | 
            .subjects[]? as $subject | 
            [.kind, .metadata.name, $subject.kind, $subject.name] | @tsv' /tmp/migration.json | while IFS=$'\t' read -r kind name subject_kind subject_name; do
            echo "| $kind | $name | $subject_kind | $subject_name |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
}

# Generate migration checklist
generate_migration_checklist() {
    echo "## 9. 迁移检查清单" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### 必须检查的项目:" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- [ ] **容器镜像访问权限** - 确保目标集群能够拉取所有镜像" >> "$REPORT_FILE"
    echo "- [ ] **存储类兼容性** - 验证目标集群是否有相同的存储类" >> "$REPORT_FILE"
    echo "- [ ] **网络策略** - 检查目标集群的网络策略配置" >> "$REPORT_FILE"
    echo "- [ ] **Service Account权限** - 确保RBAC配置在目标集群中正确" >> "$REPORT_FILE"
    echo "- [ ] **节点标签和污点** - 验证节点选择器和容忍度配置" >> "$REPORT_FILE"
    echo "- [ ] **外部依赖** - 检查是否有外部服务依赖需要重新配置" >> "$REPORT_FILE"
    echo "- [ ] **ConfigMap和Secret** - 确保配置数据正确迁移" >> "$REPORT_FILE"
    echo "- [ ] **持久化数据** - 规划PV数据迁移策略" >> "$REPORT_FILE"
    echo "- [ ] **Ingress控制器** - 确保目标集群有兼容的Ingress控制器" >> "$REPORT_FILE"
    echo "- [ ] **监控和日志** - 重新配置监控和日志收集" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Additional migration resources to check
    echo "### 还需要检查的资源类型:" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "- **NetworkPolicies** - 网络安全策略" >> "$REPORT_FILE"
    echo "- **PodDisruptionBudgets** - Pod中断预算" >> "$REPORT_FILE"
    echo "- **ResourceQuotas** - 资源配额" >> "$REPORT_FILE"
    echo "- **LimitRanges** - 资源限制范围" >> "$REPORT_FILE"
    echo "- **CRDs和Custom Resources** - 自定义资源定义" >> "$REPORT_FILE"
    echo "- **Webhooks** - Admission webhooks和其他webhook配置" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Generate overall resource counts
generate_resource_summary() {
    print_info "生成资源汇总..."
    
    echo "# 资源总览" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Count resources from different files - ensure single numeric values
    local workload_count=$(jq '[.items[] | select(.kind | test("Deployment|DaemonSet|StatefulSet|Job|CronJob"))] | length' /tmp/workloads.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local svc_count=$(jq '.items | length' /tmp/services.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local cm_count=$(jq '[.items[] | select(.kind == "ConfigMap")] | length' /tmp/config.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local secret_count=$(jq '[.items[] | select(.kind == "Secret")] | length' /tmp/config.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local pvc_count=$(jq '.items | length' /tmp/storage.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local ing_count=$(jq '[.items[] | select(.kind == "Ingress")] | length' /tmp/networking.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local hpa_count=$(jq '[.items[] | select(.kind == "HorizontalPodAutoscaler")] | length' /tmp/scaling.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local vpa_count=$(jq '[.items[] | select(.kind == "VerticalPodAutoscaler")] | length' /tmp/scaling.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    local sa_count=$(jq '[.items[] | select(.kind == "ServiceAccount")] | length' /tmp/config.json 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo 0)
    
    echo "## 资源数量汇总" >> "$REPORT_FILE"
    echo "| 资源类型 | 数量 |" >> "$REPORT_FILE"
    echo "|----------|------|" >> "$REPORT_FILE"
    echo "| 工作负载 | $workload_count |" >> "$REPORT_FILE"
    echo "| Services | $svc_count |" >> "$REPORT_FILE"
    echo "| ConfigMaps | $cm_count |" >> "$REPORT_FILE"
    echo "| Secrets | $secret_count |" >> "$REPORT_FILE"
    echo "| ServiceAccounts | $sa_count |" >> "$REPORT_FILE"
    echo "| PVCs | $pvc_count |" >> "$REPORT_FILE"
    echo "| Ingresses | $ing_count |" >> "$REPORT_FILE"
    echo "| HPAs | $hpa_count |" >> "$REPORT_FILE"
    # Check VPA support and display accordingly
    if kubectl get vpa 2>/dev/null >/dev/null; then
        echo "| VPAs | $vpa_count |" >> "$REPORT_FILE"
    else
        print_warning "VPA不支持，已跳过"
        echo "| VPAs | 0 (不支持) |" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # Ensure all variables are valid numbers before calculation
    workload_count=${workload_count:-0}
    svc_count=${svc_count:-0}
    cm_count=${cm_count:-0}
    secret_count=${secret_count:-0}
    sa_count=${sa_count:-0}
    pvc_count=${pvc_count:-0}
    ing_count=${ing_count:-0}
    hpa_count=${hpa_count:-0}
    vpa_count=${vpa_count:-0}
    
    local total_resources=$((workload_count + svc_count + cm_count + secret_count + sa_count + pvc_count + ing_count + hpa_count + vpa_count))
    echo "**总资源数:** $total_resources" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Main execution
main() {
    print_info "Kubernetes命名空间统计分析器 (优化版)"
    print_info "=========================================="
    
    # Pre-flight checks
    check_dependencies
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "未连接到Kubernetes集群"
        exit 1
    fi
    
    check_namespace
    
    print_info "当前集群: $(kubectl config current-context)"
    print_info "分析命名空间: $NAMESPACE"
    
    # Execute analysis pipeline
    fetch_all_resources_optimized
    parse_resources
    analyze_workloads_comprehensive
    generate_resource_summary
    generate_statistics
    analyze_migration_requirements
    generate_migration_checklist
    
    print_success "统计分析完成!"
    print_info "报告已保存到: $REPORT_FILE"
    
    # Cleanup
    rm -f /tmp/all_resources.json /tmp/workloads.json /tmp/services.json /tmp/config.json 
    rm -f /tmp/storage.json /tmp/networking.json /tmp/scaling.json /tmp/migration.json
    rm -f /tmp/workload_analysis.json /tmp/image_stats.txt
}

# Execute main function
main "$@"