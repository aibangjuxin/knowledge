#!/bin/bash

# Network Connectivity Verification Script for K8s Cluster Migration
# This script verifies connectivity to new cluster services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NEW_CLUSTER_ENDPOINTS=(
    "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
    "kong.dev.aliyun.intracloud.cn.aibang"
)

PORTS=(80 443 8078)
TIMEOUT=10

echo "=== K8s Cluster Migration - Network Connectivity Verification ==="
echo "Timestamp: $(date)"
echo ""

# Function to test DNS resolution
test_dns_resolution() {
    local endpoint=$1
    echo -n "Testing DNS resolution for $endpoint... "
    
    if nslookup "$endpoint" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# Function to test port connectivity
test_port_connectivity() {
    local endpoint=$1
    local port=$2
    echo -n "Testing connectivity to $endpoint:$port... "
    
    if timeout $TIMEOUT nc -z "$endpoint" "$port" 2>/dev/null; then
        echo -e "${GREEN}✓ SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# Function to test HTTP/HTTPS endpoints
test_http_endpoint() {
    local endpoint=$1
    local port=$2
    local protocol="http"
    
    if [ "$port" = "443" ]; then
        protocol="https"
    fi
    
    echo -n "Testing HTTP endpoint ${protocol}://$endpoint:$port/... "
    
    if timeout $TIMEOUT curl -s -o /dev/null -w "%{http_code}" "${protocol}://$endpoint:$port/" | grep -q "200\|301\|302\|404"; then
        echo -e "${GREEN}✓ SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# Function to verify ExternalName service resolution
verify_external_service() {
    local service_name=$1
    local namespace=$2
    echo -n "Verifying ExternalName service $service_name in namespace $namespace... "
    
    if kubectl get service "$service_name" -n "$namespace" > /dev/null 2>&1; then
        local external_name=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.externalName}')
        echo -e "${GREEN}✓ SUCCESS${NC} (points to: $external_name)"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# Main verification process
main() {
    local dns_failures=0
    local port_failures=0
    local http_failures=0
    local service_failures=0
    
    echo "1. DNS Resolution Tests"
    echo "======================"
    for endpoint in "${NEW_CLUSTER_ENDPOINTS[@]}"; do
        if ! test_dns_resolution "$endpoint"; then
            ((dns_failures++))
        fi
    done
    echo ""
    
    echo "2. Port Connectivity Tests"
    echo "=========================="
    for endpoint in "${NEW_CLUSTER_ENDPOINTS[@]}"; do
        for port in "${PORTS[@]}"; do
            if ! test_port_connectivity "$endpoint" "$port"; then
                ((port_failures++))
            fi
        done
    done
    echo ""
    
    echo "3. HTTP/HTTPS Endpoint Tests"
    echo "============================"
    for endpoint in "${NEW_CLUSTER_ENDPOINTS[@]}"; do
        for port in 80 443; do
            if ! test_http_endpoint "$endpoint" "$port"; then
                ((http_failures++))
            fi
        done
    done
    echo ""
    
    echo "4. ExternalName Service Verification"
    echo "===================================="
    services=(
        "new-cluster-bbdm-api:aibang-1111111111-bbdm"
        "new-cluster-gateway:aibang-1111111111-bbdm"
        "new-cluster-health:aibang-1111111111-bbdm"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name namespace <<< "$service_info"
        if ! verify_external_service "$service_name" "$namespace"; then
            ((service_failures++))
        fi
    done
    echo ""
    
    # Summary
    echo "=== VERIFICATION SUMMARY ==="
    echo "DNS Resolution Failures: $dns_failures"
    echo "Port Connectivity Failures: $port_failures"
    echo "HTTP Endpoint Failures: $http_failures"
    echo "ExternalName Service Failures: $service_failures"
    echo ""
    
    local total_failures=$((dns_failures + port_failures + http_failures + service_failures))
    
    if [ $total_failures -eq 0 ]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED - New cluster connectivity verified${NC}"
        exit 0
    else
        echo -e "${RED}✗ $total_failures TESTS FAILED - Please check network configuration${NC}"
        exit 1
    fi
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Warning: kubectl not found. ExternalName service verification will be skipped.${NC}"
fi

# Check if nc (netcat) is available
if ! command -v nc &> /dev/null; then
    echo -e "${YELLOW}Warning: nc (netcat) not found. Port connectivity tests may fail.${NC}"
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: curl not found. HTTP endpoint tests will be skipped.${NC}"
fi

# Run main verification
main