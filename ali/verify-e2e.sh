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