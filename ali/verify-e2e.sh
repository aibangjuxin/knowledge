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