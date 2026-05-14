- enhance the output format
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

# Function to calculate column widths
calculate_column_widths() {
    local deployments_json="$1"
    
    # Initialize minimum widths (header lengths)
    local max_deployment_width=10  # "DEPLOYMENT"
    local max_container_width=9    # "CONTAINER"
    local max_cpu_req_width=11     # "CPU_REQUEST"
    local max_cpu_lim_width=9      # "CPU_LIMIT"
    local max_mem_req_width=11     # "MEM_REQUEST"
    local max_mem_lim_width=9      # "MEM_LIMIT"
    
    # Process data to find maximum widths
    while IFS='|' read -r deployment container cpu_req cpu_lim mem_req mem_lim; do
        if [ -n "$deployment" ]; then
            # Calculate actual display lengths
            local dep_len=${#deployment}
            local cont_len=${#container}
            
            # Convert and get display lengths for resources
            local cpu_req_converted=$(convert_cpu "$cpu_req")
            local cpu_lim_converted=$(convert_cpu "$cpu_lim")
            local mem_req_converted=$(convert_memory "$mem_req")
            local mem_lim_converted=$(convert_memory "$mem_lim")
            
            local cpu_req_display="${cpu_req_converted:-"-"}"
            local cpu_lim_display="${cpu_lim_converted:-"-"}"
            local mem_req_display="${mem_req_converted:-"-"}"
            local mem_lim_display="${mem_lim_converted:-"-"}"
            
            local cpu_req_len=${#cpu_req_display}
            local cpu_lim_len=${#cpu_lim_display}
            local mem_req_len=${#mem_req_display}
            local mem_lim_len=${#mem_lim_display}
            
            # Update maximum widths
            [ $dep_len -gt $max_deployment_width ] && max_deployment_width=$dep_len
            [ $cont_len -gt $max_container_width ] && max_container_width=$cont_len
            [ $cpu_req_len -gt $max_cpu_req_width ] && max_cpu_req_width=$cpu_req_len
            [ $cpu_lim_len -gt $max_cpu_lim_width ] && max_cpu_lim_width=$cpu_lim_len
            [ $mem_req_len -gt $max_mem_req_width ] && max_mem_req_width=$mem_req_len
            [ $mem_lim_len -gt $max_mem_lim_width ] && max_mem_lim_width=$mem_lim_len
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
    
    # Add some padding
    max_deployment_width=$((max_deployment_width + 2))
    max_container_width=$((max_container_width + 2))
    max_cpu_req_width=$((max_cpu_req_width + 2))
    max_cpu_lim_width=$((max_cpu_lim_width + 2))
    max_mem_req_width=$((max_mem_req_width + 2))
    max_mem_lim_width=$((max_mem_lim_width + 2))
    
    # Return widths as space-separated values
    echo "$max_deployment_width $max_container_width $max_cpu_req_width $max_cpu_lim_width $max_mem_req_width $max_mem_lim_width"
}

# Function to print separator line
print_separator() {
    local dep_width=$1
    local cont_width=$2
    local cpu_req_width=$3
    local cpu_lim_width=$4
    local mem_req_width=$5
    local mem_lim_width=$6
    
    printf "%*s %*s %*s %*s %*s %*s\n" \
        $dep_width "$(printf '%*s' $dep_width '' | tr ' ' '-')" \
        $cont_width "$(printf '%*s' $cont_width '' | tr ' ' '-')" \
        $cpu_req_width "$(printf '%*s' $cpu_req_width '' | tr ' ' '-')" \
        $cpu_lim_width "$(printf '%*s' $cpu_lim_width '' | tr ' ' '-')" \
        $mem_req_width "$(printf '%*s' $mem_req_width '' | tr ' ' '-')" \
        $mem_lim_width "$(printf '%*s' $mem_lim_width '' | tr ' ' '-')"
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

    # Calculate optimal column widths
    local widths=($(calculate_column_widths "$deployments_json"))
    local dep_width=${widths[0]}
    local cont_width=${widths[1]}
    local cpu_req_width=${widths[2]}
    local cpu_lim_width=${widths[3]}
    local mem_req_width=${widths[4]}
    local mem_lim_width=${widths[5]}

    # Print table header with dynamic widths
    printf "%-*s %-*s %-*s %-*s %-*s %-*s\n" \
        $dep_width "DEPLOYMENT" \
        $cont_width "CONTAINER" \
        $cpu_req_width "CPU_REQUEST" \
        $cpu_lim_width "CPU_LIMIT" \
        $mem_req_width "MEM_REQUEST" \
        $mem_lim_width "MEM_LIMIT"
    
    # Print separator line
    print_separator $dep_width $cont_width $cpu_req_width $cpu_lim_width $mem_req_width $mem_lim_width

    # Process each deployment with dynamic widths
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
        
        printf "%-*s %-*s %-*s %-*s %-*s %-*s\n" \
            $dep_width "$deployment" \
            $cont_width "$container" \
            $cpu_req_width "$cpu_req_display" \
            $cpu_lim_width "$cpu_lim_display" \
            $mem_req_width "$mem_req_display" \
            $mem_lim_width "$mem_lim_display"
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