#!/usr/bin/env bash
#==============================================================================
# GKE Gateway Comprehensive Verification Script
# Purpose: Verify GKE Gateway API configuration and resource status
# Author: Infrastructure Team
# Version: 3.0 (Combined best practices from multiple implementations)
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global Variables
GATEWAY_NAMESPACE=""
USER_NAMESPACE=""
VERBOSE=0
DEPENDENCIES=(kubectl openssl)
HAS_JQ=0
HAS_CURL=0

# Statistics Tracking
ERRORS=0
WARNINGS=0
CHECKS_PASSED=0

# Logging Functions
log() { printf "%b\n" "$1"; }
log_info()    { log "${BLUE}[INFO]${NC} $1"; }
log_success() { CHECKS_PASSED=$((CHECKS_PASSED+1)); log "${GREEN}[✓ PASS]${NC} $1"; }
log_warn()    { WARNINGS=$((WARNINGS+1)); log "${YELLOW}[⚠ WARN]${NC} $1"; }
log_error()   { ERRORS=$((ERRORS+1)); log "${RED}[✖ FAIL]${NC} $1"; }

print_section() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
}

print_subsection() {
    echo ""
    echo ">>> $1"
    echo ""
}

show_usage() {
    cat <<EOF
Usage: $0 -g <gateway-namespace> -u <user-namespace> [-v]

Options:
  -g <gateway-namespace>   Gateway Namespace (required)
  -u <user-namespace>      User Namespace (required)
  -v                       Verbose output (optional)
  -h                       Show this help message

Example:
  $0 -g gateway-system -u production-apps

Description:
  This script performs comprehensive verification of GKE Gateway API resources:
  - Cluster level: GatewayClass and CRD validation
  - Gateway namespace: IP assignment, policies, certificates
  - User namespace: HTTPRoute bindings and URL generation

EOF
    exit 0
}

# Parse Command Line Arguments
while getopts "g:u:vh" opt; do
    case "$opt" in
        g) GATEWAY_NAMESPACE="$OPTARG" ;;
        u) USER_NAMESPACE="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) show_usage ;;
        *) show_usage ;;
    esac
done

# Validate Required Arguments
if [ -z "${GATEWAY_NAMESPACE}" ] || [ -z "${USER_NAMESPACE}" ]; then
    log_error "Missing required arguments"
    show_usage
fi

#==============================================================================
# Dependency Checks
#==============================================================================
for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found. Please install it."
        exit 2
    fi
done

if command -v jq &>/dev/null; then
    HAS_JQ=1
    [ "$VERBOSE" -eq 1 ] && log_info "jq detected: Enhanced JSON parsing enabled"
else
    log_warn "jq not found: JSON parsing will use fallback methods"
fi

if command -v curl &>/dev/null; then
    HAS_CURL=1
    [ "$VERBOSE" -eq 1 ] && log_info "curl detected: HTTP connectivity tests enabled"
fi

#==============================================================================
# Pre-flight Checks
#==============================================================================
print_section "Pre-flight Checks"

log_info "Verifying kubectl connectivity..."
if ! kubectl version --client &>/dev/null; then
    log_error "kubectl client not available"
    exit 2
fi

if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach cluster. Verify kubeconfig and network access."
    exit 2
fi
log_success "kubectl connectivity verified"

# Display context info
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
log_info "Current context: ${CURRENT_CONTEXT}"
log_info "Gateway Namespace: ${GATEWAY_NAMESPACE}"
log_info "User Namespace: ${USER_NAMESPACE}"

#==============================================================================
# 1. Cluster Level Verification
#==============================================================================
print_section "1. Cluster Level - GatewayClass & CRDs"

# Check GatewayClass
print_subsection "GatewayClass Resources"
if kubectl get gatewayclass &>/dev/null; then
    kubectl get gatewayclass -o wide
    log_success "GatewayClass resources found"
else
    log_error "No GatewayClass found. Gateway API may not be installed."
fi

