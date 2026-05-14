#!/bin/bash
# Simple Pod Startup Time Measurement Script
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
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n production my-app-pod-abc123"
    exit 1
fi

while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
POD_NAME=$1

echo -e "${HC_BLUE}╔════════════════════════════════════════════════════════════════╗${HC_NC}"
echo -e "${HC_BLUE}║  Pod Startup Time Measurement (Simple Version)                ║${HC_NC}"
echo -e "${HC_BLUE}╠════════════════════════════════════════════════════════════════╣${HC_NC}"
echo -e "${HC_BLUE}║  Pod: ${POD_NAME}${HC_NC}"
echo -e "${HC_BLUE}║  Namespace: ${NAMESPACE}${HC_NC}"
echo -e "${HC_BLUE}╚════════════════════════════════════════════════════════════════╝${HC_NC}\n"

# Check if Pod exists
if ! check_pod_exists "$POD_NAME" "$NAMESPACE"; then
    echo -e "${HC_RED}Error: Pod does not exist${HC_NC}"
    exit 1
fi

# Get Pod status
POD_STATUS=$(get_pod_status "$POD_NAME" "$NAMESPACE")
echo -e "${HC_GREEN}Pod Status:${HC_NC} ${POD_STATUS}"

# Get container start time
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} \
    -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${HC_RED}Error: Container has not started yet${HC_NC}"
    exit 1
fi

echo -e "${HC_GREEN}Container Start Time:${HC_NC} ${CONTAINER_START}"
echo ""

# Get probe configuration
echo -e "${HC_CYAN}Getting probe configuration...${HC_NC}"
READINESS_PROBE=$(get_probe_config "$POD_NAME" "$NAMESPACE" "readinessProbe")

if [ -z "$READINESS_PROBE" ] || [ "$READINESS_PROBE" == "null" ]; then
    echo -e "${HC_RED}Error: No readiness probe configured${HC_NC}"
    exit 1
fi

# Extract endpoint
PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
if [ $? -ne 0 ]; then
    echo -e "${HC_RED}Error: Failed to extract probe endpoint${HC_NC}"
    exit 1
fi

read SCHEME PORT PROBE_PATH <<< "$PROBE_ENDPOINT"

echo -e "${HC_GREEN}Probe Endpoint:${HC_NC}"
echo "  - Scheme: $SCHEME"
echo "  - Port: $PORT"
echo "  - Path: $PROBE_PATH"
echo -e "  ${HC_MAGENTA}→ Full URL: ${SCHEME}://localhost:${PORT}${PROBE_PATH}${HC_NC}"
echo ""

# Calculate start time in seconds
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

# Check current status
echo -e "${HC_CYAN}Checking current health status...${HC_NC}"
CURRENT_STATUS=$(check_pod_health "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PROBE_PATH")

if [ $? -eq 0 ]; then
    echo -e "${HC_GREEN}✓ Pod is currently healthy (Status: ${CURRENT_STATUS})${HC_NC}"
    
    # Get Ready time from Kubernetes
    READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
    
    if [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
        else
            READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
        fi
        
        STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
        
        echo ""
        echo -e "${HC_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
        echo -e "${HC_BLUE}📊 Result${HC_NC}"
        echo -e "${HC_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
        echo -e "${HC_GREEN}✅ Startup Time: ${STARTUP_TIME} seconds${HC_NC}"
        echo -e "${HC_GREEN}   (Based on Kubernetes Ready status)${HC_NC}"
    fi
else
    echo -e "${HC_YELLOW}⏳ Pod is not ready yet, starting real-time monitoring...${HC_NC}"
    echo ""
    
    ELAPSED=$(wait_for_pod_ready "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PROBE_PATH" 60 2 "yes")
    
    if [ -z "$ELAPSED" ] || [ "$ELAPSED" = "-1" ]; then
        echo -e "\n${HC_RED}❌ Timeout: Pod did not become ready${HC_NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${HC_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
    echo -e "${HC_BLUE}📊 Result${HC_NC}"
    echo -e "${HC_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
    echo -e "${HC_GREEN}✅ Startup Time: ${ELAPSED} seconds${HC_NC}"
    echo -e "${HC_GREEN}   (Based on real-time monitoring)${HC_NC}"
    
    STARTUP_TIME=$ELAPSED
fi

# Analyze configuration
echo ""
echo -e "${HC_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
echo -e "${HC_CYAN}📋 Configuration Analysis${HC_NC}"
echo -e "${HC_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"

MAX_TIME=$(calculate_max_startup_time "$READINESS_PROBE")
echo "Current configuration allows max startup time: ${MAX_TIME}s"
echo "Actual startup time: ${STARTUP_TIME}s"

BUFFER=$((MAX_TIME - STARTUP_TIME))
if [ $STARTUP_TIME -gt $MAX_TIME ]; then
    echo -e "${HC_RED}⚠️  Warning: Actual startup time exceeds configuration!${HC_NC}"
    echo -e "${HC_RED}   Pod may be restarted by Kubernetes${HC_NC}"
elif [ $BUFFER -lt 10 ]; then
    echo -e "${HC_YELLOW}⚠️  Warning: Buffer time is insufficient (${BUFFER}s)${HC_NC}"
else
    echo -e "${HC_GREEN}✓ Configuration is reasonable, buffer: ${BUFFER}s${HC_NC}"
fi

echo ""
echo -e "${HC_BLUE}╔════════════════════════════════════════════════════════════════╗${HC_NC}"
echo -e "${HC_BLUE}║  Measurement Complete!                                         ║${HC_NC}"
echo -e "${HC_BLUE}╚════════════════════════════════════════════════════════════════╝${HC_NC}"
