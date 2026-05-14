#!/bin/bash

# verify-dp-summary.sh
#
# A concise summary status check for Kong Data Plane (DP).
# Builds upon verify-dp-status-gemini.sh but focuses on a high-level dashboard view.
#
# Usage: ./verify-dp-summary.sh [-n namespace] [-l label-selector] [-s secret-name]

set +e # Disable exit on error to ensure summary is printed even if some commands fail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="bass-int-kdp"
LABEL_SELECTOR="app=busybox-app"
SECRET_NAME="lex-tls-secret"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:l:s:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    l) LABEL_SELECTOR="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    h)
      echo "Usage: $0 [-n namespace] [-l label-selector] [-s secret-name]"
      echo "  -n: Kubernetes namespace (default: $NAMESPACE)"
      echo "  -l: DP Deployment label selector (default: $LABEL_SELECTOR)"
      echo "  -s: TLS secret name (default: $SECRET_NAME)"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Logging Helpers
log_step() {
    echo -e "${BLUE}>>> $1${NC}"
}
log_info() {
    echo -e "    ${CYAN}•${NC} $1"
}
log_warn() {
    echo -e "    ${YELLOW}⚠${NC} $1"
}
log_err() {
    echo -e "    ${RED}✖${NC} $1"
}
log_success() {
    echo -e "    ${GREEN}✔${NC} $1"
}

# Helper to check command inside pod
check_remote_cmd() {
    local pod=$1
    local cmd=$2
    kubectl exec "$pod" -n "$NAMESPACE" -- which "$cmd" > /dev/null 2>&1
    return $?
}

echo -e "\n${BLUE}Kong Data Plane Verification${NC}"
echo -e "Context: NS=${YELLOW}$NAMESPACE${NC} | Label=${YELLOW}$LABEL_SELECTOR${NC} | Secret=${YELLOW}$SECRET_NAME${NC}\n"

# Initialize Status Variables
STATUS_INFRA="SKIP"
STATUS_NET="SKIP"
STATUS_CP="SKIP"
STATUS_LOGS="SKIP"
STATUS_SEC="SKIP"

DETAIL_INFRA=""
DETAIL_NET=""
DETAIL_CP=""
DETAIL_LOGS=""
DETAIL_SEC=""

# --- 1. Infrastructure Check ---
log_step "1. Checking Infrastructure Layers"
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -gt 0 ]; then
    log_info "Found $POD_COUNT pod(s) with label '$LABEL_SELECTOR'."
    READY_COUNT=$(echo "$DP_PODS" | jq -r '[.items[] | select(.status.containerStatuses[0].ready == true)] | length')
    
    if [ "$READY_COUNT" -eq "$POD_COUNT" ]; then
        STATUS_INFRA="${GREEN}PASS${NC}"
        DETAIL_INFRA="$READY_COUNT/$POD_COUNT Pods Ready"
        log_success "All pods ready ($READY_COUNT/$POD_COUNT)."
    else
        STATUS_INFRA="${RED}FAIL${NC}"
        DETAIL_INFRA="$READY_COUNT/$POD_COUNT Pods Ready"
        log_err "Only $READY_COUNT/$POD_COUNT pods are ready."
    fi
    DP_POD_NAME=$(echo "$DP_PODS" | jq -r '.items[0].metadata.name')
    log_info "Using Pod '$DP_POD_NAME' for diagnostic commands."
else
    STATUS_INFRA="${RED}FAIL${NC}"
    DETAIL_INFRA="No Pods Found"
    DP_POD_NAME=""
    log_err "No pods found matching selector."
fi

# --- Configuration Discovery for CP ---
log_step "Configuration Discovery"
CP_SERVICE="www.baidu.com"
CP_PORT="443"