# Verify Required CRDs
print_subsection "Gateway API CRDs"
REQUIRED_CRDS=(
    "gateways.gateway.networking.k8s.io"
    "httproutes.gateway.networking.k8s.io"
    "gatewayclasses.gateway.networking.k8s.io"
    "healthcheckpolicies.gateway.networking.k8s.io"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        log_success "CRD present: $crd"
    else
        log_warn "CRD missing: $crd"
    fi
done

#==============================================================================
# 2. Gateway Namespace Verification
#==============================================================================
print_section "2. Gateway Namespace - ${GATEWAY_NAMESPACE}"

# Verify namespace exists
if ! kubectl get namespace "${GATEWAY_NAMESPACE}" &>/dev/null; then
    log_error "Namespace ${GATEWAY_NAMESPACE} not found or insufficient permissions"
    exit 4
fi
log_success "Namespace ${GATEWAY_NAMESPACE} exists"

#------------------------------------------------------------------------------
# 2.1 Gateway Resources
#------------------------------------------------------------------------------
print_subsection "Gateway Resources"

GATEWAYS_JSON=""
if kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o json &>/dev/null; then
    GATEWAYS_JSON=$(kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o json)
else
    log_warn "No Gateway resources in ${GATEWAY_NAMESPACE}"
fi

if [ -n "${GATEWAYS_JSON}" ]; then
    # Parse gateway names
    if [ "${HAS_JQ}" -eq 1 ]; then
        mapfile -t GATEWAY_NAMES < <(jq -r '.items[].metadata.name' <<<"$GATEWAYS_JSON" 2>/dev/null || true)
    else
        mapfile -t GATEWAY_NAMES < <(kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' || true)
    fi

    for gw in "${GATEWAY_NAMES[@]}"; do
        [ -z "$gw" ] && continue
        
        echo ""
        log_info "Gateway: ${gw}"

        # Check assigned IPs
        if [ "${HAS_JQ}" -eq 1 ]; then
            mapfile -t GW_IPS < <(jq -r --arg name "$gw" '.items[] | select(.metadata.name==$name) | .status.addresses[]?.value // empty' <<<"$GATEWAYS_JSON" 2>/dev/null || true)
        else
            GW_IP=$(kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
            GW_IPS=("$GW_IP")
        fi

        if [ ${#GW_IPS[@]} -gt 0 ] && [ -n "${GW_IPS[0]}" ]; then
            for ip in "${GW_IPS[@]}"; do
                [ -n "$ip" ] && log_success "  IP Address: $ip"
            done
        else
            log_warn "  No IP addresses assigned yet"
        fi

        # Show Gateway status
        if [ "$VERBOSE" -eq 1 ]; then
            kubectl get gateway "${gw}" -n "${GATEWAY_NAMESPACE}" -o yaml 2>/dev/null || true
        fi
    done
fi

#------------------------------------------------------------------------------
# 2.2 HealthCheckPolicy
#------------------------------------------------------------------------------
print_subsection "HealthCheckPolicy Resources"

if kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    HCP_COUNT=$(kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo 0)
    log_success "Found ${HCP_COUNT} HealthCheckPolicy resource(s)"
    
    if [ "$VERBOSE" -eq 1 ]; then
        kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" -o wide
    else
        kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null | awk '{print "  - " $1}' || true
    fi
else
    log_warn "No HealthCheckPolicy resources found"
fi

#------------------------------------------------------------------------------
# 2.3 NetworkPolicy
#------------------------------------------------------------------------------
print_subsection "NetworkPolicy Resources"

if kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    NP_COUNT=$(kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo 0)
    log_success "Found ${NP_COUNT} NetworkPolicy resource(s)"
    
    if [ "$VERBOSE" -eq 1 ]; then
        kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" -o wide
    else
        kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null | awk '{print "  - " $1}' || true
    fi
else
    log_warn "No NetworkPolicy resources found"
fi

#------------------------------------------------------------------------------
# 2.4 TLS Certificate Validation
#------------------------------------------------------------------------------
print_subsection "TLS Certificate Validation"

if [ -n "${GATEWAYS_JSON}" ] && [ "${HAS_JQ}" -eq 1 ]; then
    for gw in "${GATEWAY_NAMES[@]}"; do
        [ -z "$gw" ] && continue
        
        echo ""
        log_info "Gateway: ${gw}"

        LISTENERS_JSON=$(jq -r --arg name "$gw" '.items[] | select(.metadata.name==$name) | .spec.listeners' <<<"$GATEWAYS_JSON" 2>/dev/null || echo "null")
        
        if [ "$LISTENERS_JSON" = "null" ] || [ -z "$LISTENERS_JSON" ]; then
            log_warn "  No listeners defined"
            continue
        fi

        echo "$LISTENERS_JSON" | jq -c '.[]' | while read -r listener; do
            listener_name=$(jq -r '.name // "unnamed"' <<<"$listener")
            listener_hostname=$(jq -r '.hostname // "none"' <<<"$listener")
            listener_port=$(jq -r '.port // "none"' <<<"$listener")
            
            log_info "  Listener: ${listener_name} (${listener_hostname}:${listener_port})"
            
            # Check for TLS certificates
            mapfile -t cert_refs < <(jq -r '.tls.certificateRefs[]?.name // empty' <<<"$listener")
            
            if [ ${#cert_refs[@]} -eq 0 ]; then
                log_warn "    No TLS certificates configured"
            else
                for secret_name in "${cert_refs[@]}"; do
                    [ -z "$secret_name" ] && continue
                    
                    if kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
                        # Extract and validate certificate
                        crt_b64=$(kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
                        
                        if [ -n "${crt_b64}" ]; then
                            tmpcrt=$(mktemp)
                            printf '%s' "$crt_b64" | base64 -d > "$tmpcrt" 2>/dev/null || true
                            
                            if [ -s "$tmpcrt" ]; then
                                subject=$(openssl x509 -in "$tmpcrt" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "unknown")
                                expiry=$(openssl x509 -in "$tmpcrt" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "unknown")
                                log_success "    Certificate: $secret_name"
                                log_info "      Subject: $subject"
                                log_info "      Expires: $expiry"
                            else
                                log_warn "    Certificate $secret_name is empty or invalid"
                            fi
                            rm -f "$tmpcrt"
                        else
                            log_warn "    Certificate $secret_name has no tls.crt data"
                        fi
                    else
                        log_error "    Certificate secret $secret_name not found"
                    fi
                done
            fi
        done
    done
elif [ -n "${GATEWAYS_JSON}" ]; then
    log_warn "Install jq for detailed TLS certificate validation"
fi

#==============================================================================
# 3. User Namespace Verification
#==============================================================================
print_section "3. User Namespace - ${USER_NAMESPACE}"

# Verify namespace exists
if ! kubectl get namespace "${USER_NAMESPACE}" &>/dev/null; then
    log_error "Namespace ${USER_NAMESPACE} not found or insufficient permissions"
    exit 5
fi
log_success "Namespace ${USER_NAMESPACE} exists"

#------------------------------------------------------------------------------
# 3.1 HTTPRoute Resources and URL Generation
#------------------------------------------------------------------------------
print_subsection "HTTPRoute Resources"

HTR_JSON=""
if kubectl get httproute -n "${USER_NAMESPACE}" -o json &>/dev/null; then
    HTR_JSON=$(kubectl get httproute -n "${USER_NAMESPACE}" -o json)
else
    log_warn "No HTTPRoute resources in ${USER_NAMESPACE}"
fi

if [ -n "$HTR_JSON" ]; then
    # Parse route names
    if [ "${HAS_JQ}" -eq 1 ]; then
        mapfile -t ROUTE_NAMES < <(jq -r '.items[].metadata.name' <<<"$HTR_JSON" 2>/dev/null || true)
    else
        mapfile -t ROUTE_NAMES < <(kubectl get httproute -n "$USER_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' || true)
    fi

    for route in "${ROUTE_NAMES[@]}"; do
        [ -z "$route" ] && continue
        
        echo ""
        log_info "HTTPRoute: ${route}"

        # Extract hostnames
        if [ "${HAS_JQ}" -eq 1 ]; then
            mapfile -t HOSTNAMES < <(jq -r --arg name "$route" '.items[] | select(.metadata.name==$name) | .spec.hostnames[]? // empty' <<<"$HTR_JSON" || true)
        else
            mapfile -t HOSTNAMES < <(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null | tr ' ' '\n' || true)
        fi

        [ ${#HOSTNAMES[@]} -eq 0 ] && HOSTNAMES=("<no-hostname>")

        for hostname in "${HOSTNAMES[@]}"; do
            [ -z "$hostname" ] && continue
            
            # Determine listener port (default to 443 for HTTPS)
            LISTENER_PORT=443
            
            # Extract path (use first match rule)
            if [ "${HAS_JQ}" -eq 1 ]; then
                PATH_VALUE=$(jq -r --arg r "$route" '.items[] | select(.metadata.name==$r) | .spec.rules[0].matches[0].path.value // "/"' <<<"$HTR_JSON" 2>/dev/null || echo "/")
            else
                PATH_VALUE="/"
            fi

            # Generate test URL
            TEST_URL="https://${hostname}:${LISTENER_PORT}${PATH_VALUE}"
            
            log_success "  Test URL: ${TEST_URL}"
            log_info "    Hostname: ${hostname}"
            log_info "    Port: ${LISTENER_PORT}"
            log_info "    Path: ${PATH_VALUE}"

            # Optional connectivity test
            if [ "${HAS_CURL}" -eq 1 ] && [ "$hostname" != "<no-hostname>" ]; then
                if curl -k -I --max-time 5 "${TEST_URL}" &>/dev/null; then
                    log_success "    Connectivity: OK"
                else
                    log_warn "    Connectivity: Failed (may be expected if not publicly routable)"
                fi
            fi
        done

        # Show verbose route details
        if [ "$VERBOSE" -eq 1 ]; then
            kubectl get httproute "${route}" -n "${USER_NAMESPACE}" -o yaml 2>/dev/null || true
        fi
    done
fi

#==============================================================================
# 4. Summary Report
#==============================================================================
print_section "Verification Summary"

echo ""
echo "Statistics:"
echo "  ✓ Checks Passed: ${CHECKS_PASSED}"
echo "  ⚠ Warnings: ${WARNINGS}"
echo "  ✖ Errors: ${ERRORS}"
echo ""
echo "Verification Scope:"
echo "  - Cluster: GatewayClass, CRDs"
echo "  - Gateway NS (${GATEWAY_NAMESPACE}): Gateway, HealthCheckPolicy, NetworkPolicy, TLS"
echo "  - User NS (${USER_NAMESPACE}): HTTPRoute, URLs"
echo ""

if [ "${ERRORS}" -gt 0 ]; then
    log_error "Verification completed with ${ERRORS} error(s). Review output above."
    exit 6
elif [ "${WARNINGS}" -gt 0 ]; then
    log_warn "Verification completed with ${WARNINGS} warning(s). Review recommended."
    exit 0
else
    log_success "All verifications passed successfully!"
    exit 0
fi
