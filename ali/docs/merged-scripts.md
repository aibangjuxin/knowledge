# Shell Scripts Collection

Generated on: 2025-09-25 18:12:16
Directory: /Users/lex/git/knowledge/ali

## `k8s-resources.sh`

```bash
#!/bin/bash
# Kubernetes Resources Script - Get CPU and Memory limits/requests for Deployments
# Usage: ./k8s-resources.sh -n <namespace>

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""

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

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to show usage
usage() {
    echo "Usage: $0 -n <namespace>"
    echo "  -n: Kubernetes namespace (required)"
    echo "  -h: Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -n production"
    exit 1
}

# Parse command line arguments
while getopts "n:h" opt; do
    case $opt in
        n)
            NAMESPACE="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Check if namespace is provided
if [ -z "$NAMESPACE" ]; then
    print_error "Namespace is required!"
    usage
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

print_info "Analyzing Kubernetes resources in namespace: $NAMESPACE"
echo "=================================================================="

# Function to convert resource values to standard units
convert_cpu() {
    local cpu="$1"
    if [ -z "$cpu" ] || [ "$cpu" = "null" ]; then
        echo ""
        return
    fi
    
    # Handle millicores (m suffix)
    if [[ "$cpu" == *m ]]; then
        echo "${cpu}"
    # Handle cores (no suffix or with 'cpu' suffix)
    elif [[ "$cpu" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        # Convert to millicores for consistency
        local cores=$(echo "$cpu" | bc -l 2>/dev/null || echo "$cpu")
        local millicores=$(echo "$cores * 1000" | bc -l 2>/dev/null || echo "${cpu}000m")
        echo "${millicores%.*}m"
    else
        echo "$cpu"
    fi
}

convert_memory() {
    local memory="$1"
    if [ -z "$memory" ] || [ "$memory" = "null" ]; then
        echo ""
        return
    fi
    
    # Return as-is since memory units are already clear (Ki, Mi, Gi, etc.)
    echo "$memory"
}

# Function to get deployment resources
get_deployment_resources() {
    print_info "Fetching deployment resources..."
    
    # Get deployments data
    local deployments_json
    if ! deployments_json=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null); then
        print_error "Failed to get deployments from namespace $NAMESPACE"
        return 1
    fi

    local deployment_count=$(echo "$deployments_json" | jq '.items | length' 2>/dev/null || echo "0")
    if [ "$deployment_count" -eq 0 ]; then
        print_warning "No deployments found in namespace $NAMESPACE"
        return 0
    fi

    print_info "Found $deployment_count deployments"
    echo

    # Print table header
    printf "%-25s %-15s %-12s %-12s %-12s %-12s\n" \
        "DEPLOYMENT" "CONTAINER" "CPU_REQUEST" "CPU_LIMIT" "MEM_REQUEST" "MEM_LIMIT"
    printf "%-25s %-15s %-12s %-12s %-12s %-12s\n" \
        "-------------------------" "---------------" "------------" "------------" "------------" "------------"

    # Process each deployment
    echo "$deployments_json" | jq -r '
    .items[] as $deployment |
    $deployment.metadata.name as $deployment_name |
    $deployment.spec.template.spec.containers[]? as $container |
    $container.name as $container_name |
    
    ($container.resources.requests.cpu // "") as $cpu_request |
    ($container.resources.limits.cpu // "") as $cpu_limit |
    ($container.resources.requests.memory // "") as $mem_request |
    ($container.resources.limits.memory // "") as $mem_limit |
    
    "\($deployment_name)|\($container_name)|\($cpu_request)|\($cpu_limit)|\($mem_request)|\($mem_limit)"
    ' | while IFS='|' read -r deployment container cpu_req cpu_lim mem_req mem_lim; do
        
        # Convert CPU values
        cpu_req_converted=$(convert_cpu "$cpu_req")
        cpu_lim_converted=$(convert_cpu "$cpu_lim")
        
        # Convert Memory values
        mem_req_converted=$(convert_memory "$mem_req")
        mem_lim_converted=$(convert_memory "$mem_lim")
        
        # Use placeholders for empty values
        cpu_req_display="${cpu_req_converted:-"-"}"
        cpu_lim_display="${cpu_lim_converted:-"-"}"
        mem_req_display="${mem_req_converted:-"-"}"
        mem_lim_display="${mem_lim_converted:-"-"}"
        
        printf "%-25s %-15s %-12s %-12s %-12s %-12s\n" \
            "$deployment" "$container" "$cpu_req_display" "$cpu_lim_display" "$mem_req_display" "$mem_lim_display"
    done

    echo
}

# Function to show resource summary
show_resource_summary() {
    print_info "Resource Summary:"
    
    local deployments_json
    if ! deployments_json=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Could not get deployment data for summary"
        return
    fi

    # Count containers with and without resource specifications
    local total_containers=0
    local containers_with_requests=0
    local containers_with_limits=0
    local containers_with_cpu_requests=0
    local containers_with_cpu_limits=0
    local containers_with_mem_requests=0
    local containers_with_mem_limits=0

    while IFS='|' read -r deployment container cpu_req cpu_lim mem_req mem_lim; do
        if [ -n "$container" ]; then
            ((total_containers++))
            
            if [ -n "$cpu_req" ] || [ -n "$mem_req" ]; then
                ((containers_with_requests++))
            fi
            
            if [ -n "$cpu_lim" ] || [ -n "$mem_lim" ]; then
                ((containers_with_limits++))
            fi
            
            [ -n "$cpu_req" ] && ((containers_with_cpu_requests++))
            [ -n "$cpu_lim" ] && ((containers_with_cpu_limits++))
            [ -n "$mem_req" ] && ((containers_with_mem_requests++))
            [ -n "$mem_lim" ] && ((containers_with_mem_limits++))
        fi
    done < <(echo "$deployments_json" | jq -r '
    .items[] as $deployment |
    $deployment.metadata.name as $deployment_name |
    $deployment.spec.template.spec.containers[]? as $container |
    $container.name as $container_name |
    
    ($container.resources.requests.cpu // "") as $cpu_request |
    ($container.resources.limits.cpu // "") as $cpu_limit |
    ($container.resources.requests.memory // "") as $mem_request |
    ($container.resources.limits.memory // "") as $mem_limit |
    
    "\($deployment_name)|\($container_name)|\($cpu_request)|\($cpu_limit)|\($mem_request)|\($mem_limit)"
    ')

    echo "  Total containers: $total_containers"
    echo "  Containers with resource requests: $containers_with_requests"
    echo "  Containers with resource limits: $containers_with_limits"
    echo "  Containers with CPU requests: $containers_with_cpu_requests"
    echo "  Containers with CPU limits: $containers_with_cpu_limits"
    echo "  Containers with Memory requests: $containers_with_mem_requests"
    echo "  Containers with Memory limits: $containers_with_mem_limits"
    
    if [ $total_containers -gt 0 ]; then
        local req_percentage=$((containers_with_requests * 100 / total_containers))
        local lim_percentage=$((containers_with_limits * 100 / total_containers))
        echo "  Resource requests coverage: ${req_percentage}%"
        echo "  Resource limits coverage: ${lim_percentage}%"
    fi
    
    echo
}

# Function to show containers without resource specifications
show_missing_resources() {
    print_info "Containers without resource specifications:"
    
    local deployments_json
    if ! deployments_json=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null); then
        return
    fi

    local found_missing=false
    
    echo "$deployments_json" | jq -r '
    .items[] as $deployment |
    $deployment.metadata.name as $deployment_name |
    $deployment.spec.template.spec.containers[]? as $container |
    $container.name as $container_name |
    
    ($container.resources.requests.cpu // "") as $cpu_request |
    ($container.resources.limits.cpu // "") as $cpu_limit |
    ($container.resources.requests.memory // "") as $mem_request |
    ($container.resources.limits.memory // "") as $mem_limit |
    
    if ($cpu_request == "" and $cpu_limit == "" and $mem_request == "" and $mem_limit == "") then
        "⚠️  \($deployment_name)/\($container_name) - No resource specifications"
    elif ($cpu_request == "" and $mem_request == "") then
        "⚠️  \($deployment_name)/\($container_name) - Missing resource requests"
    elif ($cpu_limit == "" and $mem_limit == "") then
        "⚠️  \($deployment_name)/\($container_name) - Missing resource limits"
    else
        empty
    end
    ' | while read -r line; do
        if [ -n "$line" ]; then
            echo "  $line"
            found_missing=true
        fi
    done

    if [ "$found_missing" != "true" ]; then
        print_success "All containers have resource specifications!"
    fi
    
    echo
}

# Main function
main() {
    # Get and display deployment resources
    get_deployment_resources
    
    # Show summary
    show_resource_summary
    
    # Show missing resources
    show_missing_resources
    
    print_success "Resource analysis completed for namespace: $NAMESPACE"
}

# Run main function
main
```