if [ -n "$DP_POD_NAME" ]; then
    DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    CP_ENV_VALUE=$(kubectl get deployment "$DP_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KONG_CLUSTER_CONTROL_PLANE")].value}' 2>/dev/null || echo "")
    
    if [ -n "$CP_ENV_VALUE" ]; then
        log_info "Found env KONG_CLUSTER_CONTROL_PLANE=$CP_ENV_VALUE"
        CLEAN_VAL=${CP_ENV_VALUE#*://}
        if [[ "$CLEAN_VAL" == *":"* ]]; then
            CP_SERVICE=$(echo "$CLEAN_VAL" | cut -d: -f1)
            #CP_SERVICE="www.baidu.com"
            CP_PORT=$(echo "$CLEAN_VAL" | cut -d: -f2)
            #CP_PORT="443"
        else
            CP_SERVICE="$CLEAN_VAL"
            CP_PORT="8005"
        fi
    else
        log_warn "Env KONG_CLUSTER_CONTROL_PLANE not found, defaulting to $CP_SERVICE:$CP_PORT"
    fi
else
    log_warn "Cannot check env vars (no pod found)."
fi
log_info "Target Control Plane: ${YELLOW}$CP_SERVICE:$CP_PORT${NC}"

# --- 2. Network Connectivity ---
log_step "2. Checking Network Connectivity"
if [ -n "$DP_POD_NAME" ]; then
    # Detect curl or wget
    if check_remote_cmd "$DP_POD_NAME" "curl"; then
        CMD="timeout 5 curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT"
        TOOL="curl"
    elif check_remote_cmd "$DP_POD_NAME" "wget"; then
        CMD="timeout 5 wget --no-check-certificate -T 3 -O - https://$CP_SERVICE:$CP_PORT"
        TOOL="wget"
    else
        CMD=""
        TOOL="none"
    fi

    if [ -n "$CMD" ]; then
        log_info "Testing connectivity using $TOOL..."
        # Capture both stdout and stderr
        CONN_OUTPUT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- sh -c "$CMD" 2>&1 || echo "CMD_FAILED")
        
        # Simple analysis of output for logging
        if echo "$CONN_OUTPUT" | grep -qE "Connected to|succeed|SSL|200|404"; then
             STATUS_NET="${GREEN}PASS${NC}"
             DETAIL_NET="Connected"
             log_success "Connection successful."
        elif echo "$CONN_OUTPUT" | grep -q "SSL certificate problem"; then
             STATUS_NET="${YELLOW}WARN${NC}"
             DETAIL_NET="SSL Verify Fail"
             log_warn "Connection successful but SSL verification failed."
        else
             STATUS_NET="${RED}FAIL${NC}"
             DETAIL_NET="Connection Failed"
             log_err "Connection failed."
             log_info "Output snippet: $(echo "$CONN_OUTPUT" | tail -n 2)"
        fi
    else
        STATUS_NET="${YELLOW}SKIP${NC}"
        DETAIL_NET="No curl/wget"
        log_warn "Neither 'curl' nor 'wget' found in pod."
    fi
else
    STATUS_NET="${RED}FAIL${NC}"
    DETAIL_NET="No DP Pod"
    log_err "Skipping network check (no pod)."
fi

# --- 3. Control Plane Registration  we can deleted this logic ---
log_step "3. Checking Control Plane Registration"
# Heuristic to find CP pod.
CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" -l "app=kong-cp" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$CP_POD_GUESS" ]; then
    # Try fuzzy match if label fails
    CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" | grep "kong-cp" | grep -v "$DP_POD_NAME" | head -1 | awk '{print $1}')
fi

