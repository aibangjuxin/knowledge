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