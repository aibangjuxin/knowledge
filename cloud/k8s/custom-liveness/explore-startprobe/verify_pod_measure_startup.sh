#!/bin/bash

# Set color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Check parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n default my-api-pod-abc123"
    exit 1
fi

# Parse parameters
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
POD_NAME=$1

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Pod Startup Time Measurement and Probe Configuration Tool   ║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Pod: ${POD_NAME}${NC}"
echo -e "${BLUE}║  Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"

# 1. Get Pod basic information
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 Step 1/6: Get Pod Basic Information${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

POD_STATUS=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null)
START_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.startTime}' 2>/dev/null)
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)
CONTAINER_NAME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
CONTAINER_IMAGE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
NODE_NAME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.nodeName}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${RED}❌ Error: Container has not started or Pod does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}   Pod Status:${NC} ${POD_STATUS}"
echo -e "${GREEN}   Container Name:${NC} ${CONTAINER_NAME}"
echo -e "${GREEN}   Container Image:${NC} ${CONTAINER_IMAGE}"
echo -e "${GREEN}   Running Node:${NC} ${NODE_NAME}"
echo -e "${GREEN}   Pod Creation Time:${NC} ${START_TIME}"
echo -e "${GREEN}   Container Start Time:${NC} ${CONTAINER_START}"

# 2. Get all probe configurations
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 Step 2/6: Analyze Probe Configuration${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

STARTUP_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)
LIVENESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].livenessProbe}' 2>/dev/null)

# Show current configuration
echo -e "${YELLOW}📌 Current Probe Configuration Overview:${NC}"
echo ""

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ StartupProbe: Configured${NC}"
    STARTUP_INITIAL=$(echo "$STARTUP_PROBE" | jq -r '.initialDelaySeconds // 0')
    STARTUP_PERIOD=$(echo "$STARTUP_PROBE" | jq -r '.periodSeconds // 10')
    STARTUP_FAILURE=$(echo "$STARTUP_PROBE" | jq -r '.failureThreshold // 3')
    STARTUP_MAX_TIME=$((STARTUP_INITIAL + STARTUP_PERIOD * STARTUP_FAILURE))
    echo -e "     - initialDelaySeconds: ${STARTUP_INITIAL}s"
    echo -e "     - periodSeconds: ${STARTUP_PERIOD}s"
    echo -e "     - failureThreshold: ${STARTUP_FAILURE}"
    echo -e "     ${MAGENTA}→ Maximum allowed startup time: ${STARTUP_MAX_TIME}s${NC}"
else
    echo -e "${YELLOW}   ⚠ StartupProbe: Not configured${NC}"
fi

echo ""

