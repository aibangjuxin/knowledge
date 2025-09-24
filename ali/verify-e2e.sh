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

# Function to test a single URL
test_url() {
    local url="$1"
    print_info "Testing URL: $url"
    # Using --insecure for self-signed certs often found in k8s
    # Added --show-error to see curl errors, and redirect stdout/stderr to /dev/null
    if curl --silent --head --fail --show-error --insecure --timeout "$TIMEOUT" "$url" > /dev/null 2>&1; then
        print_success "OK"
        return 0
    else
        # Capturing exit code for better error message
        local exit_code=$?
        print_error "FAIL (curl exit code: $exit_code)"
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
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o json)
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" -o json)

    if [ "$(echo "$deployments" | jq '.items | length')" -eq 0 ]; then
        print_warning "No Deployment resources found in namespace $NAMESPACE"
        return
    fi

    if [ "$(echo "$ingresses" | jq '.items | length')" -eq 0 ]; then
        print_warning "No Ingress resources found in namespace $NAMESPACE"
        return
    fi

    # Get all ingress hosts
    local ingress_hosts=()
    while IFS= read -r host; do
        if [ -n "$host" ] && [ "$host" != "null" ]; then
            ingress_hosts+=("$host")
        fi
    done < <(echo "$ingresses" | jq -r '.items[].spec.rules[]?.host')

    if [ ${#ingress_hosts[@]} -eq 0 ]; then
        print_warning "No hosts found in Ingress resources"
        return
    fi

    # Extract readiness probe paths from deployments
    while IFS='|' read -r dep_name readiness_path; do
        if [ -n "$dep_name" ] && [ -n "$readiness_path" ]; then
            # Combine each ingress host with the readiness path
            for host in "${ingress_hosts[@]}"; do
                local full_url="https://$host$readiness_path"
                readiness_urls+=("$full_url")
            done
        fi
    done < <(echo "$deployments" | jq -r '
        .items[] |
        .metadata.name as $dep_name |
        .spec.template.spec.containers[]? |
        select(.readinessProbe.httpGet) |
        $dep_name + "|" + (.readinessProbe.httpGet.path // "/")')

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