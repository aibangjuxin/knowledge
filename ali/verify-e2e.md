
API flow
Ingress → Service → Pod → ReplicaSet → Deployment → readinessProbe）

我现在想写这样一个脚本 传参就是Namespace的名字比如
verify-e2e.sh -n mynamespace

然后呢,获取到里面所有对应的资源 然后就包括我的这个follow的流程 然后我想拿到我所有的 e2e 的测试的URL 
然后进行一个简单的curl请求

因为我们知道Ingress里面比如说有host,然后deploy最终的readiness里面有具体的url,所以说我能拿到一些对应的信息。

```bash
#!/bin/bash

# E2E Verification Script for Kubernetes Resources
# Usage: ./verify-e2e.sh -n <namespace>

set -e

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

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

print_info "Starting E2E verification for namespace: $NAMESPACE"
echo "=================================================="

# Function to extract URLs from Ingress
get_ingress_urls() {
    print_info "Extracting URLs from Ingress resources..."
    
    local ingress_urls=()
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json)
    
    if [ "$(echo "$ingresses" | jq '.items | length')" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi
    
    # Extract hosts and paths from ingress
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            ingress_urls+=("$line")
        fi
    done < <(echo "$ingresses" | jq -r '.items[] | 
        .spec.rules[]? | 
        "https://" + .host + (.http.paths[]?.path // "")')
    
    printf '%s\n' "${ingress_urls[@]}"
}

# Function to extract readiness probe URLs from Deployments
get_readiness_urls() {
    print_info "Extracting readiness probe URLs from Deployments..."
    
    local readiness_urls=()
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o json)
    
    if [ "$(echo "$deployments" | jq '.items | length')" -eq 0 ]; then
        print_warning RLs

    local success_count=0
    local total_count=${#all_urls[@]}
    
    for url in "${all_urls[@]}"; do
        if test_url "$url"; then
            ((success_count++))
        fi
        echo
    done
    
    echo "=================================================="
    print_info "Test Results Summary:"
    print_success "Successful: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        print_success "All E2E tests passed! 🎉"
        exit 0
    else
        print_warning "Some tests failed. Check the logs above for details."
        exit 1
    fi
}

# Function to port-forward for readiness probe testing
setup_port_forward() {
    local deployment="$1"
    local port="$2"
    local local_port="$3"
    
    print_info "Setting up port-forward for $deployment:$port -> localhost:$local_port"
    kubectl port-forward -n "$NAMESPACE" "deployment/$deployment" "$local_port:$port" &
    local pf_pid=$!
    sleep 2
    echo $pf_pid
}

# Enhanced function to get readiness URLs with port-forwarding
get_readiness_urls_with_portforward() {
    print_info "Extracting readiness probe URLs from Deployments with port-forwarding..."
    
    local readiness_urls=()
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o json)
    
    if [ "$(echo "$deployments" | jq '.items | length')" -eq 0 ]; then
        print_warning "No Deployment resources found in namespace $NAMESPACE"
        return
    fi
    
    local port_counter=8080
    
    # Extract deployment info and setup port-forwarding
    while IFS='|' read -r dep_name container_port readiness_path; do
        if [ -n "$dep_name" ] && [ -n "$container_port" ] && [ -n "$readiness_path" ]; then
            local local_port=$((port_counter++))
            print_info "Found readiness probe: $dep_name -> $container_port$readiness_path"
            
            # Setup port-forward in background
            kubectl port-forward -n "$NAMESPACE" "deployment/$dep_name" "$local_port:$container_port" >/dev/null 2>&1 &
            local pf_pid=$!
            sleep 1
            
            # Add URL to test list
            readiness_urls+=("http://localhost:$local_port$readiness_path")
            
            # Store PID for cleanup
            echo "$pf_pid" >> /tmp/verify-e2e-pids.tmp
        fi
    done < <(echo "$deployments" | jq -r '
        .items[] | 
        .metadata.name as $dep_name |
        .spec.template.spec.containers[]? | 
        select(.readinessProbe.httpGet) | 
        $dep_name + "|" + (.readinessProbe.httpGet.port | tostring) + "|" + (.readinessProbe.httpGet.path // "/")')
    
    printf '%s\n' "${readiness_urls[@]}"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up port-forwards..."
    if [ -f /tmp/verify-e2e-pids.tmp ]; then
        while read -r pid; do
            if [ -n "$pid" ]; then
                kill "$pid" 2>/dev/null || true
            fi
        done < /tmp/verify-e2e-pids.tmp
        rm -f /tmp/verify-e2e-pids.tmp
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main
```