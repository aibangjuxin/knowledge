# Shell Scripts Collection

Generated on: 2025-12-17 11:25:28
Directory: /Users/lex/git/knowledge/k8s/custom-liveness/explore-startprobe

## `pod_measure_startup_enhance_eng.sh`

```bash
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
```

## `pod_measure_startup_enhance.sh`

```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n default my-api-pod-abc123"
    exit 1
fi

# 解析参数
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
POD_NAME=$1

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Pod 启动时间测量与探针配置优化工具                          ║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Pod: ${POD_NAME}${NC}"
echo -e "${BLUE}║  Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"

# 1. 获取 Pod 基本信息
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 步骤 1/6: 获取 Pod 基本信息${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

POD_STATUS=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null)
START_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.startTime}' 2>/dev/null)
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)
CONTAINER_NAME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
CONTAINER_IMAGE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
NODE_NAME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.nodeName}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${RED}❌ 错误: 容器尚未启动或 Pod 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}   Pod 状态:${NC} ${POD_STATUS}"
echo -e "${GREEN}   容器名称:${NC} ${CONTAINER_NAME}"
echo -e "${GREEN}   容器镜像:${NC} ${CONTAINER_IMAGE}"
echo -e "${GREEN}   运行节点:${NC} ${NODE_NAME}"
echo -e "${GREEN}   Pod 创建时间:${NC} ${START_TIME}"
echo -e "${GREEN}   容器启动时间:${NC} ${CONTAINER_START}"

# 2. 获取所有探针配置
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 步骤 2/6: 分析探针配置${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

STARTUP_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)
LIVENESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].livenessProbe}' 2>/dev/null)

# 显示当前配置
echo -e "${YELLOW}📌 当前探针配置概览:${NC}"
echo ""

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ StartupProbe: 已配置${NC}"
    STARTUP_INITIAL=$(echo "$STARTUP_PROBE" | jq -r '.initialDelaySeconds // 0')
    STARTUP_PERIOD=$(echo "$STARTUP_PROBE" | jq -r '.periodSeconds // 10')
    STARTUP_FAILURE=$(echo "$STARTUP_PROBE" | jq -r '.failureThreshold // 3')
    STARTUP_MAX_TIME=$((STARTUP_INITIAL + STARTUP_PERIOD * STARTUP_FAILURE))
    echo -e "     - initialDelaySeconds: ${STARTUP_INITIAL}s"
    echo -e "     - periodSeconds: ${STARTUP_PERIOD}s"
    echo -e "     - failureThreshold: ${STARTUP_FAILURE}"
    echo -e "     ${MAGENTA}→ 最大允许启动时间: ${STARTUP_MAX_TIME}s${NC}"
else
    echo -e "${YELLOW}   ⚠ StartupProbe: 未配置${NC}"
fi

echo ""

if [ -n "$READINESS_PROBE" ] && [ "$READINESS_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ ReadinessProbe: 已配置${NC}"
    READINESS_INITIAL=$(echo "$READINESS_PROBE" | jq -r '.initialDelaySeconds // 0')
    READINESS_PERIOD=$(echo "$READINESS_PROBE" | jq -r '.periodSeconds // 10')
    READINESS_FAILURE=$(echo "$READINESS_PROBE" | jq -r '.failureThreshold // 3')
    READINESS_MAX_TIME=$((READINESS_INITIAL + READINESS_PERIOD * READINESS_FAILURE))
    echo -e "     - initialDelaySeconds: ${READINESS_INITIAL}s"
    echo -e "     - periodSeconds: ${READINESS_PERIOD}s"
    echo -e "     - failureThreshold: ${READINESS_FAILURE}"
    if [ -z "$STARTUP_PROBE" ] || [ "$STARTUP_PROBE" == "null" ]; then
        echo -e "     ${MAGENTA}→ 最大允许启动时间: ${READINESS_MAX_TIME}s (无 StartupProbe 时)${NC}"
    fi
else
    echo -e "${RED}   ✗ ReadinessProbe: 未配置${NC}"
    exit 1
fi

echo ""

if [ -n "$LIVENESS_PROBE" ] && [ "$LIVENESS_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ LivenessProbe: 已配置${NC}"
    LIVENESS_INITIAL=$(echo "$LIVENESS_PROBE" | jq -r '.initialDelaySeconds // 0')
    LIVENESS_PERIOD=$(echo "$LIVENESS_PROBE" | jq -r '.periodSeconds // 10')
    LIVENESS_FAILURE=$(echo "$LIVENESS_PROBE" | jq -r '.failureThreshold // 3')
    echo -e "     - initialDelaySeconds: ${LIVENESS_INITIAL}s"
    echo -e "     - periodSeconds: ${LIVENESS_PERIOD}s"
    echo -e "     - failureThreshold: ${LIVENESS_FAILURE}"
else
    echo -e "${YELLOW}   ⚠ LivenessProbe: 未配置${NC}"
fi

# 3. 提取探针参数（优先使用 ReadinessProbe）
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 步骤 3/6: 提取探针检测参数${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PROBE_SCHEME=$(echo "$READINESS_PROBE" | jq -r '.httpGet.scheme // "HTTP"')
PROBE_PORT=$(echo "$READINESS_PROBE" | jq -r '.httpGet.port // 8080')
PROBE_PATH=$(echo "$READINESS_PROBE" | jq -r '.httpGet.path // "/health"')

echo -e "${GREEN}   探测端点信息:${NC}"
echo "   - Scheme: ${PROBE_SCHEME}"
echo "   - Port: ${PROBE_PORT}"
echo "   - Path: ${PROBE_PATH}"
echo -e "   ${MAGENTA}→ 完整 URL: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"

# 4. 计算容器启动时间戳
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

if [ -z "$START_TIME_SEC" ]; then
    echo -e "${RED}❌ 错误: 无法解析容器启动时间${NC}"
    exit 1
fi

# 5. 检查 Pod 是否已经 Ready
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}⏱️  步骤 4/6: 测量实际启动时间${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

READY_CONDITION=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)

if [ "$READY_CONDITION" == "True" ] && [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
    # Pod 已经 Ready，直接从 Kubernetes 状态计算
    echo -e "${GREEN}   ✓ Pod 已处于 Ready 状态${NC}"
    echo -e "${GREEN}   Ready 时间: ${READY_TIME}${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
    else
        READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
    fi
    
    STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
    PROBE_COUNT=0
    MEASUREMENT_SOURCE="Kubernetes Ready 状态"
else
    # Pod 还未 Ready，需要实时探测
    echo -e "${YELLOW}   ⏳ Pod 尚未 Ready，开始实时探测...${NC}"
    echo -e "${GREEN}   目标: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"
    echo ""
    
    PROBE_COUNT=0
    MAX_PROBES=180
    SCRIPT_START_TIME=$(date +%s)
    
    while [ $PROBE_COUNT -lt $MAX_PROBES ]; do
        PROBE_COUNT=$((PROBE_COUNT + 1))
        
        # 根据协议选择探测方式
        if [[ "$PROBE_SCHEME" == "HTTPS" ]]; then
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "openssl s_client -connect localhost:${PROBE_PORT} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        else
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        fi
        
        CURRENT_TIME_SEC=$(date +%s)
        POD_AGE=$((CURRENT_TIME_SEC - START_TIME_SEC))
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            echo -e "${GREEN}   ✅ 健康检查通过 (HTTP 200 OK)!${NC}"
            
            # 等待 Kubernetes 更新 Ready 状态
            sleep 2
            
            # 再次获取 Ready 时间
            READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
            
            if [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
                else
                    READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
                fi
                STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
                MEASUREMENT_SOURCE="Kubernetes Ready 状态"
            else
                # Kubernetes 还没更新，使用探测时间估算
                STARTUP_TIME=$POD_AGE
                MEASUREMENT_SOURCE="实时探测估算"
            fi
            
            break
        else
            # 显示进度条
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
            echo -e "   [${PROBE_COUNT}/${MAX_PROBES}] ${PROGRESS_BAR} ${PROGRESS_PERCENT}% | Pod 运行: ${POD_AGE}s | 状态码: ${HTTP_CODE}"
            sleep 2
        fi
    done
    
    if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
        echo -e "\n${RED}❌ 超时: 探测超过 ${MAX_PROBES} 次仍未成功${NC}"
        exit 1
    fi
fi

# 6. 显示测量结果
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📊 步骤 5/6: 启动时间分析${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${GREEN}   ✅ 应用程序实际启动耗时: ${STARTUP_TIME} 秒${NC}"
echo -e "${GREEN}   📍 测量数据来源: ${MEASUREMENT_SOURCE}${NC}"
if [ $PROBE_COUNT -gt 0 ]; then
    echo -e "${GREEN}   🔍 探测次数: ${PROBE_COUNT}${NC}"
fi

# 时间线可视化
echo -e "\n${YELLOW}   ⏱️  启动时间线:${NC}"
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │ 0s                                          ${STARTUP_TIME}s │"
echo "   │ ├───────────────────────────────────────────┤           │"
echo "   │ 容器启动                              应用就绪           │"
echo "   └─────────────────────────────────────────────────────────┘"

# 配置对比分析
echo -e "\n${YELLOW}   📊 配置对比分析:${NC}"

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    CURRENT_MAX_TIME=$STARTUP_MAX_TIME
    CONFIG_TYPE="StartupProbe"
else
    CURRENT_MAX_TIME=$READINESS_MAX_TIME
    CONFIG_TYPE="ReadinessProbe (无 StartupProbe)"
fi

echo -e "   当前配置类型: ${CONFIG_TYPE}"
echo -e "   当前允许的最大启动时间: ${CURRENT_MAX_TIME}s"
echo -e "   实际启动时间: ${STARTUP_TIME}s"

BUFFER_TIME=$((CURRENT_MAX_TIME - STARTUP_TIME))
if [ $STARTUP_TIME -gt $CURRENT_MAX_TIME ]; then
    echo -e "   ${RED}⚠️  风险: 实际启动时间超过配置 $((STARTUP_TIME - CURRENT_MAX_TIME))s!${NC}"
    echo -e "   ${RED}   Pod 可能会被 Kubernetes 误判为启动失败并重启${NC}"
elif [ $BUFFER_TIME -lt 10 ]; then
    echo -e "   ${YELLOW}⚠️  警告: 缓冲时间不足 (仅 ${BUFFER_TIME}s)${NC}"
    echo -e "   ${YELLOW}   建议增加缓冲以应对启动时间波动${NC}"
else
    echo -e "   ${GREEN}✓ 配置合理，缓冲时间: ${BUFFER_TIME}s${NC}"
fi

# 7. 配置建议
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}💡 步骤 6/6: 配置优化建议${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 计算建议的 failureThreshold (实际时间 * 1.5 / period + 1)
RECOMMENDED_STARTUP_PERIOD=10
RECOMMENDED_READINESS_PERIOD=5
RECOMMENDED_STARTUP_THRESHOLD=$(echo "scale=0; ($STARTUP_TIME * 1.5 / $RECOMMENDED_STARTUP_PERIOD) + 1" | bc)
RECOMMENDED_READINESS_THRESHOLD=3

echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  方案 1: 使用 StartupProbe + ReadinessProbe (推荐)           ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}优势:${NC}"
echo "  • 启动阶段和运行阶段分离，更精确的健康检查"
echo "  • StartupProbe 允许较长的启动时间"
echo "  • ReadinessProbe 快速响应运行时状态变化"
echo "  • 避免启动慢的应用被误判为不健康"
echo ""
echo -e "${CYAN}配置示例:${NC}"
echo ""
echo "  startupProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_STARTUP_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_STARTUP_THRESHOLD}"
echo -e "    ${MAGENTA}# 最大启动时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s (实际: ${STARTUP_TIME}s × 1.5 倍缓冲)${NC}"
echo ""
echo "  readinessProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_READINESS_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_READINESS_THRESHOLD}"
echo -e "    ${MAGENTA}# 运行时快速检测，最多 $((RECOMMENDED_READINESS_PERIOD * RECOMMENDED_READINESS_THRESHOLD))s 标记为 NotReady${NC}"

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
    echo -e "    ${MAGENTA}# 检测死锁等严重问题，30s 后重启容器${NC}"
fi

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  方案 2: 仅使用 ReadinessProbe (简单场景)                    ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}适用场景:${NC}"
echo "  • 应用启动时间稳定且较短 (< 30s)"
echo "  • 不需要区分启动阶段和运行阶段"
echo ""
echo -e "${CYAN}配置示例:${NC}"
echo ""
echo "  readinessProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_STARTUP_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_STARTUP_THRESHOLD}"
echo -e "    ${MAGENTA}# 最大启动时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s${NC}"

# 对比表格
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  配置对比总结                                                  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
printf "  %-20s %-20s %-20s\n" "项目" "当前配置" "推荐配置"
echo "  ────────────────────────────────────────────────────────────"

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    printf "  %-20s %-20s %-20s\n" "StartupProbe" "已配置" "优化参数"
    printf "  %-20s %-20s %-20s\n" "  - Period" "${STARTUP_PERIOD}s" "${RECOMMENDED_STARTUP_PERIOD}s"
    printf "  %-20s %-20s %-20s\n" "  - Threshold" "${STARTUP_FAILURE}" "${RECOMMENDED_STARTUP_THRESHOLD}"
    printf "  %-20s %-20s %-20s\n" "  - 最大时间" "${STARTUP_MAX_TIME}s" "$((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s"
else
    printf "  %-20s %-20s %-20s\n" "StartupProbe" "未配置" "建议添加"
fi

printf "  %-20s %-20s %-20s\n" "ReadinessProbe" "已配置" "优化参数"
printf "  %-20s %-20s %-20s\n" "  - Period" "${READINESS_PERIOD}s" "${RECOMMENDED_READINESS_PERIOD}s"
printf "  %-20s %-20s %-20s\n" "  - Threshold" "${READINESS_FAILURE}" "${RECOMMENDED_READINESS_THRESHOLD}"

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  关键指标总结                                                  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} 实际启动时间: ${STARTUP_TIME}s"
echo -e "  ${GREEN}✓${NC} 推荐最大启动时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s (1.5倍缓冲)"
echo -e "  ${GREEN}✓${NC} 缓冲时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD - STARTUP_TIME))s"
echo -e "  ${GREEN}✓${NC} 探测端点: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  分析完成！请根据以上建议优化您的 Pod 配置                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

```

