# Shell Scripts Collection

Generated on: 2025-12-08 09:29:37
Directory: /Users/lex/git/knowledge/gateway/no-gateway

## `verify-all.sh`

```bash
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
print_subsection "HealthCheckPolicy Resources at ${GATEWAY_NAMESPACE}"

if kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    HCP_COUNT=$(kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo 0)
    log_success "Found ${HCP_COUNT} HealthCheckPolicy resource(s)"
    
    if [ "$VERBOSE" -eq 1 ]; then
        kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" -o wide
    else
        kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null | awk '{print "  - " $1}' || true
    fi
else
    log_warn "No HealthCheckPolicy resources found at ${GATEWAY_NAMESPACE}"
fi

print_subsection "HealthCheckPolicy Resources at ${USER_NAMESPACE}"

if kubectl get healthcheckpolicy -n "${USER_NAMESPACE}" &>/dev/null; then
    HCP_COUNT=$(kubectl get healthcheckpolicy -n "${USER_NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo 0)
    log_success "Found ${HCP_COUNT} HealthCheckPolicy resource(s)"
    
    if [ "$VERBOSE" -eq 1 ]; then
        kubectl get healthcheckpolicy -n "${USER_NAMESPACE}" -o wide
    else
        kubectl get healthcheckpolicy -n "${USER_NAMESPACE}" --no-headers 2>/dev/null | awk '{print "  - " $1}' || true
    fi
else
    log_warn "No HealthCheckPolicy resources found at ${USER_NAMESPACE}"
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

```

## `verify-gke-gateway-chatgpt.sh`

