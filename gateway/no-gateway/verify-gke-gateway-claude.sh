#!/bin/bash

#==============================================================================
# GKE Internal Gateway Verification Script
# Purpose: Verify GKE Gateway API configuration and resource status
# Author: Infrastructure Team
# Version: 1.1
#==============================================================================

set -e

# Color Output Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
}

# Show Usage Information
show_usage() {
    echo "Usage: $0 -g <gateway-namespace> -u <user-namespace>"
    echo ""
    echo "Options:"
    echo "  -g    Gateway Namespace (Required)"
    echo "  -u    User Namespace (Required)"
    echo "  -h    Show help information"
    echo ""
    echo "Example:"
    echo "  $0 -g gateway-ns -u application-ns"
    exit 1
}

# Initialize Variables
GATEWAY_NAMESPACE=""
USER_NAMESPACE=""

# Parse Command Line Arguments
while getopts "g:u:h" opt; do
    case $opt in
        g)
            GATEWAY_NAMESPACE="$OPTARG"
            ;;
        u)
            USER_NAMESPACE="$OPTARG"
            ;;
        h)
            show_usage
            ;;
        \?)
            log_error "Invalid option: -$OPTARG"
            show_usage
            ;;
        :)
            log_error "Option -$OPTARG requires an argument"
            show_usage
            ;;
    esac
done

# Check Arguments
if [ -z "$GATEWAY_NAMESPACE" ] || [ -z "$USER_NAMESPACE" ]; then
    log_error "Missing required arguments!"
    show_usage
fi

log_info "Gateway Namespace: ${GATEWAY_NAMESPACE}"
log_info "User Namespace: ${USER_NAMESPACE}"

#==============================================================================
# 1. Cluster Level Check
#==============================================================================
print_section "1. Cluster Level - GatewayClass Check"

log_info "Checking GatewayClass resources..."
if kubectl get gatewayclass &>/dev/null; then
    kubectl get gatewayclass
    log_success "GatewayClass check complete"
else
    log_error "GatewayClass resource not found, please confirm Gateway API is enabled"
    exit 1
fi

# Check Gateway API CRDs
log_info "Checking Gateway API CRDs..."
REQUIRED_CRDS=("gateways.gateway.networking.k8s.io" "httproutes.gateway.networking.k8s.io" "gatewayclasses.gateway.networking.k8s.io")
for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        log_success "CRD $crd is installed"
    else
        log_error "CRD $crd is NOT installed"
    fi
done

#==============================================================================
# 2. Gateway Namespace Check
#==============================================================================
print_section "2. Gateway Namespace - ${GATEWAY_NAMESPACE}"

# Check if Namespace Exists
if ! kubectl get namespace "$GATEWAY_NAMESPACE" &>/dev/null; then
    log_error "Namespace ${GATEWAY_NAMESPACE} does not exist"
    exit 1
fi