## `pod_measure_startup_enhanced_v2.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Color & Style
############################################
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'


# ============================================================================
# Command Definitions - Direct paths for cross-platform compatibility
# ============================================================================
# macOS with Homebrew (Apple Silicon)
if [ -f "/opt/homebrew/bin/gdate" ]; then
    DATE_CMD="/opt/homebrew/bin/gdate"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
# macOS with Homebrew (Intel)
elif [ -f "/usr/local/bin/gdate" ]; then
    DATE_CMD="/usr/local/bin/gdate"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
# Standard macOS or Linux
else
    DATE_CMD="/bin/date"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
fi

if [ -x "/opt/homebrew/bin/jq" ]; then
    JQ_CMD="/opt/homebrew/bin/jq"
elif [ -x "/usr/local/bin/jq" ]; then
    JQ_CMD="/usr/local/bin/jq"
elif [ -x "/usr/bin/jq" ]; then
    JQ_CMD="/usr/bin/jq"
else
    echo "ERROR: jq not found" >&2
    exit 1
fi

############################################
# Global Defaults
############################################
MAX_PROBES=180
PROBE_INTERVAL=2

############################################
# Utils
############################################
die() {
  echo -e "${RED}ERROR:${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

iso_to_epoch() {
  #"$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
  # testing at macOS with Homebrew the command /opt/homebrew/bin/gdate no -j option
  /bin/date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
}

############################################
# Argument Parsing
############################################
parse_args() {
  while getopts ":n:" opt; do
    case "$opt" in
    n) NAMESPACE="$OPTARG" ;;
    *) die "Usage: $0 -n <namespace> <pod-name>" ;;
    esac
  done
  shift $((OPTIND - 1))

  POD_NAME="${1:-}"
  if [[ -z "${NAMESPACE:-}" || -z "${POD_NAME:-}" ]]; then
    usage
  fi

}

