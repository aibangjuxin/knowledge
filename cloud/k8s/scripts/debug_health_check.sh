#!/bin/bash
# Debug script to test health check

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/pod_health_check_lib.sh"

POD_NAME="$1"
NAMESPACE="$2"

if [ -z "$POD_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "Usage: $0 <pod-name> <namespace>"
  exit 1
fi

echo "=== Debug Health Check ==="
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Get probe config
echo "1. Getting probe configuration..."
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)
echo "Probe config: $READINESS_PROBE"
echo ""

# Extract endpoint
echo "2. Extracting endpoint..."
PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
echo "Endpoint: $PROBE_ENDPOINT"
read SCHEME PORT PATH <<<"$PROBE_ENDPOINT"
echo "  Scheme: $SCHEME"
echo "  Port: $PORT"
echo "  Path: $PATH"
echo ""

# Test direct kubectl exec (like original script)
echo "3. Testing direct kubectl exec (original method)..."
HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PATH}" |
  kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c \
    "timeout 2 nc localhost ${PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
echo "Status line: '$HTTP_STATUS_LINE'"
HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | /usr/bin/awk '{print $2}')
echo "Status code: '$HTTP_CODE'"
echo ""

# Test using library function
echo "4. Testing library function..."
echo "Command paths:"
echo "  AWK_CMD: $AWK_CMD"
echo "  DATE_CMD: $DATE_CMD"
echo "  SLEEP_CMD: $SLEEP_CMD"
echo ""

STATUS=$(check_pod_health "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH")
RESULT=$?
echo "Library result: $STATUS (return code: $RESULT)"
echo ""

# Test with verbose output
echo "5. Testing with verbose kubectl exec..."
printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PATH}" |
  /opt/homebrew/bin/kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c \
    "timeout 2 nc localhost ${PORT}" 2>&1 | /usr/bin/head -10
echo ""

echo "=== Debug Complete ==="