## `namespace-status.sh`

```bash
#!/bin/bash

# Kubernetes Namespace Status Check Script
# Usage: ./namespace-status.sh -n <namespace-name>
# 检查指定namespace中Ingress、Deployment和Pod的对应关系和状态

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的状态信息
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 显示使用说明
show_usage() {
    echo "Usage: $0 -n <namespace-name>"
    echo "  -n: Kubernetes namespace name"
    echo ""
    echo "Example:"
    echo "  $0 -n default"
    echo "  $0 -n my-app-namespace"
    exit 1
}

# 检查kubectl是否可用
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_status $RED "Error: kubectl command not found. Please install kubectl first."
        exit 1
    fi
}

# 检查namespace是否存在
check_namespace() {
    local namespace=$1
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        print_status $RED "Error: Namespace '$namespace' not found."
        exit 1
    fi
}

# 获取Ingress信息
get_ingress_info() {
    local namespace=$1
    kubectl get ingress -n "$namespace" -o custom-columns="NAME:.metadata.name,HOSTS:.spec.rules[*].host" --no-headers 2>/dev/null
}

# 获取Deployment信息
get_deployment_info() {
    local namespace=$1
    kubectl get deployment -n "$namespace" -o custom-columns="NAME:.metadata.name,READY:.status.readyReplicas,REPLICAS:.status.replicas,AVAILABLE:.status.availableReplicas" --no-headers 2>/dev/null
}

# 获取Pod信息
get_pod_info() {
    local namespace=$1
    local deployment_name=$2
    kubectl get pods -n "$namespace" -l app="$deployment_name" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready" --no-headers 2>/dev/null
}

# 获取Pod信息（通过deployment selector）
get_pods_by_deployment() {
    local namespace=$1
    local deployment_name=$2
    
    # 获取deployment的selector
    local selector=$(kubectl get deployment "$deployment_name" -n "$namespace" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
    
    if [ -n "$selector" ]; then
        # 解析selector并构建label selector字符串
        local label_selector=$(echo "$selector" | sed 's/[{}"]//g' | sed 's/:/=/g' | sed 's/,/,/g')
        kubectl get pods -n "$namespace" -l "$label_selector" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount" --no-headers 2>/dev/null
    else
        # fallback: 尝试使用app label
        kubectl get pods -n "$namespace" -l app="$deployment_name" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount" --no-headers 2>/dev/null
    fi
}

# 分析Pod状态
analyze_pod_status() {
    local pod_line=$1
    local pod_name=$(echo "$pod_line" | awk '{print $1}')
    local pod_status=$(echo "$pod_line" | awk '{print $2}')
    local pod_ready=$(echo "$pod_line" | awk '{print $3}')
    local pod_restarts=$(echo "$pod_line" | awk '{print $4}')
    
    # 判断Pod是否健康
    if [[ "$pod_status" == "Running" && "$pod_ready" == "true" ]]; then
        echo "✓ $pod_name (Running, Ready, Restarts: ${pod_restarts:-0})"
        return 0  # 健康
    else
        echo "✗ $pod_name ($pod_status, Ready: $pod_ready, Restarts: ${pod_restarts:-0})"
        return 1  # 不健康
    fi
}

# 主要处理函数
process_namespace_status() {
    local namespace=$1
    
    print_status $BLUE "=== Namespace: $namespace Status Report ==="
    echo
    
    # 获取Ingress信息
    print_status $YELLOW "📋 Getting Ingress resources..."
    local ingress_data=$(get_ingress_info "$namespace")
    
    if [ -z "$ingress_data" ]; then
        print_status $YELLOW "No Ingress resources found in namespace '$namespace'"
        echo
    fi
    
    # 获取Deployment信息
    print_status $YELLOW "📋 Getting Deployment resources..."
    local deployment_data=$(get_deployment_info "$namespace")
    
    if [ -z "$deployment_data" ]; then
        print_status $YELLOW "No Deployment resources found in namespace '$namespace'"
        echo
        return
    fi
    
    # 输出表头
    printf "%-30s %-40s %-15s %s\n" "NAME" "HOSTS" "DEPLOY_STATUS" "POD_STATUS"
    printf "%-30s %-40s %-15s %s\n" "----" "-----" "-------------" "----------"
    
    # 处理每个Ingress
    if [ -n "$ingress_data" ]; then
        while IFS= read -r ingress_line; do
            if [ -n "$ingress_line" ]; then
                local ingress_name=$(echo "$ingress_line" | awk '{print $1}')
                local ingress_hosts=$(echo "$ingress_line" | awk '{print $2}')
                
                # 查找对应的Deployment
                local matching_deployment=$(echo "$deployment_data" | grep "^$ingress_name ")
                
                if [ -n "$matching_deployment" ]; then
                    local deploy_ready=$(echo "$matching_deployment" | awk '{print $2}')
                    local deploy_replicas=$(echo "$matching_deployment" | awk '{print $3}')
                    local deploy_available=$(echo "$matching_deployment" | awk '{print $4}')
                    
                    # Deployment状态
                    local deploy_status
                    if [[ "$deploy_ready" == "$deploy_replicas" && "$deploy_available" == "$deploy_replicas" ]]; then
                        deploy_status="✓ ${deploy_ready}/${deploy_replicas}"
                    else
                        deploy_status="✗ ${deploy_ready:-0}/${deploy_replicas:-0}"
                    fi
                    
                    # 获取Pod信息
                    local pod_data=$(get_pods_by_deployment "$namespace" "$ingress_name")
                    
                    if [ -n "$pod_data" ]; then
                        local healthy_pods=0
                        local total_pods=0
                        local pod_status_summary=""
                        
                        while IFS= read -r pod_line; do
                            if [ -n "$pod_line" ]; then
                                total_pods=$((total_pods + 1))
                                if analyze_pod_status "$pod_line" >/dev/null; then
                                    healthy_pods=$((healthy_pods + 1))
                                fi
                            fi
                        done <<< "$pod_data"
                        
                        if [ $healthy_pods -eq $total_pods ]; then
                            pod_status_summary="✓ ${healthy_pods}/${total_pods} healthy"
                        else
                            pod_status_summary="✗ ${healthy_pods}/${total_pods} healthy"
                        fi
                    else
                        pod_status_summary="No pods found"
                    fi
                    
                    # 输出汇总行
                    printf "%-30s %-40s %-15s %s\n" "$ingress_name" "$ingress_hosts" "$deploy_status" "$pod_status_summary"
                    
                else
                    printf "%-30s %-40s %-15s %s\n" "$ingress_name" "$ingress_hosts" "No deployment" "N/A"
                fi
            fi
        done <<< "$ingress_data"
    fi
    
    # 处理没有对应Ingress的Deployment
    echo
    print_status $YELLOW "📋 Deployments without matching Ingress:"
    while IFS= read -r deploy_line; do
        if [ -n "$deploy_line" ]; then
            local deploy_name=$(echo "$deploy_line" | awk '{print $1}')
            
            # 检查是否有对应的Ingress
            local has_ingress=$(echo "$ingress_data" | grep "^$deploy_name ")
            
            if [ -z "$has_ingress" ]; then
                local deploy_ready=$(echo "$deploy_line" | awk '{print $2}')
                local deploy_replicas=$(echo "$deploy_line" | awk '{print $3}')
                local deploy_available=$(echo "$deploy_line" | awk '{print $4}')
                
                local deploy_status
                if [[ "$deploy_ready" == "$deploy_replicas" && "$deploy_available" == "$deploy_replicas" ]]; then
                    deploy_status="✓ ${deploy_ready}/${deploy_replicas}"
                else
                    deploy_status="✗ ${deploy_ready:-0}/${deploy_replicas:-0}"
                fi
                
                # 获取Pod信息
                local pod_data=$(get_pods_by_deployment "$namespace" "$deploy_name")
                local pod_status_summary="No pods found"
                
                if [ -n "$pod_data" ]; then
                    local healthy_pods=0
                    local total_pods=0
                    
                    while IFS= read -r pod_line; do
                        if [ -n "$pod_line" ]; then
                            total_pods=$((total_pods + 1))
                            if analyze_pod_status "$pod_line" >/dev/null; then
                                healthy_pods=$((healthy_pods + 1))
                            fi
                        fi
                    done <<< "$pod_data"
                    
                    if [ $healthy_pods -eq $total_pods ]; then
                        pod_status_summary="✓ ${healthy_pods}/${total_pods} healthy"
                    else
                        pod_status_summary="✗ ${healthy_pods}/${total_pods} healthy"
                    fi
                fi
                
                printf "%-30s %-40s %-15s %s\n" "$deploy_name" "No ingress" "$deploy_status" "$pod_status_summary"
            fi
        fi
    done <<< "$deployment_data"
    
    echo
    print_status $BLUE "=== Detailed Pod Status ==="
    
    # 详细的Pod状态信息
    while IFS= read -r deploy_line; do
        if [ -n "$deploy_line" ]; then
            local deploy_name=$(echo "$deploy_line" | awk '{print $1}')
            
            print_status $YELLOW "Deployment: $deploy_name"
            local pod_data=$(get_pods_by_deployment "$namespace" "$deploy_name")
            
            if [ -n "$pod_data" ]; then
                local healthy_pods=()
                local unhealthy_pods=()
                
                while IFS= read -r pod_line; do
                    if [ -n "$pod_line" ]; then
                        local pod_analysis=$(analyze_pod_status "$pod_line")
                        if analyze_pod_status "$pod_line" >/dev/null; then
                            healthy_pods+=("  $pod_analysis")
                        else
                            unhealthy_pods+=("  $pod_analysis")
                        fi
                    fi
                done <<< "$pod_data"
                
                if [ ${#healthy_pods[@]} -gt 0 ]; then
                    print_status $GREEN "  Healthy Pods:"
                    printf '%s\n' "${healthy_pods[@]}"
                fi
                
                if [ ${#unhealthy_pods[@]} -gt 0 ]; then
                    print_status $RED "  Unhealthy Pods:"
                    printf '%s\n' "${unhealthy_pods[@]}"
                fi
            else
                print_status $YELLOW "  No pods found"
            fi
            echo
        fi
    done <<< "$deployment_data"
}

# 主函数
main() {
    local namespace=""
    
    # 解析命令行参数
    while getopts "n:h" opt; do
        case $opt in
            n)
                namespace="$OPTARG"
                ;;
            h)
                show_usage
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                show_usage
                ;;
        esac
    done
    
    # 检查必需参数
    if [ -z "$namespace" ]; then
        print_status $RED "Error: Namespace is required"
        show_usage
    fi
    
    # 检查依赖
    check_kubectl
    check_namespace "$namespace"
    
    # 执行主要逻辑
    process_namespace_status "$namespace"
}

# 运行脚本
main "$@"
```