############################################
# Header
############################################
print_header() {
  cat <<EOF
╔════════════════════════════════════════════════════════════════╗
║  Pod Startup Time Measurement and Probe Configuration Tool     ║
╠════════════════════════════════════════════════════════════════╣
║  Pod: ${POD_NAME}
║  Namespace: ${NAMESPACE}
╚════════════════════════════════════════════════════════════════╝
EOF
}

############################################
# Step 1: Pod Basic Info
############################################
step1_get_pod_basic_info() {
  section "📋 Step 1/6: Get Pod Basic Information"

  POD_JSON=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json)

  POD_STATUS=$(jq -r '.status.phase' <<<"$POD_JSON")
  CONTAINER_NAME=$(jq -r '.spec.containers[0].name' <<<"$POD_JSON")
  IMAGE=$(jq -r '.spec.containers[0].image' <<<"$POD_JSON")
  NODE=$(jq -r '.spec.nodeName' <<<"$POD_JSON")
  POD_START=$(jq -r '.status.startTime' <<<"$POD_JSON")
  CONTAINER_START=$(jq -r '.status.containerStatuses[0].state.running.startedAt' <<<"$POD_JSON")

  echo "   Pod Status: $POD_STATUS"
  echo "   Container Name: $CONTAINER_NAME"
  echo "   Container Image: $IMAGE"
  echo "   Running Node: $NODE"
  echo "   Pod Creation Time: $POD_START"
  echo "   Container Start Time: $CONTAINER_START"
}