if [ -n "$READINESS_PROBE" ] && [ "$READINESS_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ ReadinessProbe: Configured${NC}"
    READINESS_INITIAL=$(echo "$READINESS_PROBE" | jq -r '.initialDelaySeconds // 0')
    READINESS_PERIOD=$(echo "$READINESS_PROBE" | jq -r '.periodSeconds // 10')
    READINESS_FAILURE=$(echo "$READINESS_PROBE" | jq -r '.failureThreshold // 3')
    READINESS_MAX_TIME=$((READINESS_INITIAL + READINESS_PERIOD * READINESS_FAILURE))
    echo -e "     - initialDelaySeconds: ${READINESS_INITIAL}s"
    echo -e "     - periodSeconds: ${READINESS_PERIOD}s"
    echo -e "     - failureThreshold: ${READINESS_FAILURE}"
    if [ -z "$STARTUP_PROBE" ] || [ "$STARTUP_PROBE" == "null" ]; then
        echo -e "     ${MAGENTA}→ Maximum allowed startup time: ${READINESS_MAX_TIME}s (without StartupProbe)${NC}"
    fi
else
    echo -e "${RED}   ✗ ReadinessProbe: Not configured${NC}"
    exit 1
fi

echo ""

if [ -n "$LIVENESS_PROBE" ] && [ "$LIVENESS_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ LivenessProbe: Configured${NC}"
    LIVENESS_INITIAL=$(echo "$LIVENESS_PROBE" | jq -r '.initialDelaySeconds // 0')
    LIVENESS_PERIOD=$(echo "$LIVENESS_PROBE" | jq -r '.periodSeconds // 10')
    LIVENESS_FAILURE=$(echo "$LIVENESS_PROBE" | jq -r '.failureThreshold // 3')
    echo -e "     - initialDelaySeconds: ${LIVENESS_INITIAL}s"
    echo -e "     - periodSeconds: ${LIVENESS_PERIOD}s"
    echo -e "     - failureThreshold: ${LIVENESS_FAILURE}"
else
    echo -e "${YELLOW}   ⚠ LivenessProbe: Not configured${NC}"
fi

# 3. Extract probe parameters (prioritize ReadinessProbe)
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 Step 3/6: Extract Probe Detection Parameters${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PROBE_SCHEME=$(echo "$READINESS_PROBE" | jq -r '.httpGet.scheme // "HTTP"')
PROBE_PORT=$(echo "$READINESS_PROBE" | jq -r '.httpGet.port // 8080')
PROBE_PATH=$(echo "$READINESS_PROBE" | jq -r '.httpGet.path // "/health"')

echo -e "${GREEN}   Detection Endpoint Information:${NC}"
echo "   - Scheme: ${PROBE_SCHEME}"
echo "   - Port: ${PROBE_PORT}"
echo "   - Path: ${PROBE_PATH}"
echo -e "   ${MAGENTA}→ Full URL: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"

# 4. Calculate container start timestamp
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

if [ -z "$START_TIME_SEC" ]; then
    echo -e "${RED}❌ Error: Unable to parse container start time${NC}"
    exit 1
fi

# 5. Check if Pod is already Ready
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}⏱️  Step 4/6: Measure Actual Startup Time${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

READY_CONDITION=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)

if [ "$READY_CONDITION" == "True" ] && [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
    # Pod is already Ready, calculate directly from Kubernetes status
    echo -e "${GREEN}   ✓ Pod is already in Ready status${NC}"
    echo -e "${GREEN}   Ready Time: ${READY_TIME}${NC}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
    else
        READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
    fi

    STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
    PROBE_COUNT=0
    MEASUREMENT_SOURCE="Kubernetes Ready Status"
else
    # Pod is not yet Ready, need real-time detection
    echo -e "${YELLOW}   ⏳ Pod is not Ready, starting real-time detection...${NC}"
    echo -e "${GREEN}   Target: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"
    echo ""

    PROBE_COUNT=0
    MAX_PROBES=180
    SCRIPT_START_TIME=$(date +%s)

    while [ $PROBE_COUNT -lt $MAX_PROBES ]; do
        PROBE_COUNT=$((PROBE_COUNT + 1))

        # Select detection method based on protocol
        if [[ "$PROBE_SCHEME" == "HTTPS" ]]; then
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "openssl s_client -connect localhost:${PROBE_PORT} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        else
            # HTTP Strategy: curl -> wget -> nc
            # execute a single compound command inside the pod to find an available tool
            local cmd="
            if command -v curl >/dev/null 2>&1; then
                # Option 1: curl (preferred)
                curl -m 2 -s -I 'http://localhost:${PROBE_PORT}${PROBE_PATH}' 2>/dev/null | head -n 1
            elif command -v wget >/dev/null 2>&1; then
                # Option 2: wget
                wget -T 2 -q --spider --server-response 'http://localhost:${PROBE_PORT}${PROBE_PATH}' 2>&1 | grep '^  HTTP' | head -n 1
            else
                # Option 3: nc (fallback)
                printf 'GET ${PROBE_PATH} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' | timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1
            fi"
            
            HTTP_STATUS_LINE=$(kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "$cmd" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        fi

        CURRENT_TIME_SEC=$(date +%s)
        POD_AGE=$((CURRENT_TIME_SEC - START_TIME_SEC))

        if [[ "$HTTP_CODE" == "200" ]]; then
            echo -e "${GREEN}   ✅ Health check passed (HTTP 200 OK)!${NC}"

            # Wait for Kubernetes to update Ready status
            sleep 2

            # Get Ready time again
            READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)

            if [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
                else
                    READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
                fi
                STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
                MEASUREMENT_SOURCE="Kubernetes Ready Status"
            else
                # Kubernetes hasn't updated yet, use detection time estimate
                STARTUP_TIME=$POD_AGE
                MEASUREMENT_SOURCE="Real-time Detection Estimate"
            fi

            break
        else
            # Display progress bar
            PROGRESS_BAR=""
            PROGRESS_PERCENT=$((PROBE_COUNT * 100 / MAX_PROBES))
            FILLED=$((PROGRESS_PERCENT / 5))
            for i in $(seq 1 20); do
                if [ $i -le $FILLED ]; then
                    PROGRESS_BAR="${PROGRESS_BAR}█"
                else
                    PROGRESS_BAR="${PROGRESS_BAR}░"
                fi
            done
            echo -e "   [${PROBE_COUNT}/${MAX_PROBES}] ${PROGRESS_BAR} ${PROGRESS_PERCENT}% | Pod Running: ${POD_AGE}s | Status Code: ${HTTP_CODE}"
            sleep 2
        fi
    done

    if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
        echo -e "\n${RED}❌ Timeout: Detection exceeded ${MAX_PROBES} attempts without success${NC}"
        exit 1
    fi
fi

# 6. Display measurement results
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📊 Step 5/6: Startup Time Analysis${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${GREEN}   ✅ Actual Application Startup Time: ${STARTUP_TIME} seconds${NC}"
echo -e "${GREEN}   📍 Measurement Data Source: ${MEASUREMENT_SOURCE}${NC}"
if [ $PROBE_COUNT -gt 0 ]; then
    echo -e "${GREEN}   🔍 Number of Probes: ${PROBE_COUNT}${NC}"
fi

# Timeline visualization
echo -e "\n${YELLOW}   ⏱️  Startup Timeline:${NC}"
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │ 0s                                          ${STARTUP_TIME}s │"
echo "   │ ├───────────────────────────────────────────┤           │"
echo "   │ Container Start                      Application Ready   │"
echo "   └─────────────────────────────────────────────────────────┘"

# Configuration comparison analysis
echo -e "\n${YELLOW}   📊 Configuration Comparison Analysis:${NC}"

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    CURRENT_MAX_TIME=$STARTUP_MAX_TIME
    CONFIG_TYPE="StartupProbe"
else
    CURRENT_MAX_TIME=$READINESS_MAX_TIME
    CONFIG_TYPE="ReadinessProbe (without StartupProbe)"
fi

echo -e "   Current Configuration Type: ${CONFIG_TYPE}"
echo -e "   Maximum Allowed Startup Time: ${CURRENT_MAX_TIME}s"
echo -e "   Actual Startup Time: ${STARTUP_TIME}s"

BUFFER_TIME=$((CURRENT_MAX_TIME - STARTUP_TIME))
if [ $STARTUP_TIME -gt $CURRENT_MAX_TIME ]; then
    echo -e "   ${RED}⚠️  Risk: Actual startup time exceeds configuration by $((STARTUP_TIME - CURRENT_MAX_TIME))s!${NC}"
    echo -e "   ${RED}   Pod may be incorrectly judged as startup failure and restarted by Kubernetes${NC}"
elif [ $BUFFER_TIME -lt 10 ]; then
    echo -e "   ${YELLOW}⚠️  Warning: Insufficient buffer time (only ${BUFFER_TIME}s)${NC}"
    echo -e "   ${YELLOW}   Recommend adding buffer to handle startup time fluctuations${NC}"
else
    echo -e "   ${GREEN}✓ Configuration is reasonable, buffer time: ${BUFFER_TIME}s${NC}"
fi

# 7. Configuration recommendations
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}💡 Step 6/6: Configuration Optimization Recommendations${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Calculate recommended failureThreshold (actual time * 1.5 / period + 1)
RECOMMENDED_STARTUP_PERIOD=10
RECOMMENDED_READINESS_PERIOD=5
RECOMMENDED_STARTUP_THRESHOLD=$(echo "scale=0; ($STARTUP_TIME * 1.5 / $RECOMMENDED_STARTUP_PERIOD) + 1" | bc)
RECOMMENDED_READINESS_THRESHOLD=3

echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Option 1: Using StartupProbe + ReadinessProbe (Recommended)  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Advantages:${NC}"
echo "  • Separates startup and runtime phases for more precise health checks"
echo "  • StartupProbe allows longer startup times"
echo "  • ReadinessProbe responds quickly to runtime status changes"
echo "  • Prevents slow-starting applications from being incorrectly marked as unhealthy"
echo ""
echo -e "${CYAN}Configuration Example:${NC}"
echo ""
echo "  startupProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_STARTUP_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_STARTUP_THRESHOLD}"
echo -e "    ${MAGENTA}# Maximum startup time: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s (actual: ${STARTUP_TIME}s × 1.5 buffer)${NC}"
echo ""
echo "  readinessProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_READINESS_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_READINESS_THRESHOLD}"
echo -e "    ${MAGENTA}# Runtime quick detection, marked as NotReady after at most $((RECOMMENDED_READINESS_PERIOD * RECOMMENDED_READINESS_THRESHOLD))s${NC}"

if [ -n "$LIVENESS_PROBE" ] && [ "$LIVENESS_PROBE" != "null" ]; then
    echo ""
    echo "  livenessProbe:"
    echo "    httpGet:"
    echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: 10"
echo "    failureThreshold: 3"
echo -e "    ${MAGENTA}# Detect serious issues like deadlocks, restart container after 30s${NC}"
fi

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Option 2: Using ReadinessProbe Only (Simple Scenario)        ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Applicable Scenarios:${NC}"
echo "  • Application startup time is stable and short (< 30s)"
echo "  • No need to distinguish between startup and runtime phases"
echo ""
echo -e "${CYAN}Configuration Example:${NC}"
echo ""
echo "  readinessProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_STARTUP_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_STARTUP_THRESHOLD}"
echo -e "    ${MAGENTA}# Maximum startup time: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s${NC}"

# Comparison table
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Configuration Comparison Summary                             ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
printf "  %-20s %-20s %-20s\n" "Item" "Current Config" "Recommended Config"
echo "  ────────────────────────────────────────────────────────────"

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    printf "  %-20s %-20s %-20s\n" "StartupProbe" "Configured" "Optimized Params"
    printf "  %-20s %-20s %-20s\n" "  - Period" "${STARTUP_PERIOD}s" "${RECOMMENDED_STARTUP_PERIOD}s"
    printf "  %-20s %-20s %-20s\n" "  - Threshold" "${STARTUP_FAILURE}" "${RECOMMENDED_STARTUP_THRESHOLD}"
    printf "  %-20s %-20s %-20s\n" "  - Max Time" "${STARTUP_MAX_TIME}s" "$((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s"
else
    printf "  %-20s %-20s %-20s\n" "StartupProbe" "Not Configured" "Recommended to Add"
fi

printf "  %-20s %-20s %-20s\n" "ReadinessProbe" "Configured" "Optimized Params"
printf "  %-20s %-20s %-20s\n" "  - Period" "${READINESS_PERIOD}s" "${RECOMMENDED_READINESS_PERIOD}s"
printf "  %-20s %-20s %-20s\n" "  - Threshold" "${READINESS_FAILURE}" "${RECOMMENDED_READINESS_THRESHOLD}"

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Key Metrics Summary                                           ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} Actual Startup Time: ${STARTUP_TIME}s"
echo -e "  ${GREEN}✓${NC} Recommended Maximum Startup Time: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s (1.5x buffer)"
echo -e "  ${GREEN}✓${NC} Buffer Time: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD - STARTUP_TIME))s"
echo -e "  ${GREEN}✓${NC} Detection Endpoint: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Analysis Complete! Please optimize your Pod configuration     ║${NC}"
echo -e "${BLUE}║  according to the recommendations above                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""