## `verify-e2e.sh`

```bash
#!/bin/bash
# E2E Verification Script for Kubernetes Resources
# Usage: ./verify-e2e.sh -n <namespace>

# set -e  # Commented out to prevent script from exiting on non-critical errors

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
TIMEOUT=10

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
    echo "Usage: $0 -n <namespace> [-t <timeout>]"
    echo "  -n: Kubernetes namespace (required)"
    echo "  -t: Timeout for curl requests in seconds (default: 10)"
    echo "  -h: Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:t:h" opt; do
    case $opt in
        n)
            NAMESPACE="$OPTARG"
            ;;
        t)
            TIMEOUT="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Check if namespace is provided
if [ -z "$NAMESPACE" ]; then
    print_error "Namespace is required!"
    usage
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

print_info "Starting E2E verification for namespace: $NAMESPACE"
echo "=================================================="

# Function to extract URLs from Ingress (silent version for collection)
get_ingress_urls() {
    local ingress_urls=()
    local ingresses
    
    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        return
    fi

    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        return
    fi

    # Extract hosts and paths from ingress with better error handling
    while IFS= read -r line; do
        if [ -n "$line" ] && [ "$line" != "null" ]; then
            ingress_urls+=("$line")
        fi
    done < <(echo "$ingresses" | jq -r '.items[] |
        .spec.rules[]? |
        select(.host != null) |
        "https://" + .host + (.http.paths[]?.path // "")' 2>/dev/null || true)

    # Only output URLs, no info messages
    printf '%s\n' "${ingress_urls[@]}"
}

# Function to build and display resource relationships (no URL testing)
show_resource_relationships_detailed() {
    print_info "Building detailed resource relationship map..."

    # Create temporary files for data processing
    local temp_dir="/tmp/verify-e2e-$$"
    mkdir -p "$temp_dir"
    local ingress_data="$temp_dir/ingress.json"
    local service_data="$temp_dir/services.json"
    local deployment_data="$temp_dir/deployments.json"
    local relationship_output="$temp_dir/relationships.txt"

    # Fetch all resources with error handling
    if ! kubectl get ingress -n "$NAMESPACE" -o json > "$ingress_data" 2>/dev/null; then
        print_warning "Failed to fetch ingress data"
        rm -rf "$temp_dir"
        return
    fi

    if ! kubectl get services -n "$NAMESPACE" -o json > "$service_data" 2>/dev/null; then
        print_warning "Failed to fetch service data"
        rm -rf "$temp_dir"
        return
    fi

    if ! kubectl get deployments -n "$NAMESPACE" -o json > "$deployment_data" 2>/dev/null; then
        print_warning "Failed to fetch deployment data"
        rm -rf "$temp_dir"
        return
    fi

    # Check if we have any ingresses
    local ingress_count=$(jq '.items | length' "$ingress_data" 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        rm -rf "$temp_dir"
        return
    fi

    print_info "Processing $ingress_count Ingress resources for relationship mapping..."

    # Build resource relationship map using jq (only for relationship display, no URL generation)
    jq -r --slurpfile services "$service_data" --slurpfile deployments "$deployment_data" '
    .items[] as $ingress |
    $ingress.metadata.name as $ingress_name |
    
    $ingress.spec.rules[]? as $rule |
    $rule.host as $host |
    
    if ($host and $host != null) then
        $rule.http.paths[]? as $path |
        
        ($path.path // "/") as $ingress_path |
        ($path.backend.service.name // $path.backend.serviceName // empty) as $service_name |
        ($path.backend.service.port.number // $path.backend.servicePort // empty) as $service_port |
        
        if ($service_name and $service_name != null) then
            # Find matching service
            $services[0].items[] | select(.metadata.name == $service_name) as $service |
            
            if ($service) then
                $service.spec.selector as $selector |
                
                if ($selector and ($selector | length > 0)) then
                    # Find matching deployments
                    $deployments[0].items[] as $deployment |
                    $deployment.metadata.name as $deployment_name |
                    $deployment.spec.template.metadata.labels as $deploy_labels |
                    
                    if ($deploy_labels) then
                        # Check if deployment labels match service selector
                        ([$selector | to_entries[] as $sel_entry | 
                         $deploy_labels[$sel_entry.key] == $sel_entry.value] | all) as $labels_match |
                        
                        if ($labels_match) then
                            # Show relationship mapping
                            "✓ \($ingress_name) (\($host)\($ingress_path)) -> \($service_name):\($service_port) -> \($deployment_name)"
                        else 
                            "⚠ \($ingress_name) (\($host)\($ingress_path)) -> \($service_name):\($service_port) -> [NO MATCHING DEPLOYMENT]"
                        end
                    else 
                        "⚠ \($ingress_name) (\($host)\($ingress_path)) -> \($service_name):\($service_port) -> [DEPLOYMENT HAS NO LABELS]"
                    end
                else 
                    "⚠ \($ingress_name) (\($host)\($ingress_path)) -> \($service_name):\($service_port) -> [SERVICE HAS NO SELECTOR]"
                end
            else 
                "✗ \($ingress_name) (\($host)\($ingress_path)) -> \($service_name) [SERVICE NOT FOUND]"
            end
        else 
            "✗ \($ingress_name) (\($host)\($ingress_path)) -> [NO SERVICE SPECIFIED]"
        end
    else 
        "✗ \($ingress_name) [NO HOST SPECIFIED]"
    end
    ' "$ingress_data" > "$relationship_output" 2>/dev/null

    # Display only successful relationships
    echo
    print_info "Resource Relationship Map (Successful Mappings Only):"
    echo "=================================================="
    local success_count=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if [[ "$line" == ✓* ]]; then
                print_success "$line"
                ((success_count++))
            fi
        fi
    done < "$relationship_output"
    
    if [ $success_count -eq 0 ]; then
        print_warning "No successful resource relationships found"
    else
        print_info "Found $success_count successful resource relationships"
    fi
    echo "=================================================="

    # Clean up temporary files
    rm -rf "$temp_dir"
}

# Function to get readiness probe URLs (silent version for collection)
get_readiness_probe_urls() {
    # Create temporary files for data processing
    local temp_dir="/tmp/verify-e2e-$$"
    mkdir -p "$temp_dir"
    local ingress_data="$temp_dir/ingress.json"
    local service_data="$temp_dir/services.json"
    local deployment_data="$temp_dir/deployments.json"
    local url_output="$temp_dir/readiness_urls.txt"

    # Fetch all resources with error handling
    if ! kubectl get ingress -n "$NAMESPACE" -o json > "$ingress_data" 2>/dev/null; then
        rm -rf "$temp_dir"
        return
    fi

    if ! kubectl get services -n "$NAMESPACE" -o json > "$service_data" 2>/dev/null; then
        rm -rf "$temp_dir"
        return
    fi

    if ! kubectl get deployments -n "$NAMESPACE" -o json > "$deployment_data" 2>/dev/null; then
        rm -rf "$temp_dir"
        return
    fi

    # Check if we have any ingresses
    local ingress_count=$(jq '.items | length' "$ingress_data" 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        rm -rf "$temp_dir"
        return
    fi

    # Build readiness probe URLs using jq
    jq -r --slurpfile services "$service_data" --slurpfile deployments "$deployment_data" '
    .items[] as $ingress |
    $ingress.metadata.name as $ingress_name |
    
    $ingress.spec.rules[]? as $rule |
    $rule.host as $host |
    
    if ($host and $host != null) then
        $rule.http.paths[]? as $path |
        
        ($path.path // "/") as $ingress_path |
        ($path.backend.service.name // $path.backend.serviceName // empty) as $service_name |
        ($path.backend.service.port.number // $path.backend.servicePort // empty) as $service_port |
        
        if ($service_name and $service_name != null) then
            # Find matching service
            $services[0].items[] | select(.metadata.name == $service_name) as $service |
            
            if ($service) then
                $service.spec.selector as $selector |
                
                if ($selector and ($selector | length > 0)) then
                    # Find matching deployments
                    $deployments[0].items[] as $deployment |
                    $deployment.metadata.name as $deployment_name |
                    $deployment.spec.template.metadata.labels as $deploy_labels |
                    
                    if ($deploy_labels) then
                        # Check if deployment labels match service selector
                        ([$selector | to_entries[] as $sel_entry | 
                         $deploy_labels[$sel_entry.key] == $sel_entry.value] | all) as $labels_match |
                        
                        if ($labels_match) then
                            # Extract readiness probe paths from deployment
                            $deployment.spec.template.spec.containers[]? as $container |
                            
                            if ($container.readinessProbe and $container.readinessProbe.httpGet) then
                                $container.readinessProbe.httpGet.path as $probe_path |
                                ($container.readinessProbe.httpGet.port // 80) as $probe_port |
                                
                                if ($probe_path and $probe_path != "/" and $probe_path != null) then
                                    "https://\($host)\($probe_path)"
                                else empty end
                            else empty end
                        else empty end
                    else empty end
                else empty end
            else empty end
        else empty end
    else empty end
    ' "$ingress_data" > "$url_output" 2>/dev/null

    # Output unique URLs only
    sort -u "$url_output" 2>/dev/null

    # Clean up temporary files
    rm -rf "$temp_dir"
}

# Function to test a single URL
test_url() {
    local url="$1"
    printf "Testing %-60s ... " "$url"
    
    # Get HTTP status code
    local status_code
    if status_code=$(curl --silent --head --insecure --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" --write-out "%{http_code}" --output /dev/null "$url" 2>/dev/null); then
        # Consider 5xx as failure, everything else as success
        if [[ "$status_code" =~ ^5[0-9][0-9]$ ]]; then
            print_error "✗ $status_code"
            return 1
        elif [[ "$status_code" =~ ^[23][0-9][0-9]$ ]]; then
            print_success "✓ $status_code"
            return 0
        elif [[ "$status_code" =~ ^4[0-9][0-9]$ ]]; then
            print_warning "! $status_code (Client Error)"
            return 0  # Consider 4xx as success for readiness probes (might be auth-protected)
        else
            print_warning "? $status_code (Unknown)"
            return 0
        fi
    else
        print_error "✗ TIMEOUT/ERROR"
        return 1
    fi
}

# Function to show resource summary
show_resource_summary() {
    print_info "Resource summary for namespace $NAMESPACE:"
    
    local ingress_count=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local service_count=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local deployment_count=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local pod_count=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local rs_count=$(kubectl get replicasets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    echo "  Ingresses: $ingress_count"
    echo "  Services: $service_count"
    echo "  Deployments: $deployment_count"
    echo "  Pods: $pod_count"
    echo "  ReplicaSets: $rs_count"
    echo
}

# Function to show pod status
show_pod_status() {
    print_info "Pod status in namespace $NAMESPACE:"
    if ! kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null; then
        print_warning "Could not get pod status"
    fi
    echo
}

# Function to show basic resource relationships (simple version)
show_resource_relationships() {
    print_info "Basic resource relationships in namespace $NAMESPACE:"
    
    # Get ingress to service mappings
    kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
    .items[] as $ingress |
    $ingress.metadata.name as $ingress_name |
    $ingress.spec.rules[]? as $rule |
    $rule.host as $host |
    $rule.http.paths[]? as $path |
    ($path.backend.service.name // $path.backend.serviceName) as $service_name |
    ($path.path // "/") as $path_value |
    "  \($ingress_name) (\($host)\($path_value)) -> \($service_name)"
    ' 2>/dev/null || print_warning "Could not analyze ingress relationships"
    
    echo
}

# Main logic
main() {
    # Show resource summary
    show_resource_summary

    # Show basic resource relationships
    show_resource_relationships

    # Show detailed resource relationships (no testing, just mapping)
    show_resource_relationships_detailed

    # Show pod status
    show_pod_status

    # Collect URLs for testing
    print_info "Collecting URLs for testing..."
    echo "=================================================="
    
    # Collect ingress URLs silently
    local ingress_urls_output=$(get_ingress_urls)
    
    # Collect readiness probe URLs silently
    local readiness_urls_output=$(get_readiness_probe_urls)
    
    # Prepare Ingress URLs for testing
    local ingress_test_urls=()
    while IFS= read -r url; do 
        [ -n "$url" ] && ingress_test_urls+=("$url")
    done <<< "$ingress_urls_output"
    
    # Remove duplicates from ingress URLs
    if [ ${#ingress_test_urls[@]} -gt 0 ]; then
        local unique_ingress_urls=()
        while IFS= read -r url; do
            unique_ingress_urls+=("$url")
        done < <(printf '%s\n' "${ingress_test_urls[@]}" | sort -u)
        ingress_test_urls=("${unique_ingress_urls[@]}")
    fi

    # Prepare Readiness Probe URLs for testing
    local readiness_test_urls=()
    while IFS= read -r url; do 
        [ -n "$url" ] && readiness_test_urls+=("$url")
    done <<< "$readiness_urls_output"
    
    # Remove duplicates from readiness URLs
    if [ ${#readiness_test_urls[@]} -gt 0 ]; then
        local unique_readiness_urls=()
        while IFS= read -r url; do
            unique_readiness_urls+=("$url")
        done < <(printf '%s\n' "${readiness_test_urls[@]}" | sort -u)
        readiness_test_urls=("${unique_readiness_urls[@]}")
    fi

    # Display collected URLs
    print_info "Found ${#ingress_test_urls[@]} Ingress URLs to be tested:"
    if [ ${#ingress_test_urls[@]} -gt 0 ]; then
        printf -- "  🌐 %s\n" "${ingress_test_urls[@]}"
    fi
    echo

    print_info "Found ${#readiness_test_urls[@]} Readiness Probe URLs to be tested:"
    if [ ${#readiness_test_urls[@]} -gt 0 ]; then
        printf -- "  📋 %s\n" "${readiness_test_urls[@]}"
    fi
    echo

    # Check if we have any URLs to test
    if [ ${#ingress_test_urls[@]} -eq 0 ] && [ ${#readiness_test_urls[@]} -eq 0 ]; then
        print_warning "No URLs found to test."
        print_info "This might indicate:"
        print_info "  1. No Ingress resources with valid hosts"
        print_info "  2. No Deployments with readiness probes"
        print_info "  3. Resources are not properly configured"
        exit 0
    fi

    # Test Ingress URLs
    local ingress_success=0
    local ingress_failed=0
    if [ ${#ingress_test_urls[@]} -gt 0 ]; then
        echo "=================================================="
        print_info "Starting Ingress URL tests..."
        echo "=================================================="

        for url in "${ingress_test_urls[@]}"; do
            if test_url "$url"; then
                ((ingress_success++))
            else
                ((ingress_failed++))
            fi
        done

        echo "=================================================="
        print_info "Ingress URL Test Results:"
        print_success "Successful: $ingress_success/${#ingress_test_urls[@]}"
        if [ $ingress_failed -gt 0 ]; then
            print_error "Failed: $ingress_failed/${#ingress_test_urls[@]}"
        fi
        echo "=================================================="
    fi

    # Test Readiness Probe URLs
    local readiness_success=0
    local readiness_failed=0
    if [ ${#readiness_test_urls[@]} -gt 0 ]; then
        echo "=================================================="
        print_info "Starting Readiness Probe URL tests..."
        echo "=================================================="

        for url in "${readiness_test_urls[@]}"; do
            if test_url "$url"; then
                ((readiness_success++))
            else
                ((readiness_failed++))
            fi
        done

        echo "=================================================="
        print_info "Readiness Probe URL Test Results:"
        print_success "Successful: $readiness_success/${#readiness_test_urls[@]}"
        if [ $readiness_failed -gt 0 ]; then
            print_error "Failed: $readiness_failed/${#readiness_test_urls[@]}"
        fi
        echo "=================================================="
    fi

    # Overall Summary
    local total_success=$((ingress_success + readiness_success))
    local total_failed=$((ingress_failed + readiness_failed))
    local total_tests=$((${#ingress_test_urls[@]} + ${#readiness_test_urls[@]}))

    echo "=================================================="
    print_info "Overall Test Summary:"
    print_success "Total Successful: $total_success/$total_tests"
    if [ $total_failed -gt 0 ]; then
        print_error "Total Failed: $total_failed/$total_tests"
    fi
    
    if [ ${#ingress_test_urls[@]} -gt 0 ]; then
        print_info "Ingress URLs: $ingress_success/${#ingress_test_urls[@]} passed"
    fi
    if [ ${#readiness_test_urls[@]} -gt 0 ]; then
        print_info "Readiness Probe URLs: $readiness_success/${#readiness_test_urls[@]} passed"
    fi
    echo "=================================================="

    # Exit with appropriate code
    if [ $total_success -eq $total_tests ]; then
        print_success "All E2E tests passed! 🎉"
        exit 0
    elif [ $total_success -gt 0 ]; then
        print_warning "Partial success: $total_success out of $total_tests tests passed."
        exit 1
    else
        print_error "All tests failed! Please check your configuration."
        exit 1
    fi
}

# Cleanup function
cleanup() {
    # Clean up any temporary files if needed
    rm -rf /tmp/verify-e2e-* 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main
```

