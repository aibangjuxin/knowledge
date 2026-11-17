#!/bin/bash
# Simple test to verify Pod health check works

POD_NAME="nginx-deployment-854b5bc678-zq4kb"
NAMESPACE="lex"

echo "=== Simple Health Check Test ==="
echo ""

echo "1. Check if Pod exists..."
kubectl get pod ${POD_NAME} -n ${NAMESPACE} 2>&1 | head -5
echo ""

echo "2. Test direct HTTP request in Pod..."
printf "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
    kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- timeout 2 nc localhost 80 2>&1 | head -5
echo ""

echo "3. Test with grep..."
HTTP_LINE=$(printf "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
    kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost 80 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "FAILED")
echo "HTTP Line: '$HTTP_LINE'"
echo ""

echo "4. Extract status code..."
STATUS_CODE=$(echo "$HTTP_LINE" | awk '{print $2}')
echo "Status Code: '$STATUS_CODE'"
echo ""

if [ "$STATUS_CODE" = "200" ]; then
    echo "✓ SUCCESS: Pod is healthy!"
else
    echo "✗ FAILED: Status code is not 200"
fi