```bash
#!/usr/bin/env bash
#==============================================================================
# Enhanced: GKE Internal Gateway Verification Script
# Purpose: Verify GKE Gateway API configuration and resource status (robust)
# Author: Infrastructure Team (enhanced)
# Version: 2.0
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Globals
GATEWAY_NAMESPACE=""
USER_NAMESPACE=""
VERBOSE=0
DEPENDENCIES=(kubectl openssl)
HAS_JQ=0
HAS_CURL=0

# Stats
ERRORS=0
WARNINGS=0

# Logging
log() { printf "%b\n" "$1"; }
log_info()    { log "${BLUE}[INFO]${NC} $1"; }
log_success() { log "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { WARNINGS=$((WARNINGS+1)); log "${YELLOW}[WARN]${NC} $1"; }
log_error()   { ERRORS=$((ERRORS+1)); log "${RED}[ERROR]${NC} $1"; }

print_section() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
}

show_usage() {
    cat <<EOF
Usage: $0 -g <gateway-namespace> -u <user-namespace> [-v]
Options:
  -g <gateway-namespace>   Gateway Namespace (required)
  -u <user-namespace>      User Namespace (required)
  -v                       Verbose (optional)
  -h                       Show help
Example:
  $0 -g gateway-ns -u application-ns
EOF
    exit 1
}

# ---- parse args
while getopts "g:u:vh" opt; do
    case "$opt" in
        g) GATEWAY_NAMESPACE="$OPTARG" ;;
        u) USER_NAMESPACE="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) show_usage ;;
        *) show_usage ;;
    esac
done

if [ -z "${GATEWAY_NAMESPACE}" ] || [ -z "${USER_NAMESPACE}" ]; then
    log_error "Missing required arguments"
    show_usage
fi

# ---- dependency check
for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found in PATH. Please install it before running."
        exit 2
    fi
done

if command -v jq &>/dev/null; then
    HAS_JQ=1
else
    log_warn "jq not found: JSON parsing will be less precise. Install jq for better results."
fi

if command -v curl &>/dev/null; then
    HAS_CURL=1
fi

# ---- helper safe kubectl wrapper: run but don't exit script on failure (unless fatal flag)
run_kubectl() {
    # usage: run_kubectl <fatal:0|1> -- kubectl args...
    local fatal="$1"; shift
    # pass through the rest to kubectl
    if kubectl "$@" 2>/dev/null; then
        return 0
    else
        if [ "$fatal" -eq 1 ]; then
            log_error "kubectl failed: kubectl $*"
            exit 3
        else
            log_warn "kubectl returned non-zero: kubectl $*"
            return 1
        fi
    fi
}

# ---- pre-flight: check kube access
print_section "Pre-flight checks"
log_info "Checking kubectl connectivity and current context..."
if ! kubectl version --client &>/dev/null; then
    log_error "kubectl client not available"
    exit 2
fi

if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach cluster. Please verify kubeconfig and network access."
    exit 2
fi
log_success "kubectl is available and cluster is reachable"

log_info "Gateway Namespace: ${GATEWAY_NAMESPACE}"
log_info "User Namespace   : ${USER_NAMESPACE}"

#==============================================================================
# 1. Cluster Level Check
#==============================================================================
print_section "1. Cluster Level - GatewayClass & CRDs"

# GatewayClass
if run_kubectl 0 get gatewayclass -o name; then
    run_kubectl 0 get gatewayclass -o wide
    log_success "GatewayClass resources present (at least one)"
else
    log_error "No GatewayClass found. Ensure Gateway API is installed and CRDs are present."
fi

# CRD checks
REQUIRED_CRDS=(
  "gateways.gateway.networking.k8s.io"
  "httproutes.gateway.networking.k8s.io"
  "gatewayclasses.gateway.networking.k8s.io"
  "healthcheckpolicies.gateway.networking.k8s.io"
)
for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        log_success "CRD installed: $crd"
    else
        log_warn "CRD missing: $crd"
    fi
done

#==============================================================================
# 2. Gateway Namespace Check
#==============================================================================
print_section "2. Gateway Namespace - ${GATEWAY_NAMESPACE}"

# Namespace exists?
if ! kubectl get namespace "${GATEWAY_NAMESPACE}" &>/dev/null; then
    log_error "Namespace ${GATEWAY_NAMESPACE} does not exist or you lack permission"
    exit 4
fi
log_success "Namespace ${GATEWAY_NAMESPACE} exists"

# List Gateways in namespace
GATEWAYS_JSON=""
if kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o json &>/dev/null; then
    GATEWAYS_JSON=$(kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o json)
else
    log_warn "No Gateway resources found in ${GATEWAY_NAMESPACE}"
fi

if [ -n "${GATEWAYS_JSON}" ]; then
    if [ "${HAS_JQ}" -eq 1 ]; then
        GATEWAY_NAMES=($(jq -r '.items[].metadata.name' <<<"$GATEWAYS_JSON" 2>/dev/null || true))
    else
        # fallback: try jsonpath (may be brittle)
        GATEWAY_NAMES=($(kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    fi

    if [ ${#GATEWAY_NAMES[@]} -eq 0 ]; then
        log_warn "No Gateway objects found (after parsing)"
    else
        for gw in "${GATEWAY_NAMES[@]}"; do
            echo ""
            log_info "Gateway: ${gw}"

            # print status (jsonpath if possible)
            if kubectl get gateway "${gw}" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.status}' &>/dev/null; then
                kubectl get gateway "${gw}" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.status}' || true
                echo ""
            else
                log_warn "No status available for Gateway ${gw}"
            fi

            # try to get assigned IP(s)
            if HAS_JQ=1; then :; fi # noop so shellcheck doesn't complain

            # use jq when available
            if command -v jq &>/dev/null; then
                GW_IPS=($(jq -r --arg name "$gw" '.items[] | select(.metadata.name==$name) | .status.addresses[]?.value' <<<"$GATEWAYS_JSON" 2>/dev/null || true))
            else
                # fallback: try jsonpath for first address
                GW_IP=$(kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
                if [ -n "$GW_IP" ]; then
                    GW_IPS=("$GW_IP")
                else
                    GW_IPS=()
                fi
            fi

            if [ ${#GW_IPS[@]} -gt 0 ]; then
                for ip in "${GW_IPS[@]}"; do
                    log_success "Assigned Address: $ip"
                done
            else
                log_warn "No assigned addresses found for Gateway ${gw}"
            fi
        done
    fi
fi

# 2.2 HealthCheckPolicy
echo ""
log_info "Checking HealthCheckPolicy in ${GATEWAY_NAMESPACE}..."
if kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" -o wide || true
    HCP_NAMES=($(kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    for hcp in "${HCP_NAMES[@]}"; do
        echo ""
        log_info "HealthCheckPolicy: $hcp"
        kubectl get healthcheckpolicy "${hcp}" -n "${GATEWAY_NAMESPACE}" -o yaml || true
    done
else
    log_warn "No HealthCheckPolicy resources in ${GATEWAY_NAMESPACE}"
fi

# 2.3 NetworkPolicy
echo ""
log_info "Checking NetworkPolicy in ${GATEWAY_NAMESPACE}..."
if kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" -o wide || true
    NP_NAMES=($(kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    for np in "${NP_NAMES[@]}"; do
        echo ""
        log_info "NetworkPolicy: $np"
        kubectl get networkpolicy "$np" -n "${GATEWAY_NAMESPACE}" -o yaml || true
    done
else
    log_warn "No NetworkPolicy resources in ${GATEWAY_NAMESPACE}"
fi

# 2.4 Gateway TLS / Certificate Checks
echo ""
log_info "Checking Gateway TLS listeners and referenced secrets..."

if [ -n "${GATEWAYS_JSON}" ]; then
    for gw in "${GATEWAY_NAMES[@]}"; do
        echo ""
        log_info "=== Gateway: ${gw} ==="
        GW_JSON=$(kubectl get gateway "$gw" -n "${GATEWAY_NAMESPACE}" -o json 2>/dev/null || true)

        # parse listeners and certificateRefs
        if command -v jq &>/dev/null; then
            LISTENERS_JSON=$(jq -r --arg name "$gw" '.items[] | select(.metadata.name==$name) | .spec.listeners' <<<"$GATEWAYS_JSON" 2>/dev/null || true)
            if [ -z "$LISTENERS_JSON" ] || [ "$LISTENERS_JSON" = "null" ]; then
                log_warn "No listeners defined in Gateway ${gw}"
                continue
            fi

            # for each listener, get listener.name, hostname, port and tls.certificateRefs[]
            echo "$LISTENERS_JSON" | jq -c '.[]' | while read -r listener; do
                listener_name=$(jq -r '.name // empty' <<<"$listener")
                listener_hostname=$(jq -r '.hostname // empty' <<<"$listener")
                listener_port=$(jq -r '.port // empty' <<<"$listener")
                cert_ref_names=($(jq -r '.tls.certificateRefs[]?.name // empty' <<<"$listener" | sed '/^$/d'))

                log_info "Listener: ${listener_name:-<unnamed>} hostname:${listener_hostname:-<none>} port:${listener_port:-<none>}"
                if [ ${#cert_ref_names[@]} -eq 0 ]; then
                    log_warn "No certificateRefs in listener ${listener_name:-<unnamed>}"
                else
                    for secret_name in "${cert_ref_names[@]}"; do
                        log_info "Referenced Secret: $secret_name (ns: ${GATEWAY_NAMESPACE})"
                        # get secret, check type
                        if kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
                            secret_type=$(kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.type}' 2>/dev/null || true)
                            if [ "$secret_type" != "kubernetes.io/tls" ]; then
                                log_warn "Secret $secret_name is type '$secret_type' (expected kubernetes.io/tls)"
                            fi

                            crt_b64=$(kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
                            if [ -n "${crt_b64}" ]; then
                                # decode into temp file
                                tmpcrt=$(mktemp)
                                printf '%s' "$crt_b64" | base64 -d > "$tmpcrt" 2>/dev/null || true
                                if [ -s "$tmpcrt" ]; then
                                    log_info "Certificate summary for $secret_name:"
                                    openssl x509 -in "$tmpcrt" -noout -subject -issuer -startdate -enddate \
                                        || log_warn "openssl failed to parse certificate for $secret_name"
                                    # show SAN if possible
                                    openssl x509 -in "$tmpcrt" -noout -text | sed -n '/Subject Alternative Name:/, /X509v3/{/DNS/p;}' || true
                                    rm -f "$tmpcrt"
                                else
                                    log_warn "Secret $secret_name contains no tls.crt"
                                fi
                            else
                                log_warn "Secret $secret_name missing tls.crt data"
                            fi
                        else
                            log_warn "Referenced secret $secret_name does not exist in ${GATEWAY_NAMESPACE}"
                        fi
                    done
                fi
            done
        else
            # no jq: fallback simple output
            log_warn "Skipping deep listener parsing (jq not installed). Showing raw Gateway YAML:"
            kubectl get gateway "$gw" -n "${GATEWAY_NAMESPACE}" -o yaml || true
        fi
    done
fi

#==============================================================================
# 3. User Namespace Check - HTTPRoute binding & test URL generation
#==============================================================================
print_section "3. User Namespace - ${USER_NAMESPACE}"

if ! kubectl get namespace "${USER_NAMESPACE}" &>/dev/null; then
    log_error "Namespace ${USER_NAMESPACE} does not exist or you lack permission"
    exit 5
fi
log_success "Namespace ${USER_NAMESPACE} exists"

# get HTTPRoute objects
HTR_JSON=""
if kubectl get httproute -n "${USER_NAMESPACE}" -o json &>/dev/null; then
    HTR_JSON=$(kubectl get httproute -n "${USER_NAMESPACE}" -o json)
else
    log_warn "No HTTPRoute resources found in ${USER_NAMESPACE}"
fi

if [ -n "$HTR_JSON" ]; then
    if command -v jq &>/dev/null; then
        ROUTE_NAMES=($(jq -r '.items[].metadata.name' <<<"$HTR_JSON" || true))
    else
        ROUTE_NAMES=($(kubectl get httproute -n "$USER_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    fi

    for route in "${ROUTE_NAMES[@]}"; do
        echo ""
        log_info "=== HTTPRoute: ${route} ==="
        kubectl get httproute "${route}" -n "${USER_NAMESPACE}" -o yaml || true

        # extract hostnames and parentRefs
        if command -v jq &>/dev/null; then
            HOSTNAMES=($(jq -r --arg name "$route" '.items[] | select(.metadata.name==$name) | .spec.hostnames[]? // empty' <<<"$HTR_JSON" || true))
            # parentRefs can be many; extract names and namespace (if provided)
            # parentRefs usually: name + namespace(optional)
            PARENT_REFS=$(jq -c --arg name "$route" '.items[] | select(.metadata.name==$name) | .spec.parentRefs[]? // empty' <<<"$HTR_JSON" || true)
        else
            HOSTNAMES=($(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null || true))
            PARENT_REFS="" # skip deep parsing without jq
        fi

        # for each hostname, try to determine listener port from referenced Gateway(s)
        if [ ${#HOSTNAMES[@]} -eq 0 ]; then
            HOSTNAMES=("<none>")
        fi

        for hostname in "${HOSTNAMES[@]}"; do
            # default port
            LISTENER_PORT=""
            # attempt to parse parentRefs and get gateway listener port that matches hostname
            if command -v jq &>/dev/null && [ -n "$PARENT_REFS" ]; then
                # iterate parentRefs
                echo "$PARENT_REFS" | jq -c '.' | while read -r parent; do
                    parent_name=$(jq -r '.name // empty' <<<"$parent")
                    parent_ns=$(jq -r '.namespace // empty' <<<"$parent")
                    [ -z "$parent_ns" ] && parent_ns="${GATEWAY_NAMESPACE}" # fallback to gateway ns assumption

                    # get gateway json
                    gwjson=$(kubectl get gateway "$parent_name" -n "$parent_ns" -o json 2>/dev/null || true)
                    if [ -z "$gwjson" ]; then
                        log_warn "Parent Gateway ${parent_name} not found in namespace ${parent_ns}"
                        continue
                    fi

                    # find listener that matches hostname or has no hostname (hostless)
                    listener_port=$(jq -r --arg host "$hostname" \
                        '.spec.listeners[]? | select((.hostname==($host)) or (.hostname==null) or (.hostname=="")) | .port // empty' \
                        <<<"$gwjson" 2>/dev/null || true)

                    if [ -n "$listener_port" ]; then
                        LISTENER_PORT="$listener_port"
                        break
                    fi
                done
            fi

            # fallback if not found
            if [ -z "$LISTENER_PORT" ]; then
                # Use 8443 by default for HTTPS; note: this is not guaranteed correct if listener uses non-standard port.
                LISTENER_PORT=8443
                log_warn "Could not determine listener port for hostname ${hostname}; defaulting to ${LISTENER_PORT}. Validate Gateway listeners for accurate port."
            fi

            # Attempt to extract path from first match rule (best-effort)
            PATH_VALUE="/"
            if command -v jq &>/dev/null; then
                PATH_VALUE=$(jq -r --arg r "$route" --arg host "$hostname" \
                  '.items[] | select(.metadata.name==$r) | .spec.rules[0].matches[0].path.value // "/"' \
                  <<<"$HTR_JSON" 2>/dev/null || echo "/")
            fi

            TEST_URL="https://${hostname}:${LISTENER_PORT}${PATH_VALUE}"
            log_success "Test URL: $TEST_URL"
            log_info "  Hostname: ${hostname}"
            log_info "  Listener Port (best-effort): ${LISTENER_PORT}"
            log_info "  Path (best-effort): ${PATH_VALUE}"

            # Optional live test
            if [ "${HAS_CURL}" -eq 1 ]; then
                # use -k to ignore cert errors (since we're only testing connectivity). Do not do this for real validation.
                log_info "Performing HEAD request to ${TEST_URL} (insecure)"
                if curl -k -I --max-time 10 "${TEST_URL}" &>/dev/null; then
                    log_success "Connectivity OK for ${TEST_URL}"
                else
                    log_warn "Connectivity test failed for ${TEST_URL} (this may be due to network/firewall/Cloud LB config)"
                fi
            else
                log_warn "curl not installed; skipping live HTTP connectivity test"
            fi
        done
    done
fi

#==============================================================================
# 4. Summary Report
#==============================================================================
print_section "Verification Complete"
log_info "Errors: ${ERRORS}, Warnings: ${WARNINGS}"
echo ""
cat <<EOF
Verification Scope:
  - Cluster Level: GatewayClass, Gateway API CRDs
  - Gateway Namespace (${GATEWAY_NAMESPACE}): Gateway, listeners, HealthCheckPolicy, NetworkPolicy, TLS secrets
  - User Namespace (${USER_NAMESPACE}): HTTPRoute bindings, hostnames, test URLs
EOF

if [ "${ERRORS}" -gt 0 ]; then
    log_error "Completed with errors. Please inspect output above and fix the issues."
    exit 6
else
    log_success "Completed successfully (warnings may exist)."
    exit 0
fi
```

