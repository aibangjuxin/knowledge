#!/bin/bash
# Minimal test - exactly like original script

POD_NAME="nginx-deployment-854b5bc678-zq4kb"
NAMESPACE="lex"
PROBE_PATH="/"
PROBE_PORT="80"

echo "=== Minimal Test (Exact Copy of Original) ==="
echo ""

echo "Test 1: Direct command (like original script)"
HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
    kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
if [ -z "$HTTP_CODE" ]; then
    HTTP_CODE="000"
fi

echo "Status Line: '$HTTP_STATUS_LINE'"
echo "Status Code: '$HTTP_CODE'"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ SUCCESS"
else
    echo "✗ FAILED"
fi
