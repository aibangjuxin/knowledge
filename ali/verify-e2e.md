API flow
Ingress → Service → Pod → ReplicaSet → Deployment → readinessProbe）

我现在想写这样一个脚本 传参就是 Namespace 的名字比如
verify-e2e.sh -n mynamespace

然后呢,获取到里面所有对应的资源 然后就包括我的这个 follow 的流程 然后我想拿到我所有的 e2e 的测试的 URL
然后进行一个简单的 curl 请求

因为我们知道 Ingress 里面比如说有 host,然后 deploy 最终的 readiness 里面有具体的 url,所以说我能拿到一些对应的信息。

```bash
#!/bin/bash
# E2E Verification Script for Kubernetes Resources
# Usage: ./verify-e2e.sh -n <namespace>

# Exit on error in pipes
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
TIMEOUT=10
VERBOSE=false

# --- Helper Functions ---

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_debug() { [ "$VERBOSE" = true ] && echo -e "${BLUE}[DEBUG]${NC} $1"; }

usage() {
    cat <<EOF
Usage: $0 -n <namespace> [-t <timeout>] [-v]
  -n: Kubernetes namespace (required)
  -t: Timeout for curl requests in seconds (default: 10)
  -v: Enable verbose/debug output
  -h: Show this help message

Examples:
  $0 -n production                    # Test production namespace
  $0 -n staging -t 30 -v             # Test staging with 30s timeout and verbose output
EOF
    exit 1
}

# Function to deduplicate array elements
# Usage: deduplicate_array "original_array_name" "new_array_name"
deduplicate_array() {
    local -n _source_arr=$1
    local -n _dest_arr=$2
    if [ ${#_source_arr[@]} -gt 0 ]; then
        _dest_arr=()
        while IFS= read -r item; do
            [ -n "$item" ] && _dest_arr+=("$item")
        done < <(printf '%s\n' "${_source_arr[@]}" | sort -u)
    fi
}

# Function to normalize URL paths
# Handles edge cases in path combination
normalize_path() {
    local ingress_path="$1"
    local probe_path="$2"
    
    # Remove trailing slash from ingress_path if it's not root
    if [ "$ingress_path" != "/" ]; then
        ingress_path="${ingress_path%/}"
    fi
    
    # Ensure probe_path starts with slash
    if [ "${probe_path:0:1}" != "/" ]; then
        probe_path="/$probe_path"
    fi
    
    # Combine paths
    if [ "$ingress_path" = "/" ]; then
        echo "$probe_path"
    else
        echo "$ingress_path$probe_path"
    fi
}

# --- Kubernetes Data Extraction Functions ---

get_ingress_urls() {
    local -n _ingress_json_ref=$1
    local -n _urls_ref=$2
    print_info "Extracting base URLs from Ingress resources..."

    local ingress_count
    ingress_count=$(echo "$_ingress_json_ref" | jq '.items | length')
    if [ "$ingress_count" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi
    print_info "Found $ingress_count Ingress resources"

    local extracted_urls=()
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" != "null" ]]; then
            extracted_urls+=("$line")
            print_debug "Extracted Ingress URL: $line"
        fi
    done < <(echo "$_ingress_json_ref" | jq -r '
        .items[] |
        .spec.rules[]? |
        select(.host != null) |
        .http.paths[]? |
        "https://" + .host + (.path // "")
    ')
    
    deduplicate_array extracted_urls _urls_ref
    print_info "Extracted ${#_urls_ref[@]} unique base URLs from Ingresses"
    if [ "$VERBOSE" = true ]; then
        printf '  - %s\n' "${_urls_ref[@]}"
    fi
}

get_readiness_urls() {
    local -n _ingress_json_ref=$1
    local -n _service_json_ref=$2
    local -n _deployment_json_ref=$3
    local -n _urls_ref=$4
    print_info "Extracting readiness probe URLs based on resource relationships..."

    local extracted_urls=()
    local temp_file="/tmp/readiness_output_$$"
    
    # Create a more robust jq query with better path handling
    jq -r --argjson services "$_service_json_ref" --argjson deployments "$_deployment_json_ref" '
    # Iterate over each Ingress object
    .items[] as $ingress |
    $ingress.metadata.name as $ingress_name |
    
    # Iterate over each rule in the Ingress
    $ingress.spec.rules[]? as $rule |
    $rule.host as $host |
    
    # Ensure the host exists
    if ($host and $host != null) then
        # Iterate over each path in the rule
        $rule.http.paths[]? as $path_rule |
        
        ($path_rule.path // "/") as $ingress_path |
        ($path_rule.backend.service.name // $path_rule.backend.serviceName // empty) as $service_name |
        
        if ($service_name and $service_name != null) then
            # Find the matching Service
            ($services.items[] | select(.metadata.name == $service_name)) as $service |
            
            if ($service) then
                $service.spec.selector as $selector |
                
                if ($selector and ($selector | length > 0)) then
                    # Find Deployments whose labels match the Service selector
                    $deployments.items[] as $deployment |
                    $deployment.metadata.name as $deployment_name |
                    
                    # Check if all selector labels match deployment labels
                    (
                        [$selector | to_entries[] as $sel_entry | 
                         $deployment.spec.template.metadata.labels[$sel_entry.key] == $sel_entry.value] | all
                    ) as $labels_match |

                    if ($labels_match) then
                        "# Mapping: \($ingress_name) -> \($service_name) -> \($deployment_name)",
                        
                        # Extract readiness probe from containers in the matching Deployment
                        ($deployment.spec.template.spec.containers[]? |
                        select(.readinessProbe and .readinessProbe.httpGet) |
                        .readinessProbe.httpGet.path) as $probe_path |
                        
                        if ($probe_path and $probe_path != "/" and $probe_path != null) then
                            # Better path combination logic
                            (
                                if ($ingress_path == "/") then
                                    $probe_path
                                else
                                    ($ingress_path | sub("/$"; "")) + $probe_path
                                end
                            ) as $full_path |
                            "https://\($host)\($full_path)"
                        else empty end
                    else 
                        "# Debug: Labels don'\''t match for deployment \($deployment_name)"
                    end
                else 
                    "# Warning: Service \($service_name) has no selector"
                end
            else 
                "# Warning: Service \($service_name) (from Ingress \($ingress_name)) not found"
            end
        else 
            "# Debug: No service name found in path rule"
        end
    else 
        "# Debug: No host found in rule"
    end
    ' <<< "$_ingress_json_ref" > "$temp_file"
    
    # Process the output
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" != "null" ]]; then
            if [[ "$line" == \#* ]]; then
                # This is a comment/mapping info line
                local message="${line#\# }"
                if [[ "$line" == *"Warning:"* ]]; then
                    print_warning "$message"
                elif [[ "$line" == *"Debug:"* ]]; then
                    print_debug "$message"
                elif [[ "$line" == *"Mapping:"* ]]; then
                    print_info "$message"
                fi
            else
                # This is a URL
                extracted_urls+=("$line")
                print_success "Generated readiness URL: $line"
            fi
        fi
    done < "$temp_file"
    
    # Clean up temp file
    rm -f "$temp_file"
    
    deduplicate_array extracted_urls _urls_ref
    print_info "Generated ${#_urls_ref[@]} unique readiness probe URLs"
}

# --- Display Functions ---

show_resource_summary() {
    local -n ing_json=$1 svc_json=$2 dep_json=$3 pod_json=$4 rs_json=$5
    print_info "Resource summary for namespace $NAMESPACE:"
    echo "  Ingresses:   $(echo "$ing_json" | jq '.items | length')"
    echo "  Services:    $(echo "$svc_json" | jq '.items | length')"
    echo "  Deployments: $(echo "$dep_json" | jq '.items | length')"
    echo "  Pods:        $(echo "$pod_json" | jq '.items | length')"
    echo "  ReplicaSets: $(echo "$rs_json" | jq '.items | length')"
    echo
}

show_pod_status() {
    print_info "Pod status in namespace $NAMESPACE:"
    if ! kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null; then
        print_warning "Could not get pod status"
    fi
    echo
}

show_resource_relationships() {
    local -n ing_json=$1 svc_json=$2
    if [ "$VERBOSE" = true ]; then
        print_info "Ingress -> Service relationships:"
        echo "$ing_json" | jq -r '
        .items[] as $ingress |
        $ingress.metadata.name as $ingress_name |
        $ingress.spec.rules[]? as $rule |
        $rule.host as $host |
        $rule.http.paths[]? as $path |
        ($path.backend.service.name // $path.backend.serviceName // "unknown") as $service_name |
        ($path.path // "/") as $path_value |
        "  \($ingress_name) (\($host)\($path_value)) -> \($service_name)"
        ' 2>/dev/null || print_warning "Could not analyze ingress relationships"
        echo
    fi
}

# --- Test Execution ---

test_url() {
    local url="$1"
    printf "🧪 Testing %-60s ... " "$url"
    
    local status_code curl_exit_code
    # Use a more comprehensive curl command with better error handling
    status_code=$(curl -k -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$TIMEOUT" \
        --max-time "$TIMEOUT" \
        --retry 1 \
        --retry-delay 1 \
        --user-agent "K8s-E2E-Verifier/1.0" \
        "$url" 2>/dev/null)
    curl_exit_code=$?

    if [ $curl_exit_code -ne 0 ]; then
        case $curl_exit_code in
            6) print_error "✗ DNS_RESOLUTION_FAILED" ;;
            7) print_error "✗ CONNECTION_FAILED" ;;
            28) print_error "✗ TIMEOUT" ;;
            *) print_error "✗ CURL_ERROR($curl_exit_code)" ;;
        esac
        return 1
    fi

    case "${status_code:0:1}" in
        2|3) print_success "✓ $status_code"; return 0 ;;
        4) print_warning "! $status_code (Client Error)"; return 0 ;;  # Treat 4xx as acceptable
        5) print_error "✗ $status_code (Server Error)"; return 1 ;;
        *) print_warning "? $status_code (Unknown)"; return 1 ;;
    esac
}

# --- Cleanup Function ---

cleanup() {
    print_debug "Cleaning up temporary files..."
    rm -f /tmp/readiness_output_$$ /tmp/verify-e2e-* 2>/dev/null || true
}

# --- Main Logic ---

main() {
    # Set trap for cleanup
    trap cleanup EXIT
    
    # --- Argument Parsing ---
    while getopts "n:t:vh" opt; do
        case $opt in
            n) NAMESPACE="$OPTARG" ;;
            t) TIMEOUT="$OPTARG" ;;
            v) VERBOSE=true ;;
            h) usage ;;
            \?) print_error "Invalid option: -$OPTARG"; usage ;;
        esac
    done

    # --- Pre-flight Checks ---
    if [ -z "$NAMESPACE" ]; then 
        print_error "Namespace is required!"
        usage
    fi
    
    if ! command -v kubectl &> /dev/null; then 
        print_error "kubectl not found in PATH!"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then 
        print_error "jq not found in PATH!"
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then 
        print_error "Namespace '$NAMESPACE' does not exist or is not accessible"
        exit 1
    fi

    print_info "Starting E2E verification for namespace: $NAMESPACE"
    [ "$VERBOSE" = true ] && print_info "Verbose mode enabled"
    echo "=================================================="

    # --- Data Collection (Single API Call per Resource) ---
    print_info "Fetching all necessary resources from namespace '$NAMESPACE'..."
    local ingress_json service_json deployment_json pod_json rs_json
    
    print_debug "Fetching Ingresses..."
    ingress_json=$(kubectl get ingress -n "$NAMESPACE" -o json) || {
        print_error "Failed to fetch Ingresses from namespace $NAMESPACE"
        exit 1
    }
    
    print_debug "Fetching Services..."
    service_json=$(kubectl get service -n "$NAMESPACE" -o json) || {
        print_error "Failed to fetch Services from namespace $NAMESPACE"
        exit 1
    }
    
    print_debug "Fetching Deployments..."
    deployment_json=$(kubectl get deployment -n "$NAMESPACE" -o json) || {
        print_error "Failed to fetch Deployments from namespace $NAMESPACE"
        exit 1
    }
    
    print_debug "Fetching Pods..."
    pod_json=$(kubectl get pods -n "$NAMESPACE" -o json) || {
        print_error "Failed to fetch Pods from namespace $NAMESPACE"
        exit 1
    }
    
    print_debug "Fetching ReplicaSets..."
    rs_json=$(kubectl get replicaset -n "$NAMESPACE" -o json) || {
        print_error "Failed to fetch ReplicaSets from namespace $NAMESPACE"
        exit 1
    }
    
    print_success "Successfully fetched all Kubernetes resources"
    echo "=================================================="

    # --- Information Display ---
    show_resource_summary ingress_json service_json deployment_json pod_json rs_json
    show_resource_relationships ingress_json service_json
    show_pod_status
    
    # --- URL Generation ---
    print_info "Collecting URLs for testing..."
    echo "=================================================="
    
    local ingress_urls=()
    local readiness_urls=()
    
    get_ingress_urls ingress_json ingress_urls
    echo
    get_readiness_urls ingress_json service_json deployment_json readiness_urls
    echo

    # Combine and deduplicate all URLs
    local all_urls=("${ingress_urls[@]}" "${readiness_urls[@]}")
    local unique_urls=()
    deduplicate_array all_urls unique_urls

    if [ ${#unique_urls[@]} -eq 0 ]; then
        print_warning "No URLs found to test."
        print_info "This might indicate:"
        print_info "  1. No Ingress resources with valid hosts"
        print_info "  2. No Deployments with readiness probes"
        print_info "  3. Service selectors don't match Deployment labels"
        print_info "  4. Missing httpGet readiness probes in containers"
        exit 0
    fi
    
    print_info "Final unique URL collection for testing (${#unique_urls[@]} URLs):"
    printf -- "  - %s\n" "${unique_urls[@]}"
    echo

    # --- Run Tests ---
    echo "=================================================="
    print_info "Starting URL tests (timeout: ${TIMEOUT}s)..."
    echo "=================================================="
    
    local success_count=0 failed_count=0 warning_count=0
    local total_count=${#unique_urls[@]}
    local start_time=$(date +%s)

    for url in "${unique_urls[@]}"; do
        if test_url "$url"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # --- Final Summary ---
    echo "=================================================="
    print_info "Test Results Summary:"
    print_success "Successful: $success_count/$total_count"
    [ $failed_count -gt 0 ] && print_error "Failed:     $failed_count/$total_count"
    print_info "Total time: ${duration}s"
    echo "=================================================="

    if [ $failed_count -eq 0 ]; then
        print_success "All E2E tests passed! 🎉"
        exit 0
    elif [ $success_count -gt 0 ]; then
        print_warning "Partial success: $success_count out of $total_count tests passed"
        exit 1
    else
        print_error "All tests failed! Please check your deployments and ingress configurations"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
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