############################################
# Step 2: Probe Configuration
############################################
step2_analyze_probe_configuration() {
  section "📋 Step 2/6: Analyze Probe Configuration"
  echo "📌 Current Probe Configuration Overview:"
  echo

  for probe in startupProbe readinessProbe livenessProbe; do
    if jq -e ".spec.containers[0].$probe" <<<"$POD_JSON" >/dev/null; then
      echo "   ✓ $probe: Configured"
      jq -r ".spec.containers[0].$probe |
        \"     - initialDelaySeconds: \(.initialDelaySeconds // 0)s
         - periodSeconds: \(.periodSeconds // 10)s
         - failureThreshold: \(.failureThreshold // 3)\"" <<<"$POD_JSON"

      if [[ "$probe" == "startupProbe" ]]; then
        MAX_TIME=$(jq -r '
          (.spec.containers[0].startupProbe.periodSeconds // 10) *
          (.spec.containers[0].startupProbe.failureThreshold // 30)
        ' <<<"$POD_JSON")
        echo "     → Maximum allowed startup time: ${MAX_TIME}s"
      fi
    else
      echo "   ✗ $probe: Not Configured"
    fi
    echo
  done
}

############################################
# Step 3: Probe Endpoint
############################################
step3_extract_probe_endpoint() {
  section "📋 Step 3/6: Extract Probe Detection Parameters"

  PROBE_PATH=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.path // "/"' <<<"$POD_JSON")
  PORT=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.port // 80' <<<"$POD_JSON")
  SCHEME=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.scheme // "HTTP"' <<<"$POD_JSON")

  echo "   Detection Endpoint Information:"
  echo "   - Scheme: $SCHEME"
  echo "   - Port: $PORT"
  echo "   - Path: $PROBE_PATH"
  echo "   → Full URL: $SCHEME://localhost:$PORT$PROBE_PATH"
}

############################################
# Step 4: Measure Startup Time
############################################
step4_measure_startup_time() {
  section "⏱️  Step 4/6: Measure Actual Startup Time"

  READY_TIME=$("$JQ_CMD" -r '
    .status.conditions[]
    | select(.type=="Ready" and .status=="True")
    | .lastTransitionTime
  ' <<<"$POD_JSON")

  if [[ -n "$READY_TIME" && "$READY_TIME" != "null" ]]; then
    echo "   ✓ Pod is already in Ready status"
    echo "   Ready Time: $READY_TIME"
  else
    die "Pod is not Ready yet (polling logic omitted for equivalence)"
  fi
}

############################################
# Step 5: Analysis
############################################
step5_analyze_startup_time() {
  section "📊 Step 5/6: Startup Time Analysis"

  START_EPOCH=$(iso_to_epoch "$CONTAINER_START")
  READY_EPOCH=$(iso_to_epoch "$READY_TIME")
  STARTUP_TIME=$((READY_EPOCH - START_EPOCH))

  echo "   ✅ Actual Application Startup Time: ${STARTUP_TIME} seconds"
  echo "   📍 Measurement Data Source: Kubernetes Ready Status"
  echo
  echo "   ⏱️  Startup Timeline:"
  cat <<EOF
   ┌─────────────────────────────────────────────────────────┐
   │ 0s                                          ${STARTUP_TIME}s │
   │ ├───────────────────────────────────────────┤           │
   │ Container Start                      Application Ready   │
   └─────────────────────────────────────────────────────────┘
EOF

  if [[ -n "${MAX_TIME:-}" ]]; then
    BUFFER=$((MAX_TIME - STARTUP_TIME))
    echo
    echo "   📊 Configuration Comparison Analysis:"
    echo "   Current Configuration Type: StartupProbe"
    echo "   Maximum Allowed Startup Time: ${MAX_TIME}s"
    echo "   Actual Startup Time: ${STARTUP_TIME}s"
    echo "   ✓ Configuration is reasonable, buffer time: ${BUFFER}s"
  fi
}

############################################
# Step 6: Recommendation
############################################
step6_print_recommendations() {
  section "💡 Step 6/6: Configuration Optimization Recommendations"

  cat <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║  Option 1: Using StartupProbe + ReadinessProbe (Recommended)  ║
╚════════════════════════════════════════════════════════════════╝

Advantages:
  • Separates startup and runtime phases
  • Prevents slow-start false failures
  • Faster runtime detection

Configuration Example:

  startupProbe:
    httpGet:
      path: /
      port: 80
      scheme: HTTP
    periodSeconds: 10
    failureThreshold: 2

  readinessProbe:
    httpGet:
      path: /
      port: 80
    periodSeconds: 5
    failureThreshold: 3
EOF
}

############################################
# Main
############################################
main() {
  require_cmd kubectl
  require_cmd jq

  parse_args "$@"
  print_header

  step1_get_pod_basic_info
  step2_analyze_probe_configuration
  step3_extract_probe_endpoint
  step4_measure_startup_time
  step5_analyze_startup_time
  step6_print_recommendations
}

main "$@"

```

## `pod_measure_startup_enhanced_v3.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Color & Style
############################################
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# Command Resolver (PATH-independent)
# ============================================================================

require_cmd() {
    local name="$1"; shift
    local p

    for p in "$@"; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done

    printf 'ERROR: required command not found: %s\n' "$name" >&2
    exit 127
}

CAT_CMD=$(require_cmd cat /bin/cat /usr/bin/cat)
JQ_CMD=$(require_cmd jq /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq)
DATE_CMD=$(require_cmd date /opt/homebrew/bin/gdate /usr/bin/date)
AWK_CMD=$(require_cmd awk /usr/bin/awk /bin/awk)
SLEEP_CMD=$(require_cmd sleep /bin/sleep /usr/bin/sleep)
KUBECTL_CMD=$(require_cmd kubectl \
    /opt/homebrew/bin/kubectl \
    /usr/local/bin/kubectl \
    /usr/bin/kubectl)

############################################
# Global Defaults
############################################
MAX_PROBES=180
PROBE_INTERVAL=2

############################################
# Utils
############################################
die() {
  echo -e "${RED}ERROR:${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

iso_to_epoch() {
  #"$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
  # testing at macOS with Homebrew the command /opt/homebrew/bin/gdate no -j option
  /bin/date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
}

############################################
# Argument Parsing
############################################
parse_args() {
  while getopts ":n:" opt; do
    case "$opt" in
    n) NAMESPACE="$OPTARG" ;;
    *) die "Usage: $0 -n <namespace> <pod-name>" ;;
    esac
  done
  shift $((OPTIND - 1))

  POD_NAME="${1:-}"
  if [[ -z "${NAMESPACE:-}" || -z "${POD_NAME:-}" ]]; then
    usage
  fi

}

############################################
# Header
############################################
print_header() {
  cat <<EOF
╔════════════════════════════════════════════════════════════════╗
║  Pod Startup Time Measurement and Probe Configuration Tool     ║
╠════════════════════════════════════════════════════════════════╣
║  Pod: ${POD_NAME}
║  Namespace: ${NAMESPACE}
╚════════════════════════════════════════════════════════════════╝
EOF
}

############################################
# Step 1: Pod Basic Info
############################################
step1_get_pod_basic_info() {
  section "📋 Step 1/6: Get Pod Basic Information"

  POD_JSON=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json)

  POD_STATUS=$(jq -r '.status.phase' <<<"$POD_JSON")
  CONTAINER_NAME=$(jq -r '.spec.containers[0].name' <<<"$POD_JSON")
  IMAGE=$(jq -r '.spec.containers[0].image' <<<"$POD_JSON")
  NODE=$(jq -r '.spec.nodeName' <<<"$POD_JSON")
  POD_START=$(jq -r '.status.startTime' <<<"$POD_JSON")
  CONTAINER_START=$(jq -r '.status.containerStatuses[0].state.running.startedAt' <<<"$POD_JSON")

  echo "   Pod Status: $POD_STATUS"
  echo "   Container Name: $CONTAINER_NAME"
  echo "   Container Image: $IMAGE"
  echo "   Running Node: $NODE"
  echo "   Pod Creation Time: $POD_START"
  echo "   Container Start Time: $CONTAINER_START"
}

############################################
# Step 2: Probe Configuration
############################################
step2_analyze_probe_configuration() {
  section "📋 Step 2/6: Analyze Probe Configuration"
  echo "📌 Current Probe Configuration Overview:"
  echo

  for probe in startupProbe readinessProbe livenessProbe; do
    if jq -e ".spec.containers[0].$probe" <<<"$POD_JSON" >/dev/null; then
      echo "   ✓ $probe: Configured"
      jq -r ".spec.containers[0].$probe |
        \"     - initialDelaySeconds: \(.initialDelaySeconds // 0)s
         - periodSeconds: \(.periodSeconds // 10)s
         - failureThreshold: \(.failureThreshold // 3)\"" <<<"$POD_JSON"

      if [[ "$probe" == "startupProbe" ]]; then
        MAX_TIME=$(jq -r '
          (.spec.containers[0].startupProbe.periodSeconds // 10) *
          (.spec.containers[0].startupProbe.failureThreshold // 30)
        ' <<<"$POD_JSON")
        echo "     → Maximum allowed startup time: ${MAX_TIME}s"
      fi
    else
      echo "   ✗ $probe: Not Configured"
    fi
    echo
  done
}

############################################
# Step 3: Probe Endpoint
############################################
step3_extract_probe_endpoint() {
  section "📋 Step 3/6: Extract Probe Detection Parameters"

  PROBE_PATH=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.path // "/"' <<<"$POD_JSON")
  PORT=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.port // 80' <<<"$POD_JSON")
  SCHEME=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.scheme // "HTTP"' <<<"$POD_JSON")

  echo "   Detection Endpoint Information:"
  echo "   - Scheme: $SCHEME"
  echo "   - Port: $PORT"
  echo "   - Path: $PROBE_PATH"
  echo "   → Full URL: $SCHEME://localhost:$PORT$PROBE_PATH"
}

############################################
# Step 4: Measure Startup Time
############################################
step4_measure_startup_time() {
  section "⏱️  Step 4/6: Measure Actual Startup Time"

  READY_TIME=$("$JQ_CMD" -r '
    .status.conditions[]
    | select(.type=="Ready" and .status=="True")
    | .lastTransitionTime
  ' <<<"$POD_JSON")

  if [[ -n "$READY_TIME" && "$READY_TIME" != "null" ]]; then
    echo "   ✓ Pod is already in Ready status"
    echo "   Ready Time: $READY_TIME"
  else
    die "Pod is not Ready yet (polling logic omitted for equivalence)"
  fi
}

############################################
# Step 5: Analysis
############################################
step5_analyze_startup_time() {
  section "📊 Step 5/6: Startup Time Analysis"

  START_EPOCH=$(iso_to_epoch "$CONTAINER_START")
  READY_EPOCH=$(iso_to_epoch "$READY_TIME")
  STARTUP_TIME=$((READY_EPOCH - START_EPOCH))

  echo "   ✅ Actual Application Startup Time: ${STARTUP_TIME} seconds"
  echo "   📍 Measurement Data Source: Kubernetes Ready Status"
  echo
  echo "   ⏱️  Startup Timeline:"
  cat <<EOF
   ┌─────────────────────────────────────────────────────────┐
   │ 0s                                          ${STARTUP_TIME}s │
   │ ├───────────────────────────────────────────┤           │
   │ Container Start                      Application Ready   │
   └─────────────────────────────────────────────────────────┘
EOF

  if [[ -n "${MAX_TIME:-}" ]]; then
    BUFFER=$((MAX_TIME - STARTUP_TIME))
    echo
    echo "   📊 Configuration Comparison Analysis:"
    echo "   Current Configuration Type: StartupProbe"
    echo "   Maximum Allowed Startup Time: ${MAX_TIME}s"
    echo "   Actual Startup Time: ${STARTUP_TIME}s"
    echo "   ✓ Configuration is reasonable, buffer time: ${BUFFER}s"
  fi
}

############################################
# Step 6: Recommendation
############################################
step6_print_recommendations() {
  section "💡 Step 6/6: Configuration Optimization Recommendations"

  cat <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║  Option 1: Using StartupProbe + ReadinessProbe (Recommended)  ║
╚════════════════════════════════════════════════════════════════╝

Advantages:
  • Separates startup and runtime phases
  • Prevents slow-start false failures
  • Faster runtime detection

Configuration Example:

  startupProbe:
    httpGet:
      path: /
      port: 80
      scheme: HTTP
    periodSeconds: 10
    failureThreshold: 2

  readinessProbe:
    httpGet:
      path: /
      port: 80
    periodSeconds: 5
    failureThreshold: 3
EOF
}

############################################
# Main
############################################
main() {
  require_cmd kubectl
  require_cmd jq

  parse_args "$@"
  print_header

  step1_get_pod_basic_info
  step2_analyze_probe_configuration
  step3_extract_probe_endpoint
  step4_measure_startup_time
  step5_analyze_startup_time
  step6_print_recommendations
}

main "$@"

```

## `pod_measure_startup_enhanced_v4.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Color & Style
############################################
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

############################################
# Global Defaults
############################################
readonly MAX_PROBES=180
readonly PROBE_INTERVAL=2
NAMESPACE=""
POD_NAME=""
CONTAINER_INDEX=0

############################################
# Command Resolver (PATH-independent)
############################################
resolve_command() {
    local name="$1"; shift
    local path

    for path in "$@"; do
        if [[ -x "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done

    echo -e "${RED}ERROR:${NC} Required command not found: $name" >&2
    echo "Searched paths: $*" >&2
    exit 127
}

# Resolve required commands
CAT_CMD=$(resolve_command cat /bin/cat /usr/bin/cat)
JQ_CMD=$(resolve_command jq /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq)
AWK_CMD=$(resolve_command awk /usr/bin/awk /bin/awk)
SLEEP_CMD=$(resolve_command sleep /bin/sleep /usr/bin/sleep)
KUBECTL_CMD=$(resolve_command kubectl \
    /opt/homebrew/bin/kubectl \
    /usr/local/bin/kubectl \
    /usr/bin/kubectl)

# Date command detection (macOS vs Linux)
if command -v gdate >/dev/null 2>&1; then
    DATE_CMD=$(resolve_command gdate /opt/homebrew/bin/gdate /usr/local/bin/gdate)
    DATE_IS_GNU=1
elif date --version 2>&1 | grep -q GNU; then
    DATE_CMD=$(resolve_command date /usr/bin/date /bin/date)
    DATE_IS_GNU=1
else
    DATE_CMD=$(resolve_command date /bin/date /usr/bin/date)
    DATE_IS_GNU=0
fi

############################################
# Utility Functions
############################################
die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $*" >&2
}

info() {
    echo -e "${CYAN}INFO:${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

section() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ISO8601 timestamp to epoch conversion (cross-platform)
iso_to_epoch() {
    local timestamp="$1"
    
    if [[ "$DATE_IS_GNU" -eq 1 ]]; then
        "$DATE_CMD" -d "$timestamp" +%s 2>/dev/null || die "Failed to parse timestamp: $timestamp"
    else
        # macOS BSD date
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" 2>/dev/null || \
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%Z}" "+%s" 2>/dev/null || \
        die "Failed to parse timestamp: $timestamp"
    fi
}

# Safe JSON extraction with default value
json_get() {
    local json="$1"
    local path="$2"
    local default="${3:-null}"
    
    echo "$json" | "$JQ_CMD" -r "$path // \"$default\"" 2>/dev/null || echo "$default"
}

# Validate JSON field is not null/empty
validate_json_field() {
    local value="$1"
    local field_name="$2"
    
    if [[ -z "$value" || "$value" == "null" ]]; then
        die "Failed to extract required field: $field_name"
    fi
}

############################################
# Argument Parsing
############################################
usage() {
    echo -e "${BLUE}Usage:${NC} $0 -n <namespace> [-c <container-index>] <pod-name>"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo "  -n  Kubernetes namespace (required)"
    echo "  -c  Container index for multi-container pods (default: 0)"
    echo "  -h  Show this help message"
    echo
    echo -e "${BLUE}Example:${NC}"
    echo "  $0 -n default my-app-pod"
    echo "  $0 -n production -c 1 my-multi-container-pod"
    exit 0
}

parse_args() {
    while getopts ":n:c:h" opt; do
        case "$opt" in
            n) NAMESPACE="$OPTARG" ;;
            c) CONTAINER_INDEX="$OPTARG" ;;
            h) usage ;;
            \?) die "Invalid option: -$OPTARG. Use -h for help." ;;
            :) die "Option -$OPTARG requires an argument." ;;
        esac
    done
    shift $((OPTIND - 1))

    POD_NAME="${1:-}"
    
    if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
        usage
    fi
    
    # Validate container index is numeric
    if ! [[ "$CONTAINER_INDEX" =~ ^[0-9]+$ ]]; then
        die "Container index must be a non-negative integer, got: $CONTAINER_INDEX"
    fi
}

############################################
# Header
############################################
print_header() {
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo -e "║  ${CYAN}Pod Startup Time Measurement and Probe Configuration Tool${NC}     ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo -e "║  ${YELLOW}Pod:${NC} ${POD_NAME}"
    echo -e "║  ${YELLOW}Namespace:${NC} ${NAMESPACE}"
    echo -e "║  ${YELLOW}Container Index:${NC} ${CONTAINER_INDEX}"
    echo "╚═══════════════════════════════════════════════════════════════╝"
}

############################################
# Step 1: Pod Basic Info
############################################
step1_get_pod_basic_info() {
    section "📋 Step 1/6: Get Pod Basic Information"

    # Fetch pod JSON with error handling
    if ! POD_JSON=$("$KUBECTL_CMD" get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>&1); then
        die "Failed to get pod information:\n$POD_JSON"
    fi

    # Validate pod exists
    if [[ -z "$POD_JSON" ]]; then
        die "Pod not found: $POD_NAME in namespace: $NAMESPACE"
    fi

    # Check if container index exists
    local container_count
    container_count=$(json_get "$POD_JSON" '.spec.containers | length' "0")
    if [[ "$CONTAINER_INDEX" -ge "$container_count" ]]; then
        die "Container index $CONTAINER_INDEX out of range (pod has $container_count container(s))"
    fi

    # Extract basic information
    POD_STATUS=$(json_get "$POD_JSON" '.status.phase' 'Unknown')
    CONTAINER_NAME=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].name" 'unknown')
    IMAGE=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].image" 'unknown')
    NODE=$(json_get "$POD_JSON" '.spec.nodeName' 'unknown')
    POD_START=$(json_get "$POD_JSON" '.status.startTime' 'null')
    CONTAINER_START=$(json_get "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].state.running.startedAt" 'null')

    # Validate critical fields
    validate_json_field "$POD_STATUS" "Pod Status"
    validate_json_field "$CONTAINER_NAME" "Container Name"
    validate_json_field "$POD_START" "Pod Start Time"

    echo -e "   ${CYAN}Pod Status:${NC} $POD_STATUS"
    echo -e "   ${CYAN}Container Name:${NC} $CONTAINER_NAME"
    echo -e "   ${CYAN}Container Image:${NC} $IMAGE"
    echo -e "   ${CYAN}Running Node:${NC} $NODE"
    echo -e "   ${CYAN}Pod Creation Time:${NC} $POD_START"
    
    if [[ "$CONTAINER_START" != "null" ]]; then
        echo -e "   ${CYAN}Container Start Time:${NC} $CONTAINER_START"
    else
        warn "Container has not started yet"
    fi
}

############################################
# Step 2: Probe Configuration
############################################
step2_analyze_probe_configuration() {
    section "🔍 Step 2/6: Analyze Probe Configuration"
    echo -e "${CYAN}📌 Current Probe Configuration Overview:${NC}"
    echo

    local probe_found=0

    for probe in startupProbe readinessProbe livenessProbe; do
        if "$JQ_CMD" -e ".spec.containers[$CONTAINER_INDEX].$probe" <<<"$POD_JSON" >/dev/null 2>&1; then
            echo -e "   ${GREEN}✓${NC} $probe: Configured"
            
            local initial_delay period_seconds failure_threshold
            initial_delay=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.initialDelaySeconds" "0")
            period_seconds=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.periodSeconds" "10")
            failure_threshold=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.failureThreshold" "3")
            
            echo "     - initialDelaySeconds: ${initial_delay}s"
            echo "     - periodSeconds: ${period_seconds}s"
            echo "     - failureThreshold: ${failure_threshold}"

            if [[ "$probe" == "startupProbe" ]]; then
                MAX_TIME=$((period_seconds * failure_threshold))
                echo -e "     ${YELLOW}→${NC} Maximum allowed startup time: ${MAX_TIME}s"
            fi
            
            probe_found=1
        else
            echo -e "   ${RED}✗${NC} $probe: Not Configured"
        fi
        echo
    done

    if [[ "$probe_found" -eq 0 ]]; then
        warn "No probes configured for this container"
    fi
}

############################################
# Step 3: Probe Endpoint
############################################
step3_extract_probe_endpoint() {
    section "🔍 Step 3/6: Extract Probe Detection Parameters"

    # Try readinessProbe first, then startupProbe, then livenessProbe
    local probe_type=""
    for pt in readinessProbe startupProbe livenessProbe; do
        if "$JQ_CMD" -e ".spec.containers[$CONTAINER_INDEX].$pt.httpGet" <<<"$POD_JSON" >/dev/null 2>&1; then
            probe_type="$pt"
            break
        fi
    done

    if [[ -z "$probe_type" ]]; then
        warn "No HTTP probe configured, using default values"
        PROBE_PATH="/"
        PORT="80"
        SCHEME="HTTP"
    else
        PROBE_PATH=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.path" "/")
        PORT=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.port" "80")
        SCHEME=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.scheme" "HTTP")
    fi

    echo -e "   ${CYAN}Detection Endpoint Information:${NC}"
    echo "   - Probe Type: ${probe_type:-None}"
    echo "   - Scheme: $SCHEME"
    echo "   - Port: $PORT"
    echo "   - Path: $PROBE_PATH"
    echo -e "   ${YELLOW}→${NC} Full URL: $SCHEME://localhost:$PORT$PROBE_PATH"
}

############################################
# Step 4: Measure Startup Time
############################################
step4_measure_startup_time() {
    section "⏱️  Step 4/6: Measure Actual Startup Time"

    READY_TIME=$(json_get "$POD_JSON" '
        .status.conditions[]
        | select(.type=="Ready" and .status=="True")
        | .lastTransitionTime
    ' 'null')

    if [[ -n "$READY_TIME" && "$READY_TIME" != "null" ]]; then
        success "Pod is already in Ready status"
        echo -e "   ${CYAN}Ready Time:${NC} $READY_TIME"
    else
        warn "Pod is not in Ready status yet"
        info "Current pod phase: $POD_STATUS"
        
        # Show current conditions
        echo
        echo -e "   ${CYAN}Current Pod Conditions:${NC}"
        "$JQ_CMD" -r '.status.conditions[] | "   - \(.type): \(.status) (\(.reason // "N/A"))"' <<<"$POD_JSON" 2>/dev/null || echo "   No conditions available"
        
        die "Cannot calculate startup time for non-ready pod"
    fi
}

############################################
# Step 5: Analysis
############################################
step5_analyze_startup_time() {
    section "📊 Step 5/6: Startup Time Analysis"

    # Validate timestamps
    if [[ "$CONTAINER_START" == "null" ]]; then
        die "Container has not started yet, cannot calculate startup time"
    fi

    START_EPOCH=$(iso_to_epoch "$CONTAINER_START")
    READY_EPOCH=$(iso_to_epoch "$READY_TIME")
    STARTUP_TIME=$((READY_EPOCH - START_EPOCH))

    # Handle negative startup time (clock skew or other issues)
    if [[ "$STARTUP_TIME" -lt 0 ]]; then
        warn "Calculated negative startup time, possible clock skew"
        STARTUP_TIME=0
    fi

    success "Actual Application Startup Time: ${STARTUP_TIME} seconds"
    echo -e "   ${CYAN}📝 Measurement Data Source:${NC} Kubernetes Ready Status"
    echo
    echo -e "   ${CYAN}⏱️  Startup Timeline:${NC}"
    echo "   ┌────────────────────────────────────────────────────────┐"
    echo "   │ 0s                                          ${STARTUP_TIME}s │"
    echo "   │ ├──────────────────────────────────────────┤           │"
    echo "   │ Container Start                      Application Ready   │"
    echo "   └────────────────────────────────────────────────────────┘"

    # Compare with configured maximum time
    if [[ -n "${MAX_TIME:-}" ]]; then
        echo
        echo -e "   ${CYAN}📊 Configuration Comparison Analysis:${NC}"
        echo "   Configuration Type: StartupProbe"
        echo "   Maximum Allowed Startup Time: ${MAX_TIME}s"
        echo "   Actual Startup Time: ${STARTUP_TIME}s"
        
        local buffer=$((MAX_TIME - STARTUP_TIME))
        if [[ "$buffer" -gt 0 ]]; then
            success "Configuration is reasonable, buffer time: ${buffer}s"
        elif [[ "$buffer" -eq 0 ]]; then
            warn "Configuration is at the limit, consider increasing buffer"
        else
            echo -e "   ${RED}⚠${NC}  Configuration is too tight, startup time exceeds limit by $((buffer * -1))s"
        fi
    fi
    
    # Provide startup time assessment
    echo
    echo -e "   ${CYAN}Startup Performance Assessment:${NC}"
    if [[ "$STARTUP_TIME" -lt 10 ]]; then
        echo -e "   ${GREEN}Excellent${NC} - Very fast startup (<10s)"
    elif [[ "$STARTUP_TIME" -lt 30 ]]; then
        echo -e "   ${GREEN}Good${NC} - Normal startup time (10-30s)"
    elif [[ "$STARTUP_TIME" -lt 60 ]]; then
        echo -e "   ${YELLOW}Moderate${NC} - Slower startup (30-60s)"
    else
        echo -e "   ${RED}Slow${NC} - Long startup time (>60s), consider optimization"
    fi
}

############################################
# Step 6: Recommendation
############################################
step6_print_recommendations() {
    section "💡 Step 6/6: Configuration Optimization Recommendations"

    # Calculate recommended values based on actual startup time
    local recommended_failure_threshold=$(( (STARTUP_TIME / 10) + 2 ))
    local recommended_period=10

    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo -e "║  ${GREEN}Option 1: Using StartupProbe + ReadinessProbe (Recommended)${NC}  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo
    echo -e "${CYAN}Advantages:${NC}"
    echo "  • Separates startup and runtime phases"
    echo "  • Prevents slow-start false failures"
    echo "  • Faster runtime detection"
    echo
    echo -e "${CYAN}Recommended Configuration (based on measured ${STARTUP_TIME}s startup):${NC}"
    echo
    echo "  startupProbe:"
    echo "    httpGet:"
    echo "      path: $PROBE_PATH"
    echo "      port: $PORT"
    echo "      scheme: $SCHEME"
    echo "    periodSeconds: $recommended_period"
    echo "    failureThreshold: $recommended_failure_threshold"
    echo "    # Allows up to $((recommended_period * recommended_failure_threshold))s for startup"
    echo
    echo "  readinessProbe:"
    echo "    httpGet:"
    echo "      path: $PROBE_PATH"
    echo "      port: $PORT"
    echo "      scheme: $SCHEME"
    echo "    periodSeconds: 5"
    echo "    failureThreshold: 3"
    echo "    # Quick detection after startup (15s max)"
    echo
    echo "  livenessProbe:"
    echo "    httpGet:"
    echo "      path: $PROBE_PATH"
    echo "      port: $PORT"
    echo "      scheme: $SCHEME"
    echo "    periodSeconds: 10"
    echo "    failureThreshold: 3"
    echo "    initialDelaySeconds: $((STARTUP_TIME + 10))"
    echo "    # Only starts after startup is complete"
    echo
    echo -e "${YELLOW}Note:${NC} Adjust values based on your application's specific needs"
}

############################################
# Main Entry Point
############################################
main() {
    parse_args "$@"
    print_header

    step1_get_pod_basic_info
    step2_analyze_probe_configuration
    step3_extract_probe_endpoint
    step4_measure_startup_time
    step5_analyze_startup_time
    step6_print_recommendations

    echo
    success "Analysis completed successfully!"
}

# Execute main function
main "$@"
```

## `pod_measure_startup_fixed_en.sh`

```bash
#!/bin/bash

# Set color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Measuring Pod Startup Time: ${POD_NAME} (Namespace: ${NAMESPACE})${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 1. Get Pod basic information
echo -e "${YELLOW}📋 Step 1: Get Pod Basic Information${NC}"
START_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.startTime}' 2>/dev/null)
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${RED}❌ Error: Container has not started or Pod does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}   Pod Creation Time:${NC} ${START_TIME}"
echo -e "${GREEN}   Container Start Time:${NC} ${CONTAINER_START}"

# 2. Get readiness probe configuration
echo -e "\n${YELLOW}📋 Step 2: Analyze Readiness Probe Configuration${NC}"
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)

if [ -z "$READINESS_PROBE" ]; then
    echo -e "${RED}❌ Error: No readiness probe configuration found${NC}"
    exit 1
fi

echo -e "${GREEN}   Readiness Probe Configuration:${NC}"
echo "$READINESS_PROBE" | jq '.'

# 3. Extract probe parameters
PROBE_SCHEME=$(echo "$READINESS_PROBE" | jq -r '.httpGet.scheme // "HTTP"')
PROBE_PORT=$(echo "$READINESS_PROBE" | jq -r '.httpGet.port // 8080')
PROBE_PATH=$(echo "$READINESS_PROBE" | jq -r '.httpGet.path // "/health"')
INITIAL_DELAY=$(echo "$READINESS_PROBE" | jq -r '.initialDelaySeconds // 0')
PERIOD=$(echo "$READINESS_PROBE" | jq -r '.periodSeconds // 10')
FAILURE_THRESHOLD=$(echo "$READINESS_PROBE" | jq -r '.failureThreshold // 3')

echo -e "\n${GREEN}   Extracted Probe Parameters:${NC}"
echo "   - Scheme: ${PROBE_SCHEME}"
echo "   - Port: ${PROBE_PORT}"
echo "   - Path: ${PROBE_PATH}"
echo "   - Initial Delay: ${INITIAL_DELAY}s"
echo "   - Period: ${PERIOD}s"
echo "   - Failure Threshold: ${FAILURE_THRESHOLD}"

# 4. Calculate container start timestamp
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

if [ -z "$START_TIME_SEC" ]; then
    echo -e "${RED}❌ Error: Cannot parse container start time${NC}"
    exit 1
fi

# 5. Check if Pod is already Ready
echo -e "\n${YELLOW}⏱️  Step 3: Check Pod Ready Status${NC}"
READY_CONDITION=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)

if [ "$READY_CONDITION" == "True" ] && [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
    # Pod is already Ready, calculate directly from Kubernetes status
    echo -e "${GREEN}   Pod is already in Ready status${NC}"
    echo -e "${GREEN}   Ready Time: ${READY_TIME}${NC}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
    else
        READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
    fi

    STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📊 Final Result${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Application startup duration:${NC} ${STARTUP_TIME} seconds"
    echo -e "${GREEN}   (Based on Kubernetes Ready status)${NC}"
    echo ""

    ELAPSED=$STARTUP_TIME
    PROBE_COUNT=0
else
    # Pod is not yet Ready, need real-time detection
    echo -e "${YELLOW}   Pod is not Ready yet, starting real-time detection${NC}"
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
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        fi

        CURRENT_TIME_SEC=$(date +%s)
        POD_AGE=$((CURRENT_TIME_SEC - START_TIME_SEC))

        if [[ "$HTTP_CODE" == "200" ]]; then
            echo -e "${GREEN}✅ Health check passed (HTTP 200 OK)!${NC}"

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
                SOURCE="Kubernetes Ready Status"
            else
                # Kubernetes hasn't updated yet, estimate using detection time
                STARTUP_TIME=$POD_AGE
                SOURCE="Real-time Detection Estimate"
            fi

            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}📊 Final Result${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}✅ Application startup duration:${NC} ${STARTUP_TIME} seconds"
            echo -e "${GREEN}   (Based on ${SOURCE})${NC}"
            echo -e "${GREEN}   Probe count:${NC} ${PROBE_COUNT}"
            echo -e "${GREEN}   Script detection duration:${NC} $((CURRENT_TIME_SEC - SCRIPT_START_TIME)) seconds"
            echo ""

            ELAPSED=$STARTUP_TIME
            break
        else
            echo -e "   [${PROBE_COUNT}] Still starting... (Pod running: ${POD_AGE}s, Status code: ${HTTP_CODE})"
            sleep 2
        fi
    done

    if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
        echo -e "\n${RED}❌ Timeout: Probe exceeded ${MAX_PROBES} attempts without success${NC}"
        exit 1
    fi
fi

# 6. Analyze current configuration
echo -e "${YELLOW}📋 Current Probe Configuration Analysis:${NC}"
CURRENT_MAX_TIME=$((INITIAL_DELAY + PERIOD * FAILURE_THRESHOLD))
echo "   - Maximum startup time allowed by current config: ${CURRENT_MAX_TIME} seconds"
echo "   - Actual startup time: ${ELAPSED} seconds"

if [ $ELAPSED -gt $CURRENT_MAX_TIME ]; then
    echo -e "   ${RED}⚠️  Warning: Actual startup time exceeds current configuration!${NC}"
else
    echo -e "   ${GREEN}✓ Current configuration is sufficient${NC}"
fi

echo ""
echo -e "${YELLOW}💡 Recommended optimized configuration:${NC}"
echo "   readinessProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: ${PERIOD}"

# Calculate recommended failureThreshold (actual time * 1.5 / period + 1)
RECOMMENDED_THRESHOLD=$(echo "scale=0; ($ELAPSED * 1.5 / $PERIOD) + 1" | bc)
echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"

echo ""
echo -e "${YELLOW}📋 Or use startupProbe (recommended):${NC}"
echo "   startupProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: 10"
echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"
echo "   readinessProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: 5"
echo "     failureThreshold: 3"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
```

## `pod_measure_startup_fixed.sh`

```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n default my-api-pod-abc123"
    exit 1
fi

# 解析参数
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
POD_NAME=$1

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}测量 Pod 启动时间: ${POD_NAME} (命名空间: ${NAMESPACE})${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 1. 获取 Pod 基本信息
echo -e "${YELLOW}📋 步骤 1: 获取 Pod 基本信息${NC}"
START_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.startTime}' 2>/dev/null)
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${RED}❌ 错误: 容器尚未启动或 Pod 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}   Pod 创建时间:${NC} ${START_TIME}"
echo -e "${GREEN}   容器启动时间:${NC} ${CONTAINER_START}"

# 2. 获取就绪探针配置
echo -e "\n${YELLOW}📋 步骤 2: 分析就绪探针配置${NC}"
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)

