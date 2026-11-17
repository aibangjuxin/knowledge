#!/bin/bash
# e2e-validation.sh - Complete E2E validation script for Gloo Gateway
# This script validates the end-to-end installation of Gloo Gateway on GKE

set -e

# Configuration
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="minimax-runtime"

echo "========================================"
echo "Gloo Gateway E2E Validation"
echo "========================================"

# Get Gateway IP
echo ""
echo "[1/6] Getting Gateway IP..."
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "${GATEWAY_IP}" ]; then
  echo "ERROR: Gateway IP not assigned"
  echo "Check with: kubectl get svc -n ${GATEWAY_NAMESPACE}"
  exit 1
fi
echo "Gateway IP: ${GATEWAY_IP}"

# Check Gateway Pods
echo ""
echo "[2/6] Checking Gateway Pods..."
kubectl get pods -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway
GATEWAY_PODS=$(kubectl get pods -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${GATEWAY_PODS}" -lt 1 ]; then
  echo "ERROR: Gateway pods not running"
  echo "Check with: kubectl get pods -n ${GATEWAY_NAMESPACE}"
  exit 1
fi
echo "Gateway pods: OK (${GATEWAY_PODS} running)"

# Check Backend Pods
echo ""
echo "[3/6] Checking Backend Pods..."
kubectl get pods -n ${WORKLOAD_NAMESPACE} -l app=minimax-api
BACKEND_PODS=$(kubectl get pods -n ${WORKLOAD_NAMESPACE} -l app=minimax-api --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${BACKEND_PODS}" -lt 1 ]; then
  echo "ERROR: Backend pods not running"
  echo "Check with: kubectl get pods -n ${WORKLOAD_NAMESPACE}"
  exit 1
fi
echo "Backend pods: OK (${BACKEND_PODS} running)"

# Test External Access
echo ""
echo "[4/6] Testing External Access..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${GATEWAY_IP}:8080/api/minimax" 2>/dev/null || echo "000")
echo "HTTP Response Code: ${HTTP_CODE}"

if [ "${HTTP_CODE}" != "200" ]; then
  echo "ERROR: External access failed"
  echo "Expected: 200, Got: ${HTTP_CODE}"
  exit 1
fi
echo "External access: OK"

# Test Health Endpoint
echo ""
echo "[5/6] Testing Health Endpoint..."
HEALTH=$(curl -s "http://${GATEWAY_IP}:8080/healthz" 2>/dev/null || echo "")
echo "Health Response: ${HEALTH}"

if [ "${HEALTH}" != "OK" ]; then
  echo "ERROR: Health check failed"
  echo "Expected: OK, Got: ${HEALTH}"
  exit 1
fi
echo "Health check: OK"

# Test API Response
echo ""
echo "[6/6] Testing API Response..."
API_RESPONSE=$(curl -s "http://${GATEWAY_IP}:8080/api/minimax" 2>/dev/null || echo "")
echo "API Response: ${API_RESPONSE}"

if ! echo "${API_RESPONSE}" | grep -q "minimax-api"; then
  echo "ERROR: Invalid API response"
  echo "Expected response to contain: minimax-api"
  exit 1
fi
echo "API response: OK"

echo ""
echo "========================================"
echo "All E2E Tests Passed!"
echo "========================================"
echo ""
echo "Access your service at: http://${GATEWAY_IP}:8080/"
echo "API endpoint: http://${GATEWAY_IP}:8080/api/minimax"
echo "Health check: http://${GATEWAY_IP}:8080/healthz"
echo ""