# 2.1 Check Gateway IP Assignment
log_info "Checking Gateway IP assignment..."
GATEWAYS=$(kubectl get gateway -n "$GATEWAY_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

if [ -z "$GATEWAYS" ]; then
    log_warning "No Gateway resources found"
else
    for gw in $GATEWAYS; do
        echo ""
        log_info "Gateway: $gw"
        
        # Get Gateway Status
        kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o yaml | grep -A 10 "status:"
        
        # Get Assigned IP
        GW_IP=$(kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
        if [ -n "$GW_IP" ]; then
            log_success "Gateway IP: $GW_IP"
        else
            log_warning "Gateway IP not yet assigned"
        fi
    done
fi

# 2.2 Print HealthCheckPolicy Information
echo ""
log_info "Checking HealthCheckPolicy..."
if kubectl get healthcheckpolicy -n "$GATEWAY_NAMESPACE" &>/dev/null; then
    kubectl get healthcheckpolicy -n "$GATEWAY_NAMESPACE" -o wide
    
    # Detailed Info
    HCP_LIST=$(kubectl get healthcheckpolicy -n "$GATEWAY_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    for hcp in $HCP_LIST; do
        echo ""
        log_info "HealthCheckPolicy Details: $hcp"
        kubectl get healthcheckpolicy "$hcp" -n "$GATEWAY_NAMESPACE" -o yaml
    done
else
    log_warning "No HealthCheckPolicy resources found"
fi

# 2.3 Print NetworkPolicy
echo ""
log_info "Checking NetworkPolicy..."
if kubectl get networkpolicy -n "$GATEWAY_NAMESPACE" &>/dev/null; then
    kubectl get networkpolicy -n "$GATEWAY_NAMESPACE" -o wide
    
    # Detailed Info
    NP_LIST=$(kubectl get networkpolicy -n "$GATEWAY_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    for np in $NP_LIST; do
        echo ""
        log_info "NetworkPolicy Details: $np"
        kubectl get networkpolicy "$np" -n "$GATEWAY_NAMESPACE" -o yaml
    done
else
    log_warning "No NetworkPolicy resources found"
fi

# 2.4 Get Gateway Resource Info and Certificates
echo ""
log_info "Checking Gateway resources and certificate information..."

for gw in $GATEWAYS; do
    echo ""
    log_info "=== Gateway: $gw ==="
    
    # Get Gateway Details
    kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o yaml
    
    # Extract Hostname
    HOSTNAMES=$(kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.spec.listeners[*].hostname}')
    if [ -n "$HOSTNAMES" ]; then
        log_success "Gateway Hostnames: $HOSTNAMES"
    fi
    
    # Check TLS Certificates
    # Maybe need manual check the tls certificate 
    log_info "Checking TLS Certificates..."
    LISTENERS=$(kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o jsonpath='{range .spec.listeners[*]}{.name}{"|"}{.tls.certificateRefs[0].name}{"\n"}{end}')
    
    while IFS='|' read -r listener_name secret_name; do
        if [ -n "$secret_name" ]; then
            log_info "Listener: $listener_name, Secret: $secret_name"
            
            # Get Certificate Subject and Expiry
            CERT_DATA=$(kubectl get secret "$secret_name" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d)
            
            if [ -n "$CERT_DATA" ]; then
                echo "$CERT_DATA" | openssl x509 -noout -subject -enddate
                log_success "Certificate information extracted"
            else
                log_warning "Unable to retrieve certificate data: $secret_name"
            fi
        fi
    done <<< "$LISTENERS"
done

#==============================================================================
# 3. User Namespace Check
#==============================================================================
print_section "3. User Namespace - ${USER_NAMESPACE}"

# Check if Namespace Exists
if ! kubectl get namespace "$USER_NAMESPACE" &>/dev/null; then
    log_error "Namespace ${USER_NAMESPACE} does not exist"
    exit 1
fi

# 3.1 Verify HTTPRoute Binding
log_info "Checking HTTPRoute resources..."
HTTPROUTES=$(kubectl get httproute -n "$USER_NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

if [ -z "$HTTPROUTES" ]; then
    log_warning "No HTTPRoute resources found"
else
    kubectl get httproute -n "$USER_NAMESPACE" -o wide
    
    # 3.2 Extract HTTPRoute Info and Generate URL
    echo ""
    log_info "HTTPRoute details and test URLs..."
    
    for route in $HTTPROUTES; do
        echo ""
        log_info "=== HTTPRoute: $route ==="
        
        # Get Full YAML
        kubectl get httproute "$route" -n "$USER_NAMESPACE" -o yaml
        
        # Extract Key Info
        HOSTNAMES=$(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath='{.spec.hostnames[*]}')
        
        # Extract parentRefs (Gateway Reference)
        PARENT_REFS=$(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath='{.spec.parentRefs[*].name}')
        log_info "Bound Gateway: $PARENT_REFS"
        
        # Iterate through hostnames
        for hostname in $HOSTNAMES; do
            # Get rules count
            RULES_COUNT=$(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath='{.spec.rules}' | jq '. | length')
            
            for ((i=0; i<RULES_COUNT; i++)); do
                # Get path
                PATH_VALUE=$(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath="{.spec.rules[$i].matches[0].path.value}" 2>/dev/null)
                if [ -z "$PATH_VALUE" ]; then
                    PATH_VALUE="/"
                fi
                
                # Get backend service port
                BACKEND_PORT=$(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath="{.spec.rules[$i].backendRefs[0].port}" 2>/dev/null)
                
                # Default to 443 (HTTPS)
                if [ -z "$BACKEND_PORT" ]; then
                    BACKEND_PORT=443
                fi
                
                # Generate Test URL
                TEST_URL="https://${hostname}:${BACKEND_PORT}${PATH_VALUE}"
                
                echo ""
                log_success "Test URL: $TEST_URL"
                echo "  Hostname: $hostname"
                echo "  Port: $BACKEND_PORT"
                echo "  Path: $PATH_VALUE"
                
                # Optional: Connection Test
                log_info "Executing connection test (Optional)..."
                if command -v curl &>/dev/null; then
                    echo "curl -k -I \"$TEST_URL\""
                else
                    log_warning "curl is not installed, skipping connection test"
                fi
            done
        done
    done
fi

#==============================================================================
# 4. Summary Report
#==============================================================================
print_section "Verification Complete"

log_success "GKE Internal Gateway verification script completed"
echo ""
echo "Verification Scope:"
echo "  - Cluster Level: GatewayClass, CRDs"
echo "  - Gateway Namespace (${GATEWAY_NAMESPACE}): Gateway, HealthCheckPolicy, NetworkPolicy, TLS Certificates"
echo "  - User Namespace (${USER_NAMESPACE}): HTTPRoute, Bindings, Test URLs"
echo ""
log_info "Please review the output above to confirm configuration correctness"