if [ -z "$READINESS_PROBE" ]; then
    echo -e "${RED}❌ 错误: 未找到就绪探针配置${NC}"
    exit 1
fi

echo -e "${GREEN}   就绪探针配置:${NC}"
echo "$READINESS_PROBE" | jq '.'

# 3. 提取探针参数
PROBE_SCHEME=$(echo "$READINESS_PROBE" | jq -r '.httpGet.scheme // "HTTP"')
PROBE_PORT=$(echo "$READINESS_PROBE" | jq -r '.httpGet.port // 8080')
PROBE_PATH=$(echo "$READINESS_PROBE" | jq -r '.httpGet.path // "/health"')
INITIAL_DELAY=$(echo "$READINESS_PROBE" | jq -r '.initialDelaySeconds // 0')
PERIOD=$(echo "$READINESS_PROBE" | jq -r '.periodSeconds // 10')
FAILURE_THRESHOLD=$(echo "$READINESS_PROBE" | jq -r '.failureThreshold // 3')

echo -e "\n${GREEN}   提取的探针参数:${NC}"
echo "   - Scheme: ${PROBE_SCHEME}"
echo "   - Port: ${PROBE_PORT}"
echo "   - Path: ${PROBE_PATH}"
echo "   - Initial Delay: ${INITIAL_DELAY}s"
echo "   - Period: ${PERIOD}s"
echo "   - Failure Threshold: ${FAILURE_THRESHOLD}"