if [ -n "$CP_POD_GUESS" ]; then
    log_info "Identified CP Pod: $CP_POD_GUESS"
    CLUSTER_STATUS=$(kubectl exec -it "$CP_POD_GUESS" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
    
    # Check if curl failed (empty json)
    if [ "$CLUSTER_STATUS" == "{}" ] || [ -z "$CLUSTER_STATUS" ]; then
         log_warn "Failed to retrieve clustering status from CP."
         STATUS_CP="${YELLOW}SKIP${NC}"
         DETAIL_CP="CP Status Query Fail"
    else
        DP_COUNT_CP=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
        log_info "CP reports $DP_COUNT_CP connected Data Plane(s)."

        if [ "$DP_COUNT_CP" -gt 0 ]; then
            if [ -n "$DP_POD_NAME" ]; then
                 DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
                 # Check IP
                 if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
                    STATUS_CP="${GREEN}PASS${NC}"
                    DETAIL_CP="Registered"
                    log_success "DP Pod IP ($DP_IP) found in CP registry."
                 else
                    STATUS_CP="${RED}FAIL${NC}"
                    DETAIL_CP="Not Registered"
                    log_err "DP Pod IP ($DP_IP) NOT found in CP registry."
                 fi
            else
                 STATUS_CP="${YELLOW}WARN${NC}"
                 DETAIL_CP="DPs exist, self unknown"
            fi
        else
            STATUS_CP="${RED}FAIL${NC}"
            DETAIL_CP="No DPs connected"
            log_err "CP registry is empty."
        fi
    fi
else
    STATUS_CP="${YELLOW}SKIP${NC}"
    DETAIL_CP="CP Pod not found (in ns '$NAMESPACE')"
    log_warn "Could not locate Control Plane pod in namespace '$NAMESPACE'. Skipping registration check."
fi

# --- 4. Logs Analysis ---
log_step "4. Logs Analysis"
if [ -n "$DP_POD_NAME" ]; then
    IS_BUSYBOX=0
    if [[ "$DP_POD_NAME" == *"busybox"* ]]; then
        IS_BUSYBOX=1
        log_info "Pod appears to be 'busybox', skipping specific Kong logs check."
    fi
    
    if [ "$IS_BUSYBOX" -eq 1 ]; then
        STATUS_LOGS="${YELLOW}SKIP${NC}"
        DETAIL_LOGS="Skipped (Busybox)"
    else
        LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "")
        log_info "Scanned last 50 lines of logs."
        if echo "$LOGS" | grep -q "control_plane: connected"; then
            STATUS_LOGS="${GREEN}PASS${NC}"
            DETAIL_LOGS="Connected signal found"
            log_success "Found 'control_plane: connected'."
        elif echo "$LOGS" | grep -q "received initial configuration snapshot"; then
            STATUS_LOGS="${GREEN}PASS${NC}"
            DETAIL_LOGS="Config synced"
            log_success "Found 'received initial configuration'."
        elif echo "$LOGS" | grep -q "failed to connect"; then
            STATUS_LOGS="${RED}FAIL${NC}"
            DETAIL_LOGS="Connection errors"
            log_err "Found connection errors in logs."
        else
            STATUS_LOGS="${YELLOW}WARN${NC}"
            DETAIL_LOGS="No clear signal"
            log_warn "No definitive success/failure signals in recent logs."
        fi
    fi
else
    STATUS_LOGS="${RED}FAIL${NC}"
    DETAIL_LOGS="No Logs"
    log_err "No pod to fetch logs from."
fi

# --- 5. Security Check ---
log_step "5. Security Check"
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
    log_info "Secret '$SECRET_NAME' found."
    CERT_EXPIRY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    
    if [ -n "$CERT_EXPIRY" ]; then
        STATUS_SEC="${GREEN}PASS${NC}"
        DETAIL_SEC="Valid (found)"
        log_success "Certificate valid until: $CERT_EXPIRY"
    else
        STATUS_SEC="${RED}FAIL${NC}"
        DETAIL_SEC="Invalid Cert (parse fail)"
        log_err "Failed to parse certificate date."
    fi
else
    STATUS_SEC="${RED}FAIL${NC}"
    DETAIL_SEC="Secret Missing"
    log_err "Secret '$SECRET_NAME' not found."
fi

# --- Output Summary ---
echo ""
echo "Kong Data Plane Summary Status"
echo "=========================================================="
printf "%-15s | %-15s | %s\n" "CATEGORY" "STATUS" "DETAILS"
echo "----------------+-----------------+-----------------------"
printf "%-15s | %b%-15s%b | %s\n" "Infrastructure" "$STATUS_INFRA" "" "$NC" "$DETAIL_INFRA"
printf "%-15s | %b%-15s%b | %s\n" "Network"        "$STATUS_NET"        "" "$NC" "$DETAIL_NET"
printf "%-15s | %b%-15s%b | %s\n" "Control Plane"  "$STATUS_CP"         "" "$NC" "$DETAIL_CP"
printf "%-15s | %b%-15s%b | %s\n" "Logs"           "$STATUS_LOGS"       "" "$NC" "$DETAIL_LOGS"
printf "%-15s | %b%-15s%b | %s\n" "Security"       "$STATUS_SEC"        "" "$NC" "$DETAIL_SEC"
echo "=========================================================="
echo ""

exit 0
