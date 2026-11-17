API flow
Ingress → Service → Pod → ReplicaSet → Deployment → readinessProbe）

我现在想写这样一个脚本 传参就是 Namespace 的名字比如
verify-e2e.sh -n mynamespace

然后呢,获取到里面所有对应的资源 然后就包括我的这个 follow 的流程 然后我想拿到我所有的 e2e 的测试的 URL
然后进行一个简单的 curl 请求

因为我们知道 Ingress 里面比如说有 host,然后 deploy 最终的 readiness 里面有具体的 url,所以说我能拿到一些对应的信息。

- enhance
- 主要改进点

更好的代码结构 - 使用了函数引用传递，避免了子 shell 问题
优化的 API 调用 - 一次性获取所有资源，减少 kubectl 调用
改进的 URL 拼接逻辑 - 正确处理了 Ingress 路径和探针路径的组合
更清晰的错误处理 - 使用 set -o pipefail 和更好的错误检查

潜在问题
在 get_readiness_urls() 函数中，URL 拼接逻辑还可以进一步优化，特别是路径组合的边界情况处理。
- v3.sh
- 脚本执行是可以的
我现在需要优化几个地方 1 Process ingress resoucres URL 这个没有问题保留
ingress对应的Service然后对应的Deployment这个关系 是不需要进行Testing测试的.仅仅是获取关系而已.
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

