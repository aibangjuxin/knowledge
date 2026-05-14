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
    echo -e "${RED}❌ Error: Unable to parse container start time${NC}"
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

    # Verify actual health check endpoint status
    echo -e "\n${YELLOW}🔍 Step 3.1: Verify Health Check Endpoint${NC}"
    echo -e "${GREEN}   Target: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"

    # Choose detection method based on protocol
    if [[ "$PROBE_SCHEME" == "HTTPS" ]]; then
        HEALTH_CHECK_RESULT=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
            kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "openssl s_client -connect localhost:${PROBE_PORT} -quiet 2>&1" 2>/dev/null || echo "")
        HTTP_STATUS_LINE=$(echo "$HEALTH_CHECK_RESULT" | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1)
        HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
        HTTP_MESSAGE=$(echo "$HTTP_STATUS_LINE" | cut -d' ' -f3-)
        RESPONSE_BODY=$(echo "$HEALTH_CHECK_RESULT" | sed -n '/^{/,/^}/p' | head -1)
    else
        HEALTH_CHECK_RESULT=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
            kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost ${PROBE_PORT} 2>&1" 2>/dev/null || echo "")
        HTTP_STATUS_LINE=$(echo "$HEALTH_CHECK_RESULT" | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1)
        HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
        HTTP_MESSAGE=$(echo "$HTTP_STATUS_LINE" | cut -d' ' -f3-)
        RESPONSE_BODY=$(echo "$HEALTH_CHECK_RESULT" | sed -n '/^{/,/^}/p' | head -1)
    fi

    if [ -z "$HTTP_CODE" ]; then
        HTTP_CODE="000"
        HTTP_MESSAGE="Connection Failed"
    fi

    # Display health check results
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo -e "${GREEN}   ✅ Health Check Status: HTTP ${HTTP_CODE} ${HTTP_MESSAGE}${NC}"
    else
        echo -e "${RED}   ⚠️  Health Check Status: HTTP ${HTTP_CODE} ${HTTP_MESSAGE}${NC}"
    fi

    if [ -n "$RESPONSE_BODY" ]; then
        echo -e "${GREEN}   📄 Response Content: ${RESPONSE_BODY}${NC}"
    fi

    # Get more Pod runtime information
    echo -e "\n${YELLOW}📊 Step 3.2: Get Pod Runtime Details${NC}"

    # Get container restart count
    RESTART_COUNT=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    echo -e "${GREEN}   Container Restart Count: ${RESTART_COUNT}${NC}"

    # Get all probe statuses
    LIVENESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].livenessProbe}' 2>/dev/null)
    STARTUP_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)

    if [ -n "$LIVENESS_PROBE" ] && [ "$LIVENESS_PROBE" != "null" ]; then
        LIVENESS_PATH=$(echo "$LIVENESS_PROBE" | jq -r '.httpGet.path // "N/A"')
        echo -e "${GREEN}   Liveness Probe Path: ${LIVENESS_PATH}${NC}"
    fi

    if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
        STARTUP_PATH=$(echo "$STARTUP_PROBE" | jq -r '.httpGet.path // "N/A"')
        STARTUP_FAILURE=$(echo "$STARTUP_PROBE" | jq -r '.failureThreshold // "N/A"')
        echo -e "${GREEN}   Startup Probe Path: ${STARTUP_PATH}${NC}"
        echo -e "${GREEN}   Startup Failure Threshold: ${STARTUP_FAILURE}${NC}"
    fi

    # Get recent events
    echo -e "\n${YELLOW}📋 Step 3.3: Recent Pod Events${NC}"
    RECENT_EVENTS=$(kubectl get events -n ${NAMESPACE} --field-selector involvedObject.name=${POD_NAME} --sort-by='.lastTimestamp' -o json 2>/dev/null | \
        jq -r '.items[-3:] | .[] | "   \(.type): \(.reason) - \(.message)"' 2>/dev/null)

    if [ -n "$RECENT_EVENTS" ]; then
        echo "$RECENT_EVENTS"
    else
        echo -e "${GREEN}   No abnormal events${NC}"
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📊 Final Result${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Application Startup Time:${NC} ${STARTUP_TIME} seconds"
    echo -e "${GREEN}   (Based on Kubernetes Ready Status)${NC}"
    echo -e "${GREEN}   Health Check Endpoint Status:${NC} HTTP ${HTTP_CODE} ${HTTP_MESSAGE}"
    echo -e "${GREEN}   Container Restart Count:${NC} ${RESTART_COUNT}"
    echo ""

    ELAPSED=$STARTUP_TIME
    PROBE_COUNT=0
else
    # Pod is not Ready yet, start real-time probing
    echo -e "${YELLOW}   Pod is not Ready yet, starting real-time probing${NC}"
    echo -e "${GREEN}   Target: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"
    echo ""

    PROBE_COUNT=0
    MAX_PROBES=180
    SCRIPT_START_TIME=$(date +%s)

    while [ $PROBE_COUNT -lt $MAX_PROBES ]; do
        PROBE_COUNT=$((PROBE_COUNT + 1))

        # Choose detection method based on protocol
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
            echo -e "${GREEN}✅ Health Check Passed (HTTP 200 OK)!${NC}"

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
                # Kubernetes hasn't updated yet, estimate using probe time
                STARTUP_TIME=$POD_AGE
                SOURCE="Real-time Probe Estimation"
            fi

            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}📊 Final Result${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}✅ Application Startup Time:${NC} ${STARTUP_TIME} seconds"
            echo -e "${GREEN}   (Based on ${SOURCE})${NC}"
            echo -e "${GREEN}   Probe Count:${NC} ${PROBE_COUNT}"
            echo -e "${GREEN}   Script Probe Duration:${NC} $((CURRENT_TIME_SEC - SCRIPT_START_TIME)) seconds"
            echo ""

            ELAPSED=$STARTUP_TIME
            break
        else
            echo -e "   [${PROBE_COUNT}] Still starting... (Pod Running: ${POD_AGE}s, Status Code: ${HTTP_CODE})"
            sleep 2
        fi
    done

    if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
        echo -e "\n${RED}❌ Timeout: Probing exceeded ${MAX_PROBES} attempts without success${NC}"
        exit 1
    fi
fi

# 6. Analyze current configuration
echo -e "${YELLOW}📋 Current Probe Configuration Analysis:${NC}"
CURRENT_MAX_TIME=$((INITIAL_DELAY + PERIOD * FAILURE_THRESHOLD))
echo "   - Maximum allowed startup time with current config: ${CURRENT_MAX_TIME} seconds"
echo "   - Actual startup time: ${ELAPSED} seconds"

if [ $ELAPSED -gt $CURRENT_MAX_TIME ]; then
    echo -e "   ${RED}⚠️  Warning: Actual startup time exceeds current configuration!${NC}"
else
    echo -e "   ${GREEN}✓ Current configuration is sufficient${NC}"
fi

echo ""
echo -e "${YELLOW}💡 Suggested Optimized Configuration:${NC}"
echo "   readinessProbe:"
echo "     httpGet:"
echo "       path: ${PROBE_PATH}"
echo "       port: ${PROBE_PORT}"
echo "       scheme: ${PROBE_SCHEME}"
echo "     initialDelaySeconds: 0"
echo "     periodSeconds: ${PERIOD}"

# Calculate suggested failureThreshold (actual time * 1.5 / period + 1)
RECOMMENDED_THRESHOLD=$(echo "scale=0; ($ELAPSED * 1.5 / $PERIOD) + 1" | bc)
echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"

echo ""
echo -e "${YELLOW}📋 Or use startupProbe (Recommended):${NC}"
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