## `verify-gke-gateway-claude.sh`

```bash
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
```

## `verify-gke-gateway.sh`

```bash
#!/bin/bash

# verify-gke-gateway.sh
#
# Verification script for GKE Gateway Configuration (User Request)
#
# Usage: ./verify-gke-gateway.sh -g <gateway-namespace> -u <user-namespace>

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

G_NS=""
U_NS=""

while getopts "g:u:h" opt; do
  case $opt in
    g) G_NS="$OPTARG" ;;
    u) U_NS="$OPTARG" ;;
    h)
      echo "Usage: $0 -g <gateway-namespace> -u <user-namespace>"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ -z "$G_NS" ] || [ -z "$U_NS" ]; then
    echo "Usage: $0 -g <gateway-namespace> -u <user-namespace>"
    exit 1
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_succ() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "=================================================="
echo "      GKE Gateway Verification Script"
echo "=================================================="
echo "Gateway Namespace: $G_NS"
echo "User Namespace:    $U_NS"
echo "=================================================="

# --- Cluster Level Check ---
log_info ">>> Checking Cluster Level Resources..."

if kubectl get gatewayclass > /dev/null 2>&1; then
    log_succ "Gateway API is enabled (GatewayClass resource found)."
    echo "    Available GatewayClasses:"
    kubectl get gatewayclass --no-headers | awk '{print "    - " $1 " (Controller: " $2 ")"}'
else
    log_err "Gateway API NOT enabled (GatewayClass resource not found)."
    exit 1
fi

echo ""

# --- Gateway Namespace Check ---
log_info ">>> Checking Gateway Namespace: $G_NS"

# 1. Gateway IP Assignment
GW_NAME=$(kubectl get gateway -n "$G_NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$GW_NAME" ]; then
    log_succ "Found Gateway: $GW_NAME"
    
    # Check IP
    GW_ADDR=$(kubectl get gateway "$GW_NAME" -n "$G_NS" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -n "$GW_ADDR" ]; then
        log_succ "Gateway IP Assigned: $GW_ADDR"
    else
        log_warn "Gateway IP not found (status.addresses is empty)"
    fi
    
    # Get Hostname (from listener)
    GW_HOST=$(kubectl get gateway "$GW_NAME" -n "$G_NS" -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null || echo "")
    log_info "Gateway Listener Hostname: $GW_HOST"

    # Get Cert Subject
    CERT_SECRET=$(kubectl get gateway "$GW_NAME" -n "$G_NS" -o jsonpath='{.spec.listeners[0].tls.certificateRefs[0].name}' 2>/dev/null || echo "")
    
    if [ -n "$CERT_SECRET" ]; then
        log_info "TLS Secret Ref: $CERT_SECRET"
        if kubectl get secret "$CERT_SECRET" -n "$G_NS" >/dev/null 2>&1; then
             CERT_ENDDATE=$(kubectl get secret "$CERT_SECRET" -n "$G_NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
             CERT_SUBJ=$(kubectl get secret "$CERT_SECRET" -n "$G_NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
             log_succ "Cert Subject: $CERT_SUBJ"
             log_info "Cert Expiry:  $CERT_ENDDATE"
        else
             log_err "Secret '$CERT_SECRET' not found in namespace '$G_NS'"
        fi
    else
        log_warn "No TLS certificate ref found in first listener"
    fi

else
    log_err "No Gateway resource found in namespace '$G_NS'"
fi

# 2. HealthCheckPolicy
log_info "Checking HealthCheckPolicy..."
HC_POLICIES=$(kubectl get healthcheckpolicy -n "$G_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HC_POLICIES" ]; then
    log_succ "Found HealthCheckPolicies: $HC_POLICIES"
    kubectl get healthcheckpolicy -n "$G_NS"
else
    log_warn "No HealthCheckPolicy found in '$G_NS'"
fi

# 3. NetworkPolicy
log_info "Checking NetworkPolicy..."
NET_POLICIES=$(kubectl get networkpolicy -n "$G_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NET_POLICIES" ]; then
    log_succ "Found NetworkPolicies: $NET_POLICIES"
    kubectl get networkpolicy -n "$G_NS"
else
    log_warn "No NetworkPolicy found in '$G_NS'"
fi

echo ""

# --- User Namespace Check ---
log_info ">>> Checking User Namespace: $U_NS"

# 1. Verify HTTPRoute Binding
http_routes=$(kubectl get httproute -n "$U_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "$http_routes" ]; then
    log_err "No HTTPRoute found in namespace '$U_NS'"
else
    log_succ "Found HTTPRoutes: $http_routes"
    
    for route in $http_routes; do
        echo "--------------------------------------------------"
        echo "Analyzing Route: $route"
        
        # 2. Get Hostname, Path, Port
        # Note: A route can have multiple hostnames and rules. We take the first for simplicity of "URL generation"
        
        # Hostname
        R_HOST=$(kubectl get httproute "$route" -n "$U_NS" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null || echo "")
        
        # Rule 1 Match Path
        # Assumes PathPrefix match
        R_PATH=$(kubectl get httproute "$route" -n "$U_NS" -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null || echo "/")
        
        # Backend Ref Port (Standard GKE Gateway usually terminates TLS and fwds to service)
        # But for constructing the URL, we need the *Listener* port from the Gateway (usually 443 for HTTPS)
        # The user request asks for "hostname path' value and port" and "https://$hostname:$port/$pathvalue"
        # Assuming port 443 for HTTPS if proper Gateway is used.
        
        # Let's try to find parentRef port if specified, otherwise default to 443
        PARENT_PORT=$(kubectl get httproute "$route" -n "$U_NS" -o jsonpath='{.spec.parentRefs[0].port}' 2>/dev/null || echo "443")
        
        # If hostname is empty in HTTPRoute, fall back to Gateway hostname
        if [ -z "$R_HOST" ]; then
             R_HOST="$GW_HOST"
             echo "    (Using Gateway Hostname)"
        fi
        
        if [ -z "$R_HOST" ]; then
             R_HOST="<unknown-host>"
        fi
        
        log_info "Hostname: $R_HOST"
        log_info "Path:     $R_PATH"
        log_info "Port:     $PARENT_PORT"
        
        # 3. Construct URL
        URL="https://${R_HOST}:${PARENT_PORT}${R_PATH}"
        log_succ "Generated URL: $URL"
        
    done
fi

echo ""
echo "=================================================="
echo "Verification Complete"
echo "=================================================="

```

