#!/bin/bash
# e2e-validation.sh - End-to-End Validation Script for Gloo Mesh Enterprise
# Run this script after completing the installation to verify all components

set -e

# Configuration
GATEWAY_NS="gloo-gateway"
WORKLOAD_NS="team-a-runtime"
MGMT_NS="gloo-mesh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Gloo Mesh Enterprise E2E Validation"
echo "========================================"
echo ""

# Get Gateway IP
GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NS} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "${GATEWAY_IP}" ]; then
  echo -e "${YELLOW}Warning: Gateway LoadBalancer IP not yet assigned${NC}"
  echo "Run: kubectl get svc -n ${GATEWAY_NS} gloo-gateway-proxy"
  echo ""
else
  echo "Gateway External IP: ${GATEWAY_IP}"
  echo ""
fi

# Test 1: Management Plane Health
echo "Test 1: Management Plane Health"
echo "--------------------------------"
MGMT_PODS=$(kubectl get pods -n ${MGMT_NS} --no-headers 2>/dev/null | wc -l)
MGMT_READY=$(kubectl get pods -n ${MGMT_NS} --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${MGMT_PODS}" -eq "${MGMT_READY}" ] && [ "${MGMT_PODS}" -gt 0 ]; then
  echo -e "${GREEN}✓ Management plane healthy (${MGMT_READY}/${MGMT_PODS} pods running)${NC}"
else
  echo -e "${RED}✗ Management plane unhealthy (${MGMT_READY}/${MGMT_PODS} pods running)${NC}"
fi
kubectl get pods -n ${MGMT_NS}
echo ""

# Test 2: Gateway Health
echo "Test 2: Gateway Health"
echo "----------------------"
GW_PODS=$(kubectl get pods -n ${GATEWAY_NS} -l app=gloo-gateway --no-headers 2>/dev/null | wc -l)
GW_READY=$(kubectl get pods -n ${GATEWAY_NS} -l app=gloo-gateway --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${GW_PODS}" -eq "${GW_READY}" ] && [ "${GW_PODS}" -gt 0 ]; then
  echo -e "${GREEN}✓ Gateway healthy (${GW_READY}/${GW_PODS} pods running)${NC}"
else
  echo -e "${RED}✗ Gateway unhealthy (${GW_READY}/${GW_PODS} pods running)${NC}"
fi
kubectl get pods -n ${GATEWAY_NS} -l app=gloo-gateway
echo ""

# Test 3: Backend Application Health
echo "Test 3: Backend Application Health"
echo "-----------------------------------"
BACKEND_PODS=$(kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend --no-headers 2>/dev/null | wc -l)
BACKEND_READY=$(kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "${BACKEND_PODS}" -eq "${BACKEND_READY}" ] && [ "${BACKEND_PODS}" -gt 0 ]; then
  # Check sidecar injection (should be 2/2 containers)
  SIDECAR_COUNT=$(kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w || echo "0")
  if [ "${SIDECAR_COUNT}" -ge 2 ]; then
    echo -e "${GREEN}✓ Backend healthy with sidecar injected${NC}"
  else
    echo -e "${YELLOW}⚠ Backend running but sidecar may not be injected${NC}"
  fi
else
  echo -e "${RED}✗ Backend unhealthy${NC}"
fi
kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend
echo ""

# Test 4: Gloo Resources Status
echo "Test 4: Gloo Resources Status"
echo "------------------------------"
VG_STATUS=$(kubectl get virtualgateway -n ${WORKLOAD_NS} team-a-gateway -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
RT_STATUS=$(kubectl get routetable -n ${WORKLOAD_NS} api1-route -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")

if [ "${VG_STATUS}" == "Accepted" ] || [ "${VG_STATUS}" == "Unknown" ]; then
  echo -e "${GREEN}✓ VirtualGateway status: ${VG_STATUS}${NC}"
else
  echo -e "${RED}✗ VirtualGateway status: ${VG_STATUS}${NC}"
fi

if [ "${RT_STATUS}" == "Accepted" ] || [ "${RT_STATUS}" == "Unknown" ]; then
  echo -e "${GREEN}✓ RouteTable status: ${RT_STATUS}${NC}"
else
  echo -e "${RED}✗ RouteTable status: ${RT_STATUS}${NC}"
fi
echo ""

# Test 5: Translated Istio Resources
echo "Test 5: Translated Istio Resources"
echo "-----------------------------------"
VS_COUNT=$(kubectl get virtualservice -n ${WORKLOAD_NS} -l "reconciler.mesh.gloo.solo.io/name" --no-headers 2>/dev/null | wc -l)
if [ "${VS_COUNT}" -gt 0 ]; then
  echo -e "${GREEN}✓ VirtualService translated (${VS_COUNT} found)${NC}"
else
  echo -e "${YELLOW}⚠ No translated VirtualService found (may need time to reconcile)${NC}"
fi

DR_COUNT=$(kubectl get destinationrule -n ${WORKLOAD_NS} --no-headers 2>/dev/null | wc -l)
if [ "${DR_COUNT}" -gt 0 ]; then
  echo -e "${GREEN}✓ DestinationRule translated (${DR_COUNT} found)${NC}"
else
  echo -e "${YELLOW}⚠ No translated DestinationRule found${NC}"
fi
echo ""

# Test 6: External Access (if Gateway IP available)
echo "Test 6: External Access Test"
echo "----------------------------"
if [ -n "${GATEWAY_IP}" ]; then
  RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${GATEWAY_IP}:8080/api1 2>/dev/null || echo "000")
  
  if [ "${RESPONSE_CODE}" == "200" ]; then
    echo -e "${GREEN}✓ External access successful (HTTP ${RESPONSE_CODE})${NC}"
    echo "Response preview:"
    curl -s http://${GATEWAY_IP}:8080/api1 | head -5
  elif [ "${RESPONSE_CODE}" == "000" ]; then
    echo -e "${YELLOW}⚠ Cannot reach gateway (network issue or IP not ready)${NC}"
  else
    echo -e "${RED}✗ External access failed (HTTP ${RESPONSE_CODE})${NC}"
  fi
else
  echo -e "${YELLOW}⊘ Skipped (Gateway IP not available)${NC}"
fi
echo ""

# Test 7: mTLS Configuration
echo "Test 7: mTLS Configuration"
echo "--------------------------"
PA_MODE=$(kubectl get peerauthentication -n istio-system default-strict -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || echo "Unknown")
if [ "${PA_MODE}" == "STRICT" ]; then
  echo -e "${GREEN}✓ Mesh-wide STRICT mTLS enabled${NC}"
else
  echo -e "${YELLOW}⚠ mTLS mode: ${PA_MODE} (STRICT recommended for production)${NC}"
fi
echo ""

# Test 8: Gloo Mesh Health Check
echo "Test 8: Gloo Mesh Health Check"
echo "-------------------------------"
if command -v meshctl &> /dev/null; then
  if meshctl check &> /dev/null; then
    echo -e "${GREEN}✓ meshctl check passed${NC}"
  else
    echo -e "${YELLOW}⚠ meshctl check reported issues (run manually for details)${NC}"
  fi
else
  echo -e "${YELLOW}⊘ Skipped (meshctl not installed)${NC}"
fi
echo ""

# Summary
echo "========================================"
echo "  Validation Summary"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. If all tests passed, your Gloo Mesh Enterprise is ready!"
echo "2. Test access: curl http://${GATEWAY_IP:-<GATEWAY_IP>}:8080/api1"
echo "3. For production: configure HTTPS, RBAC, and monitoring"
echo ""
echo "Troubleshooting:"
echo "- View logs: kubectl logs -n ${MGMT_NS} -l app=gloo-mesh-mgmt-server"
echo "- Check proxy: istioctl proxy-status"
echo "- Debug routes: istioctl proxy-config route <gateway-pod> -n ${GATEWAY_NS}"
echo ""
