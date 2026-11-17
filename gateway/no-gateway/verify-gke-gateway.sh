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
