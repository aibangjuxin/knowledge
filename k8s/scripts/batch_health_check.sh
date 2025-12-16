#!/bin/bash
# Batch Health Check Script for Multiple Pods
# Uses pod_health_check_lib.sh

# Get script directory and source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/pod_health_check_lib.sh"

if [ ! -f "$LIB_PATH" ]; then
    echo "Error: Cannot find pod_health_check_lib.sh at $LIB_PATH"
    exit 1
fi

source "$LIB_PATH"

# Parse parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <label-selector>"
    echo "Example 1: $0 -n production my-app (implies app=my-app)"
    echo "Example 2: $0 -n production 'version=v1'"
    exit 1
fi

while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
# Parse label selector
if [[ "$1" == *"="* ]]; then
    LABEL_SELECTOR="$1"
else
    LABEL_SELECTOR="app=$1"
fi
APP_LABEL="$1" # Keep for display purposes

echo -e "${HC_BLUE}╔════════════════════════════════════════════════════════════════╗${HC_NC}"
echo -e "${HC_BLUE}║  Batch Health Check for Multiple Pods                         ║${HC_NC}"
echo -e "${HC_BLUE}╠════════════════════════════════════════════════════════════════╣${HC_NC}"
echo -e "${HC_BLUE}║  Label Selector: ${LABEL_SELECTOR}${HC_NC}"
echo -e "${HC_BLUE}║  Namespace: ${NAMESPACE}${HC_NC}"
echo -e "${HC_BLUE}╚════════════════════════════════════════════════════════════════╝${HC_NC}\n"

# Get all Pods with the label
PODS=$(kubectl get pods -n ${NAMESPACE} -l ${LABEL_SELECTOR} \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null)

if [ -z "$PODS" ]; then
    echo -e "${HC_RED}Error: No Pods found with label ${LABEL_SELECTOR}${HC_NC}"
    exit 1
fi

POD_COUNT=$(echo "$PODS" | wc -l | tr -d ' ')
echo -e "${HC_GREEN}Found ${POD_COUNT} Pod(s)${HC_NC}\n"

# Get probe configuration from first Pod (assuming all Pods have same config)
FIRST_POD=$(echo "$PODS" | head -n 1)
READINESS_PROBE=$(get_probe_config "$FIRST_POD" "$NAMESPACE" "readinessProbe")

if [ -z "$READINESS_PROBE" ] || [ "$READINESS_PROBE" == "null" ]; then
    echo -e "${HC_RED}Error: No readiness probe configured${HC_NC}"
    exit 1
fi

PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
if [ $? -ne 0 ]; then
    echo -e "${HC_RED}Error: Failed to extract probe endpoint${HC_NC}"
    exit 1
fi

read SCHEME PORT PROBE_PATH <<< "$PROBE_ENDPOINT"

echo -e "${HC_CYAN}Probe Configuration:${HC_NC}"
echo "  - Endpoint: ${SCHEME}://localhost:${PORT}${PROBE_PATH}"
echo ""

# Check each Pod
echo -e "${HC_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
echo -e "${HC_CYAN}Checking Pods...${HC_NC}"
echo -e "${HC_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}\n"

TOTAL=0
SUCCESS=0
FAILED=0
declare -a FAILED_PODS

for POD in $PODS; do
    TOTAL=$((TOTAL + 1))
    
    # Get Pod status
    POD_STATUS=$(get_pod_status "$POD" "$NAMESPACE")
    
    printf "%-50s " "$POD"
    
    if [ "$POD_STATUS" != "Running" ]; then
        echo -e "${HC_YELLOW}⚠ Not Running (${POD_STATUS})${HC_NC}"
        FAILED=$((FAILED + 1))
        FAILED_PODS+=("$POD (Status: $POD_STATUS)")
        continue
    fi
    
    # Perform health check with retry
    STATUS=$(check_pod_health_with_retry "$POD" "$NAMESPACE" "$SCHEME" "$PORT" "$PROBE_PATH" 2 1)
    
    if [ $? -eq 0 ]; then
        echo -e "${HC_GREEN}✓ Healthy (${STATUS})${HC_NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${HC_RED}✗ Unhealthy (${STATUS})${HC_NC}"
        FAILED=$((FAILED + 1))
        FAILED_PODS+=("$POD (HTTP $STATUS)")
    fi
done

# Summary
echo ""
echo -e "${HC_BLUE}╔════════════════════════════════════════════════════════════════╗${HC_NC}"
echo -e "${HC_BLUE}║  Summary                                                       ║${HC_NC}"
echo -e "${HC_BLUE}╚════════════════════════════════════════════════════════════════╝${HC_NC}"
echo ""
echo "Total Pods: $TOTAL"
echo -e "${HC_GREEN}Healthy: $SUCCESS${HC_NC}"
echo -e "${HC_RED}Unhealthy: $FAILED${HC_NC}"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${HC_YELLOW}Failed Pods:${HC_NC}"
    for FAILED_POD in "${FAILED_PODS[@]}"; do
        echo "  - $FAILED_POD"
    done
fi

echo ""

# Calculate health percentage
HEALTH_PERCENT=$((SUCCESS * 100 / TOTAL))
echo -e "Health Percentage: ${HEALTH_PERCENT}%"

# Visual health bar
HEALTH_BAR=""
FILLED=$((HEALTH_PERCENT / 5))
for i in $(seq 1 20); do
    if [ $i -le $FILLED ]; then
        HEALTH_BAR="${HEALTH_BAR}█"
    else
        HEALTH_BAR="${HEALTH_BAR}░"
    fi
done

if [ $HEALTH_PERCENT -ge 90 ]; then
    echo -e "${HC_GREEN}${HEALTH_BAR}${HC_NC} ${HEALTH_PERCENT}%"
elif [ $HEALTH_PERCENT -ge 70 ]; then
    echo -e "${HC_YELLOW}${HEALTH_BAR}${HC_NC} ${HEALTH_PERCENT}%"
else
    echo -e "${HC_RED}${HEALTH_BAR}${HC_NC} ${HEALTH_PERCENT}%"
fi

echo ""

# Exit with error if any Pod is unhealthy
if [ $FAILED -gt 0 ]; then
    exit 1
fi

exit 0