# Function to extract URLs from Ingress
get_ingress_urls() {
    print_info "Extracting URLs from Ingress resources..."

    local ingress_urls=()
    local ingresses
    
    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    print_info "Found $ingress_count Ingress resources"

    # Extract hosts and paths from ingress with better error handling
    while IFS= read -r line; do
        if [ -n "$line" ] && [ "$line" != "null" ]; then
            ingress_urls+=("$line")
        fi
    done < <(echo "$ingresses" | jq -r '.items[] |
        .spec.rules[]? |
        select(.host != null) |
        "https://" + .host + (.http.paths[]?.path // "")' 2>/dev/null || true)

    print_info "Extracted ${#ingress_urls[@]} URLs from Ingress resources"
    printf '%s\n' "${ingress_urls[@]}"
}

# Enhanced function to get readiness probe URLs based on actual resource relationships
get_readiness_urls() {
    print_info "Building resource relationship map and extracting readiness URLs..."

    local readiness_urls=()
    
    # Create temporary files for data processing
    local temp_dir="/tmp/verify-e2e-$$"
    mkdir -p "$temp_dir"
    local ingress_data="$temp_dir/ingress.json"
    local service_data="$temp_dir/services.json"
    local deployment_data="$temp_dir/deployments.json"
    local url_output="$temp_dir/urls.txt"

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

    print_info "Processing $ingress_count Ingress resources for readiness probe URLs..."

    # Build resource relationship map using jq
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
                                    "# Ingress: \($ingress_name) -> Service: \($service_name) -> Deployment: \($deployment_name)",
                                    "https://\($host)\($probe_path)"
                                else empty end
                            else empty end
                        else empty end
                    else empty end
                else 
                    "# Warning: Service \($service_name) has no selector"
                end
            else 
                "# Warning: Service \($service_name) not found"
            end
        else empty end
    else empty end
    ' "$ingress_data" > "$url_output" 2>/dev/null

    # Process the output
    local current_mapping=""
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if [[ "$line" == \#* ]]; then
                # This is a comment/mapping info
                current_mapping="$line"
                if [[ "$line" == *"Warning:"* ]]; then
                    print_warning "${line#\# }"
                else
                    print_info "${line#\# }"
                fi
            else
                # This is a URL
                readiness_urls+=("$line")
                print_success "Generated readiness URL: $line"
            fi
        fi
    done < "$url_output"

    # Clean up temporary files
    rm -rf "$temp_dir"

    # Remove duplicates
    if [ ${#readiness_urls[@]} -gt 0 ]; then
        local unique_readiness_urls=()
        while IFS= read -r url; do
            if [ -n "$url" ]; then
                unique_readiness_urls+=("$url")
            fi
        done < <(printf '%s\n' "${readiness_urls[@]}" | sort -u)
        readiness_urls=("${unique_readiness_urls[@]}")
    fi

    print_info "Generated ${#readiness_urls[@]} unique readiness probe URLs based on resource relationships"
    printf '%s\n' "${readiness_urls[@]}"
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

# Function to show detailed resource relationships
show_resource_relationships() {
    print_info "Analyzing resource relationships in namespace $NAMESPACE:"
    
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

    # Show resource relationships
    show_resource_relationships

    # Show pod status
    show_pod_status

    # Get URLs from both sources
    print_info "Collecting URLs for testing..."
    echo "=================================================="
    
    local ingress_urls=$(get_ingress_urls)
    echo
    local readiness_urls=$(get_readiness_urls)
    echo

    # Combine and deduplicate URLs
    local all_urls=()
    
    # Add ingress URLs
    while IFS= read -r url; do 
        [ -n "$url" ] && all_urls+=("$url")
    done <<< "$ingress_urls"
    
    # Add readiness URLs
    while IFS= read -r url; do 
        [ -n "$url" ] && all_urls+=("$url")
    done <<< "$readiness_urls"
    
    # Remove duplicates by sorting and using uniq
    if [ ${#all_urls[@]} -gt 0 ]; then
        local unique_urls=()
        while IFS= read -r url; do
            unique_urls+=("$url")
        done < <(printf '%s\n' "${all_urls[@]}" | sort -u)
        all_urls=("${unique_urls[@]}")
    fi

    if [ ${#all_urls[@]} -eq 0 ]; then
        print_warning "No URLs found to test."
        print_info "This might indicate:"
        print_info "  1. No Ingress resources with valid hosts"
        print_info "  2. No Deployments with readiness probes"
        print_info "  3. No proper Service -> Deployment mappings"
        exit 0
    fi

    print_info "Final URL collection for testing:"
    printf -- "  - %s\n" "${all_urls[@]}"
    echo

    # Run tests
    echo "=================================================="
    print_info "Starting URL tests..."
    echo "=================================================="

    local success_count=0
    local failed_count=0
    local total_count=${#all_urls[@]}

    for url in "${all_urls[@]}"; do
        if test_url "$url"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done

    echo "=================================================="
    print_info "Test Results Summary:"
    print_success "Successful: $success_count/$total_count"
    if [ $failed_count -gt 0 ]; then
        print_error "Failed: $failed_count/$total_count"
    fi

    echo "=================================================="

    if [ $success_count -eq $total_count ]; then
        print_success "All E2E tests passed! 🎉"
        exit 0
    elif [ $success_count -gt 0 ]; then
        print_warning "Partial success: $success_count out of $total_count tests passed."
        exit 1
    else
        print_error "All tests failed! Please check your deployments and ingress configuration."
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


```bash
#!/bin/bash

# E2E Verification Script for Kubernetes Resources
# Usage: ./verify-e2e.sh -n <namespace>

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
    
    local ingresses
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    print_info "Found $ingress_count Ingress resources"

    # Extract hosts and paths from ingress with better error handling
    echo "$ingresses" | jq -r '.items[] |
        .spec.rules[]? |
        select(.host != null) |
        .http.paths[]? |
        "https://" + .host + (.path // "")' 2>/dev/null | grep -v "null" || true
}

# Function to get readiness probe URLs (simplified approach)
get_readiness_urls() {
    print_info "Extracting readiness probe URLs from Deployments..."

    local deployments
    local ingresses
    
    # Get deployments with error handling
    if ! deployments=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Deployment resources from namespace $NAMESPACE"
        return
    fi

    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local deployment_count=$(echo "$deployments" | jq '.items | length' 2>/dev/null || echo "0")
    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")

    if [ "$deployment_count" -eq 0 ]; then
        print_warning "No Deployment resources found in namespace $NAMESPACE"
        return
    fi

    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    # Get the first ingress host as primary host
    local primary_host
    primary_host=$(echo "$ingresses" | jq -r '.items[0].spec.rules[0]?.host' 2>/dev/null || echo "")
    
    if [ -z "$primary_host" ] || [ "$primary_host" = "null" ]; then
        print_warning "No valid host found in Ingress resources"
        return
    fi

    print_info "Using primary host: $primary_host"

    # Extract unique readiness probe paths from deployments
    echo "$deployments" | jq -r '
        .items[] |
        .spec.template.spec.containers[]? |
        select(.readinessProbe.httpGet) |
        .readinessProbe.httpGet.path // "/"' 2>/dev/null | \
    sort -u | while IFS= read -r readiness_path; do
        if [ -n "$readiness_path" ] && [ "$readiness_path" != "/" ]; then
            echo "https://$primary_host$readiness_path"
        fi
    done
}

# Function to test a single URL
test_url() {
    local url="$1"
    printf "Testing %-50s ... " "$url"
    
    # Get HTTP status code
    local status_code
    if status_code=$(curl --silent --head --insecure --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" --write-out "%{http_code}" --output /dev/null "$url" 2>/dev/null); then
        # Consider 5xx as failure, everything else as success
        if [[ "$status_code" =~ ^5[0-9][0-9]$ ]]; then
            print_error "✗ $status_code"
            return 1
        else
            print_success "✓ $status_code"
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
    echo "Ingresses: $(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Services: $(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Deployments: $(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Pods: $(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "ReplicaSets: $(kubectl get replicasets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo
}

# Function to show pod status
show_pod_status() {
    print_info "Pod status in namespace $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || print_warning "Could not get pod status"
    echo
}

# Cleanup function
cleanup() {
    # Clean up any temporary files if needed
    rm -f /tmp/verify-e2e-*.tmp 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    # Show resource summary
    show_resource_summary
    
    # Show pod status
    show_pod_status
    
    # Collect URLs
    local temp_ingress_file="/tmp/verify-e2e-ingress-$$"
    local temp_readiness_file="/tmp/verify-e2e-readiness-$$"
    
    get_ingress_urls > "$temp_ingress_file"
    get_readiness_urls > "$temp_readiness_file"
    
    # Combine and deduplicate URLs
    local all_urls_file="/tmp/verify-e2e-all-$$"
    cat "$temp_ingress_file" "$temp_readiness_file" 2>/dev/null | sort -u > "$all_urls_file"
    
    # Read URLs into array
    local all_urls=()
    while IFS= read -r url; do
        if [ -n "$url" ]; then
            all_urls+=("$url")
        fi
    done < "$all_urls_file"

    if [ ${#all_urls[@]} -eq 0 ]; then
        print_warning "No URLs found to test."
        exit 0
    fi

    print_info "Collected URLs to test (${#all_urls[@]} unique URLs):"
    printf -- "- %s\n" "${all_urls[@]}"
    echo

    # Test all URLs
    local success_count=0
    local failed_count=0
    local total_count=${#all_urls[@]}

    for url in "${all_urls[@]}"; do
        if test_url "$url"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done

    echo "=================================================="
    print_info "Test Results Summary:"
    print_success "Successful: $success_count/$total_count"
    if [ $failed_count -gt 0 ]; then
        print_error "Failed: $failed_count/$total_count"
    fi
    
    echo "=================================================="

    if [ $success_count -eq $total_count ]; then
        print_success "All E2E tests passed! 🎉"
        exit 0
    else
        print_warning "Some tests failed. Check the logs above for details."
        exit 1
    fi
}

# Run main function
main
```

- enhance

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
    local ingresses

    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    print_info "Found $ingress_count Ingress resources"

    # Extract hosts and paths from ingress with better error handling
    while IFS= read -r line; do
        if [ -n "$line" ] && [ "$line" != "null" ]; then
            ingress_urls+=("$line")
        fi
    done < <(echo "$ingresses" | jq -r '.items[] |
        .spec.rules[]? |
        select(.host != null) |
        "https://" + .host + (.http.paths[]?.path // "")' 2>/dev/null || true)

    print_info "Extracted ${#ingress_urls[@]} URLs from Ingress resources"
    printf '%s\n' "${ingress_urls[@]}"
}

# Function to test a single URL
test_url() {
    local url="$1"
    printf "Testing %-50s ... " "$url"

    # Get HTTP status code
    local status_code
    if status_code=$(curl --silent --head --insecure --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" --write-out "%{http_code}" --output /dev/null "$url" 2>/dev/null); then
        # Consider 5xx as failure, everything else as success
        if [[ "$status_code" =~ ^5[0-9][0-9]$ ]]; then
            print_error "✗ $status_code"
            return 1
        else
            print_success "✓ $status_code"
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
    echo "Ingresses: $(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Services: $(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Deployments: $(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Pods: $(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "ReplicaSets: $(kubectl get replicasets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo
}

# Function to show pod status
show_pod_status() {
    print_info "Pod status in namespace $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || print_warning "Could not get pod status"
    echo
}

# Main logic
main() {
    # Show resource summary
    show_resource_summary

    # Show pod status
    show_pod_status

    local ingress_urls=$(get_ingress_urls)
    local readiness_urls=$(get_readiness_urls)

    local all_urls=()
    # read urls into array
    while IFS= read -r url; do [ -n "$url" ] && all_urls+=("$url"); done <<< "$ingress_urls"
    while IFS= read -r url; do [ -n "$url" ] && all_urls+=("$url"); done <<< "$readiness_urls"

    # Remove duplicates by sorting and using uniq
    if [ ${#all_urls[@]} -gt 0 ]; then
        local unique_urls=()
        while IFS= read -r url; do
            unique_urls+=("$url")
        done < <(printf '%s\n' "${all_urls[@]}" | sort -u)
        all_urls=("${unique_urls[@]}")
    fi

    if [ ${#all_urls[@]} -eq 0 ]; then
        print_warning "No URLs found to test."
        exit 0
    fi

    print_info "Collected URLs to test:"
    printf -- "- %s\n" "${all_urls[@]}"
    echo

    local success_count=0
    local failed_count=0
    local total_count=${#all_urls[@]}

    for url in "${all_urls[@]}"; do
        if test_url "$url"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done

    echo "=================================================="
    print_info "Test Results Summary:"
    print_success "Successful: $success_count/$total_count"
    if [ $failed_count -gt 0 ]; then
        print_error "Failed: $failed_count/$total_count"
    fi

    echo "=================================================="

    if [ $success_count -eq $total_count ]; then
        print_success "All E2E tests passed! 🎉"
    else
        print_warning "Some tests failed. Check the logs above for details."
        exit 1
    fi
}

# Function to get readiness probe URLs (simplified approach)
get_readiness_urls() {
    print_info "Extracting readiness probe URLs from Deployments..."

    local readiness_urls=()
    local deployments
    local ingresses

    # Get deployments with error handling
    if ! deployments=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Deployment resources from namespace $NAMESPACE"
        return
    fi

    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local deployment_count=$(echo "$deployments" | jq '.items | length' 2>/dev/null || echo "0")
    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")

    if [ "$deployment_count" -eq 0 ]; then
        print_warning "No Deployment resources found in namespace $NAMESPACE"
        return
    fi

    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    # Get the first ingress host as primary host
    local primary_host
    primary_host=$(echo "$ingresses" | jq -r '.items[0].spec.rules[0]?.host' 2>/dev/null || echo "")

    if [ -z "$primary_host" ] || [ "$primary_host" = "null" ]; then
        print_warning "No valid host found in Ingress resources"
        return
    fi

    # Extract unique readiness probe paths from deployments
    local unique_paths=()
    while IFS= read -r readiness_path; do
        if [ -n "$readiness_path" ] && [ "$readiness_path" != "/" ]; then
            # Check if path already exists
            local path_exists=false
            for existing_path in "${unique_paths[@]}"; do
                if [ "$existing_path" = "$readiness_path" ]; then
                    path_exists=true
                    break
                fi
            done
            if [ "$path_exists" = false ]; then
                unique_paths+=("$readiness_path")
            fi
        fi
    done < <(echo "$deployments" | jq -r '
        .items[] |
        .spec.template.spec.containers[]? |
        select(.readinessProbe.httpGet) |
        .readinessProbe.httpGet.path // "/"' 2>/dev/null || true)

    # Generate URLs using primary host and unique paths
    for path in "${unique_paths[@]}"; do
        local full_url="https://$primary_host$path"
        readiness_urls+=("$full_url")
    done

    print_info "Generated ${#readiness_urls[@]} readiness probe URLs using host: $primary_host"
    printf '%s\n' "${readiness_urls[@]}"
}

# Cleanup function (simplified since we're not using port-forwarding)
cleanup() {
    # Clean up any temporary files if needed
    rm -f /tmp/verify-e2e-*.tmp 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main
```

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
    local ingresses

    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")
    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    print_info "Found $ingress_count Ingress resources"

    # Extract hosts and paths from ingress with better error handling
    while IFS= read -r line; do
        if [ -n "$line" ] && [ "$line" != "null" ]; then
            ingress_urls+=("$line")
        fi
    done < <(echo "$ingresses" | jq -r '.items[] |
        .spec.rules[]? |
        select(.host != null) |
        "https://" + .host + (.http.paths[]?.path // "")' 2>/dev/null || true)

    print_info "Extracted ${#ingress_urls[@]} URLs from Ingress resources"
    printf '%s\n' "${ingress_urls[@]}"
}

# Function to test a single URL
test_url() {
    local url="$1"
    printf "Testing %-50s ... " "$url"

    # Simple curl test with timeout, suppress all error output
    if curl --silent --head --fail --insecure --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$url" >/dev/null 2>&1; then
        print_success "✓ OK"
        return 0
    else
        print_error "✗ FAIL"
        return 1
    fi
}

# Function to show resource summary
show_resource_summary() {
    print_info "Resource summary for namespace $NAMESPACE:"
    echo "Ingresses: $(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Services: $(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Deployments: $(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "Pods: $(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo "ReplicaSets: $(kubectl get replicasets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)"
    echo
}

# Function to show pod status
show_pod_status() {
    print_info "Pod status in namespace $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || print_warning "Could not get pod status"
    echo
}

# Main logic
main() {
    # Show resource summary
    show_resource_summary

    # Show pod status
    show_pod_status

    local ingress_urls=$(get_ingress_urls)
    local readiness_urls=$(get_readiness_urls)

    local all_urls=()
    # read urls into array
    while IFS= read -r url; do [ -n "$url" ] && all_urls+=("$url"); done <<< "$ingress_urls"
    while IFS= read -r url; do [ -n "$url" ] && all_urls+=("$url"); done <<< "$readiness_urls"

    if [ ${#all_urls[@]} -eq 0 ]; then
        print_warning "No URLs found to test."
        exit 0
    fi

    print_info "Collected URLs to test:"
    printf -- "- %s\n" "${all_urls[@]}"
    echo

    local success_count=0
    local failed_count=0
    local total_count=${#all_urls[@]}

    for url in "${all_urls[@]}"; do
        if test_url "$url"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done

    echo "=================================================="
    print_info "Test Results Summary:"
    print_success "Successful: $success_count/$total_count"
    if [ $failed_count -gt 0 ]; then
        print_error "Failed: $failed_count/$total_count"
    fi

    echo "=================================================="

    if [ $success_count -eq $total_count ]; then
        print_success "All E2E tests passed! 🎉"
    else
        print_warning "Some tests failed. Check the logs above for details."
        exit 1
    fi
}

# Function to get readiness probe URLs by combining Ingress hosts with readiness paths
get_readiness_urls() {
    print_info "Extracting readiness probe URLs from Deployments and matching with Ingress hosts..."

    local readiness_urls=()
    local deployments
    local ingresses

    # Get deployments with error handling
    if ! deployments=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Deployment resources from namespace $NAMESPACE"
        return
    fi

    # Get ingresses with error handling
    if ! ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json 2>/dev/null); then
        print_warning "Failed to get Ingress resources from namespace $NAMESPACE"
        return
    fi

    local deployment_count=$(echo "$deployments" | jq '.items | length' 2>/dev/null || echo "0")
    local ingress_count=$(echo "$ingresses" | jq '.items | length' 2>/dev/null || echo "0")

    if [ "$deployment_count" -eq 0 ]; then
        print_warning "No Deployment resources found in namespace $NAMESPACE"
        return
    fi

    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    # Get all ingress hosts
    local ingress_hosts=()
    while IFS= read -r host; do
        if [ -n "$host" ] && [ "$host" != "null" ]; then
            ingress_hosts+=("$host")
        fi
    done < <(echo "$ingresses" | jq -r '.items[].spec.rules[]?.host' 2>/dev/null || true)

    if [ ${#ingress_hosts[@]} -eq 0 ]; then
        print_warning "No hosts found in Ingress resources"
        return
    fi

    # Extract readiness probe paths from deployments
    local readiness_paths=()
    while IFS='|' read -r dep_name readiness_path; do
        if [ -n "$dep_name" ] && [ -n "$readiness_path" ]; then
            readiness_paths+=("$readiness_path")
        fi
    done < <(echo "$deployments" | jq -r '
        .items[] |
        .metadata.name as $dep_name |
        .spec.template.spec.containers[]? |
        select(.readinessProbe.httpGet) |
        $dep_name + "|" + (.readinessProbe.httpGet.path // "/")' 2>/dev/null || true)

    # Combine hosts with readiness paths
    for host in "${ingress_hosts[@]}"; do
        for path in "${readiness_paths[@]}"; do
            local full_url="https://$host$path"
            readiness_urls+=("$full_url")
        done
    done

    print_info "Generated ${#readiness_urls[@]} readiness probe URLs"
    printf '%s\n' "${readiness_urls[@]}"
}

# Cleanup function (simplified since we're not using port-forwarding)
cleanup() {
    # Clean up any temporary files if needed
    rm -f /tmp/verify-e2e-*.tmp 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main
```