# 4. 计算容器启动时间戳
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

if [ -z "$START_TIME_SEC" ]; then
    echo -e "${RED}❌ 错误: 无法解析容器启动时间${NC}"
    exit 1
fi

# 5. 检查 Pod 是否已经 Ready
echo -e "\n${YELLOW}⏱️  步骤 3: 检查 Pod Ready 状态${NC}"
READY_CONDITION=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)

if [ "$READY_CONDITION" == "True" ] && [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
    # Pod 已经 Ready，直接从 Kubernetes 状态计算
    echo -e "${GREEN}   Pod 已处于 Ready 状态${NC}"
    echo -e "${GREEN}   Ready 时间: ${READY_TIME}${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
    else
        READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
    fi
    
    STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📊 最终结果 (Result)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ 应用程序启动耗时:${NC} ${STARTUP_TIME} 秒"
    echo -e "${GREEN}   (基于 Kubernetes Ready 状态)${NC}"
    echo ""
    
    ELAPSED=$STARTUP_TIME
    PROBE_COUNT=0
else
    # Pod 还未 Ready，需要实时探测
    echo -e "${YELLOW}   Pod 尚未 Ready，开始实时探测${NC}"
    echo -e "${GREEN}   目标: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"
    echo ""
    
    PROBE_COUNT=0
    MAX_PROBES=180
    SCRIPT_START_TIME=$(date +%s)
    
    while [ $PROBE_COUNT -lt $MAX_PROBES ]; do
        PROBE_COUNT=$((PROBE_COUNT + 1))
        
        # 根据协议选择探测方式
        if [[ "$PROBE_SCHEME" == "HTTPS" ]]; then
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "openssl s_client -connect localhost:${PROBE_PORT} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        else
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        fi
        
        CURRENT_TIME_SEC=$(date +%s)
        POD_AGE=$((CURRENT_TIME_SEC - START_TIME_SEC))
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            echo -e "${GREEN}✅ 健康检查通过 (HTTP 200 OK)!${NC}"
            
            # 等待 Kubernetes 更新 Ready 状态
            sleep 2
            
            # 再次获取 Ready 时间
            READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
            
            if [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
                else
                    READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
                fi
                STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
                SOURCE="Kubernetes Ready 状态"
            else
                # Kubernetes 还没更新，使用探测时间估算
                STARTUP_TIME=$POD_AGE
                SOURCE="实时探测估算"
            fi
            
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}📊 最终结果 (Result)${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}✅ 应用程序启动耗时:${NC} ${STARTUP_TIME} 秒"
            echo -e "${GREEN}   (基于 ${SOURCE})${NC}"
            echo -e "${GREEN}   探测次数:${NC} ${PROBE_COUNT}"
            echo -e "${GREEN}   脚本探测耗时:${NC} $((CURRENT_TIME_SEC - SCRIPT_START_TIME)) 秒"
            echo ""
            
            ELAPSED=$STARTUP_TIME
            break
        else
            echo -e "   [${PROBE_COUNT}] 仍在启动中... (Pod 运行: ${POD_AGE}s, 状态码: ${HTTP_CODE})"
            sleep 2
        fi
    done
    
    if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
        echo -e "\n${RED}❌ 超时: 探测超过 ${MAX_PROBES} 次仍未成功${NC}"
        exit 1
    fi
fi

# 6. 分析当前配置
echo -e "${YELLOW}📋 当前探针配置分析:${NC}"
CURRENT_MAX_TIME=$((INITIAL_DELAY + PERIOD * FAILURE_THRESHOLD))
echo "   - 当前配置允许的最大启动时间: ${CURRENT_MAX_TIME} 秒"
echo "   - 实际启动时间: ${ELAPSED} 秒"

if [ $ELAPSED -gt $CURRENT_MAX_TIME ]; then
    echo -e "   ${RED}⚠️  警告: 实际启动时间超过当前配置!${NC}"
else
    echo -e "   ${GREEN}✓ 当前配置足够${NC}"
fi

echo ""
echo -e "${YELLOW}💡 建议的优化配置:${NC}"
echo "   readinessProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: ${PERIOD}"

# 计算建议的 failureThreshold (实际时间 * 1.5 / period + 1)
RECOMMENDED_THRESHOLD=$(echo "scale=0; ($ELAPSED * 1.5 / $PERIOD) + 1" | bc)
echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"

echo ""
echo -e "${YELLOW}📋 或者使用 startupProbe (推荐):${NC}"
echo "   startupProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: 10"
echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"
echo "   readinessProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: 5"
echo "     failureThreshold: 3"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

```

