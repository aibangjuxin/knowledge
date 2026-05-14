#!/bin/bash

# Deployment script for ExternalName services in K8s cluster migration
# This script deploys and configures ExternalName services for the migration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="aibang-1111111111-bbdm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/k8s"

echo -e "${BLUE}=== K8s Cluster Migration - ExternalName Services Deployment ===${NC}"
echo "Timestamp: $(date)"
echo "Namespace: $NAMESPACE"
echo "K8s manifests directory: $K8S_DIR"
echo ""

# Function to check if namespace exists
check_namespace() {
    echo -n "Checking if namespace $NAMESPACE exists... "
    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ EXISTS${NC}"
        return 0
    else
        echo -e "${YELLOW}! NOT FOUND${NC}"
        echo -n "Creating namespace $NAMESPACE... "
        kubectl create namespace "$NAMESPACE"
        echo -e "${GREEN}✓ CREATED${NC}"
        return 0
    fi
}

# Function to deploy ExternalName services
deploy_external_services() {
    echo -e "${BLUE}Deploying ExternalName services...${NC}"
    
    if [ -f "$K8S_DIR/external-services.yaml" ]; then
        echo -n "Applying external-services.yaml... "
        kubectl apply -f "$K8S_DIR/external-services.yaml"
        echo -e "${GREEN}✓ APPLIED${NC}"
    else
        echo -e "${RED}✗ external-services.yaml not found in $K8S_DIR${NC}"
        exit 1
    fi
}

# Function to deploy DNS configuration
deploy_dns_config() {
    echo -e "${BLUE}Deploying DNS configuration...${NC}"
    
    if [ -f "$K8S_DIR/dns-config.yaml" ]; then
        echo -n "Applying dns-config.yaml... "
        kubectl apply -f "$K8S_DIR/dns-config.yaml"
        echo -e "${GREEN}✓ APPLIED${NC}"
    else
        echo -e "${YELLOW}! dns-config.yaml not found, skipping${NC}"
    fi
}

# Function to verify deployed services
verify_services() {
    echo -e "${BLUE}Verifying deployed ExternalName services...${NC}"
    
    services=(
        "new-cluster-bbdm-api"
        "new-cluster-gateway"
        "new-cluster-health"
    )
    
    for service in "${services[@]}"; do
        echo -n "Checking service $service... "
        if kubectl get service "$service" -n "$NAMESPACE" > /dev/null 2>&1; then
            local external_name=$(kubectl get service "$service" -n "$NAMESPACE" -o jsonpath='{.spec.externalName}')
            echo -e "${GREEN}✓ DEPLOYED${NC} (points to: $external_name)"
        else
            echo -e "${RED}✗ NOT FOUND${NC}"
        fi
    done
}

# Function to show service details
show_service_details() {
    echo -e "${BLUE}ExternalName Service Details:${NC}"
    echo ""
    
    kubectl get services -n "$NAMESPACE" -l "component=external-service" -o wide
    echo ""
    
    echo -e "${BLUE}Service Endpoints:${NC}"
    services=(
        "new-cluster-bbdm-api"
        "new-cluster-gateway"
        "new-cluster-health"
    )
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" > /dev/null 2>&1; then
            echo "Service: $service"
            kubectl get service "$service" -n "$NAMESPACE" -o yaml | grep -A 10 "spec:"
            echo "---"
        fi
    done
}

# Function to test connectivity
test_connectivity() {
    echo -e "${BLUE}Testing connectivity to new cluster endpoints...${NC}"
    
    if [ -f "$SCRIPT_DIR/verify-connectivity.sh" ]; then
        bash "$SCRIPT_DIR/verify-connectivity.sh"
    else
        echo -e "${YELLOW}! verify-connectivity.sh not found, skipping connectivity tests${NC}"
    fi
}

# Main deployment process
main() {
    echo "1. Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl not found. Please install kubectl first.${NC}"
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info > /dev/null 2>&1; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Prerequisites check passed${NC}"
    echo ""
    
    echo "2. Setting up namespace..."
    check_namespace
    echo ""
    
    echo "3. Deploying ExternalName services..."
    deploy_external_services
    echo ""
    
    echo "4. Deploying DNS configuration..."
    deploy_dns_config
    echo ""
    
    echo "5. Verifying deployment..."
    verify_services
    echo ""
    
    echo "6. Showing service details..."
    show_service_details
    echo ""
    
    echo "7. Testing connectivity..."
    test_connectivity
    echo ""
    
    echo -e "${GREEN}=== ExternalName Services Deployment Complete ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Verify that all services are properly configured"
    echo "2. Test DNS resolution from within the cluster"
    echo "3. Configure the migration proxy to use these services"
    echo "4. Run end-to-end connectivity tests"
}

# Handle script arguments
case "${1:-}" in
    "deploy")
        main
        ;;
    "verify")
        verify_services
        ;;
    "test")
        test_connectivity
        ;;
    "show")
        show_service_details
        ;;
    *)
        echo "Usage: $0 {deploy|verify|test|show}"
        echo ""
        echo "Commands:"
        echo "  deploy  - Deploy all ExternalName services and configurations"
        echo "  verify  - Verify that services are deployed correctly"
        echo "  test    - Test connectivity to new cluster endpoints"
        echo "  show    - Show detailed service information"
        exit 1
        ;;
esac