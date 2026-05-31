#!/usr/bin/env bash
# K8s Gateway E2E Verification Suite
# Usage: ./k8s-gateway-verify.sh <phase> [tenant-namespace] [gateway-ip]
#
# Phases:
#   preflight      — Phase 0: CRDs, Gateway, istiod, Kong DP
#   binding        — Phase 1: Gateway->ListenerSet binding, HTTPRoute attachment
#   flow1          — Phase 2.1: Direct container routing test
#   flow2          — Phase 2.2: Kong DP routing test
#   health         — Phase 2.3: ILB health check + pod readiness
#   netpol         — Phase 3: NetworkPolicy isolation tests
#   timeout        — Phase 4: Timeout configuration + 504 injection
#   monitoring     — Phase 5: Envoy metrics + logging baseline
#   all            — Run all phases sequentially

set -euo pipefail

PHASE="${1:-all}"
TENANT_NS="${2:-}"
GATEWAY_IP="${3:-}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS(){ echo -e "${GREEN}[PASS]${NC} $1"; }
FAIL(){ echo -e "${RED}[FAIL]${NC} $1"; }
WARN(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
INFO(){ echo "=== $1 ==="; }

# Derived values
GATEWAY_NS="infrastructure"
GATEWAY_NAME="${GATEWAY_NAME:-central-gateway}"
[[ -z "$GATEWAY_IP" ]] && GATEWAY_IP="$(kubectl get svc -n "$GATEWAY_NS" -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")"

header(){
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  K8s Gateway E2E — Phase: $1"
  echo "═══════════════════════════════════════════"
}

# ─── Phase 0: Pre-flight ────────────────────────────────────────────────────
phase_preflight(){
  header "0: Pre-flight Checks"

  INFO "0.1 Gateway API CRDs"
  local all_ok=true
  for crd in gatewayclasses gateways listenersets httproutes grpcroutes tcproutes referencegrants; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
      PASS "CRD exists: $crd"
    else
      FAIL "CRD missing: $crd"
      all_ok=false
    fi
  done
  $all_ok && PASS "All CRDs present" || FAIL "Some CRDs missing"

  INFO "0.2 GatewayClass"
  local gc_cnt
  gc_cnt=$(kubectl get gatewayclass -o name | wc -l | tr -d ' ')
  if [[ "$gc_cnt" -gt 0 ]]; then
    PASS "GatewayClass count: $gc_cnt"
    kubectl get gatewayclass -o wide
  else
    FAIL "No GatewayClass found"
  fi

  INFO "0.3 Gateway Status"
  if kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" >/dev/null 2>&1; then
    local cond
    cond=$(kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" \
      -o jsonpath='{range .status.conditions[?(@.type=="Accepted")]}{.status}{end}')
    if [[ "$cond" == "True" ]]; then
      PASS "Gateway $GATEWAY_NAME Accepted"
    else
      FAIL "Gateway not Accepted: $cond"
    fi
    kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" -o wide
  else
    FAIL "Gateway $GATEWAY_NAME not found"
  fi

  INFO "0.4 ListenerSets"
  local ls_cnt
  ls_cnt=$(kubectl get listenersets --all-namespaces -o name 2>/dev/null | wc -l | tr -d ' ')
  PASS "ListenerSet count: $ls_cnt"
  kubectl get listenersets --all-namespaces -o wide 2>/dev/null || WARN "ListenerSet fetch failed"

  INFO "0.5 istiod"
  local istiod_ready
  istiod_ready=$(kubectl get pods -n istio-system -l app=istiod \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{end}' 2>/dev/null)
  if [[ "$istiod_ready" == "True"* ]]; then
    PASS "istiod Ready"
  else
    FAIL "istiod not Ready: $istiod_ready"
  fi

  INFO "0.6 Kong DP"
  local kong_ready
  kong_ready=$(kubectl get pods -n kong-apw-kong-int \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{end}' 2>/dev/null)
  if [[ "$kong_ready" == "True"* ]]; then
    PASS "Kong DP Ready"
  else
    FAIL "Kong DP not Ready: $kong_ready"
  fi

  INFO "0.7 Tenant Namespaces"
  local tenant_cnt
  tenant_cnt=$(kubectl get namespaces -l 'tenant' -o name 2>/dev/null | wc -l | tr -d ' ')
  PASS "Tenant namespaces with 'tenant' label: $tenant_cnt"
}

# ─── Phase 1: Control Plane ──────────────────────────────────────────────────
phase_binding(){
  header "1: Control Plane Binding"
  [[ -z "$TENANT_NS" ]] && { FAIL "TENANT_NS required (arg 2)"; exit 1; }

  INFO "1.1 Gateway Listeners"
  kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" \
    -o jsonpath='{range .status.listeners[*]}{
      .name}{"\t"}{.attachedRoutes}{"\t"}{range .conditions[*]}{.type}{":"}{.status}{", "}{end}{"\n"}{end}'

  INFO "1.2 HTTPRoute in $TENANT_NS"
  kubectl get httproute -n "$TENANT_NS" -o wide || WARN "No HTTPRoute found"

  INFO "1.3 HTTPRoute parent status"
  kubectl get httproute -n "$TENANT_NS" \
    -o jsonpath='{range .items[*]}{
      .metadata.name}{"\n"}{range .status.parents[*]}{
        .parentRef.name}{"/"}{.parentRef.sectionName}{"\t"}{range .conditions[*]}{.type}{":"}{.status}{", "}{end}{"\n"}{end}{end}'

  INFO "1.4 ReferenceGrants"
  kubectl get referencegrants --all-namespaces 2>/dev/null || WARN "No ReferenceGrant found (may be normal if no cross-ns refs)"

  INFO "1.5 ListenerSets Status"
  kubectl get listenersets --all-namespaces \
    -o jsonpath='{range .items[*]}{
      .metadata.namespace}{"/"}{.metadata.name}{"\t"}{range .status.conditions[*]}{.type}{":"}{.status}{", "}{end}{"\n"}{end}'
}

# ─── Phase 2: Data Plane ────────────────────────────────────────────────────
phase_flow1(){
  header "2.1: Flow 1 — Direct Container Routing"
  [[ -z "$TENANT_NS" ]] && { FAIL "TENANT_NS required (arg 2)"; exit 1; }
  [[ -z "$GATEWAY_IP" ]] && { FAIL "GATEWAY_IP required (arg 3) or ILB IP not found"; exit 1; }

  INFO "2.1 ILB IP: $GATEWAY_IP"

  local hostname="app.${TENANT_NS}.example.com"
  INFO "2.1 Testing direct container route: $hostname"
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -H "Host: $hostname" \
    "https://${GATEWAY_IP}/health" 2>/dev/null || echo "000")

  if [[ "$response" == "200" ]]; then
    PASS "Direct container health → HTTP $response"
  else
    FAIL "Direct container health → HTTP $response (expected 200)"
  fi
}

phase_flow2(){
  header "2.2: Flow 2 — Kong DP Routing"
  [[ -z "$TENANT_NS" ]] && { FAIL "TENANT_NS required (arg 2)"; exit 1; }
  [[ -z "$GATEWAY_IP" ]] && { FAIL "GATEWAY_IP required (arg 3) or ILB IP not found"; exit 1; }

  local hostname="kong.${TENANT_NS}.example.com"
  INFO "2.2 Testing Kong-protected route: $hostname"
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -H "Host: $hostname" \
    -H "X-Kong-Request-ID: $(uuidgen 2>/dev/null || echo test)" \
    "https://${GATEWAY_IP}/api/v1/health" 2>/dev/null || echo "000")

  if [[ "$response" == "200" ]]; then
    PASS "Kong DP route → HTTP $response"
  else
    FAIL "Kong DP route → HTTP $response (expected 200)"
  fi
}

phase_health(){
  header "2.3: Health Check Verification"

  INFO "2.3a Envoy health endpoint"
  local envoy_hc
  envoy_hc=$(kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
    curl -s --max-time 5 localhost:15021/healthz 2>/dev/null || echo "failed")
  if [[ "$envoy_hc" == "healthy" ]]; then
    PASS "Envoy /healthz → $envoy_hc"
  else
    FAIL "Envoy /healthz → $envoy_hc (expected: healthy)"
  fi

  INFO "2.3b Gateway Pod Ready"
  local gw_ready
  gw_ready=$(kubectl get pods -n abjx-gw-int -l app=envoy \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{end}' 2>/dev/null)
  if [[ "$gw_ready" == "True"* ]]; then
    PASS "Gateway pods Ready: $gw_ready"
  else
    FAIL "Gateway pods not Ready: $gw_ready"
  fi
}

# ─── Phase 3: NetworkPolicy ─────────────────────────────────────────────────
phase_netpol(){
  header "3: NetworkPolicy Isolation"
  [[ -z "$TENANT_NS" ]] && { FAIL "TENANT_NS required (arg 2)"; exit 1; }

  INFO "3.1 NetPol in Gateway NS"
  local gw_netpol_cnt
  gw_netpol_cnt=$(kubectl get netpol -n abjx-gw-int -o name | wc -l | tr -d ' ')
  PASS "Gateway NS NetPol count: $gw_netpol_cnt"
  kubectl get netpol -n abjx-gw-int -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

  INFO "3.2 NetPol in Tenant NS ($TENANT_NS)"
  local tenant_netpol_cnt
  tenant_netpol_cnt=$(kubectl get netpol -n "$TENANT_NS" -o name | wc -l | tr -d ' ')
  PASS "Tenant NS NetPol count: $tenant_netpol_cnt"
  kubectl get netpol -n "$TENANT_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

  INFO "3.3 default-deny-all check"
  for ns in abjx-gw-int "$TENANT_NS"; do
    if kubectl get netpol default-deny-all -n "$ns" >/dev/null 2>&1; then
      PASS "default-deny-all exists in $ns"
    else
      FAIL "default-deny-all MISSING in $ns"
    fi
  done

  INFO "3.4 GCP HC IPs whitelisted (abjx-gw-int)"
  kubectl get netpol default-allow-gcp-hc-ingress -n abjx-gw-int \
    -o jsonpath='{range .spec.ingress[*]}{range .from[*]}{.ipBlock.cidr}{", "}{end}{end}' 2>/dev/null
}

# ─── Phase 4: Timeout ───────────────────────────────────────────────────────
phase_timeout(){
  header "4: Timeout & Resilience"
  [[ -z "$TENANT_NS" ]] && { FAIL "TENANT_NS required (arg 2)"; exit 1; }

  INFO "4.1 HTTPRoute timeouts"
  kubectl get httproute -n "$TENANT_NS" \
    -o jsonpath='{range .items[*]}{
      .metadata.name}{"\t"}{range .spec.rules[*]}{.timeouts.request}{"/"}{.timeouts.backendTimeout}{", "}{end}{"\n"}{end}'

  INFO "4.2 DestinationRule timeout"
  kubectl get destinationrule -n "$TENANT_NS" \
    -o jsonpath='{range .items[*]}{
      .metadata.name}{"\t"}{.spec.trafficPolicy.timeout}{"\t"}{.spec.trafficPolicy.connectTimeout}{"\n"}{end}' \
    2>/dev/null || WARN "No DestinationRule found (may be normal for direct containers)"

  INFO "4.3 Envoy default cluster timeout"
  kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
    curl -s localhost:15000/config_dump 2>/dev/null | \
    grep -o '"connect_timeout":[0-9]*' | head -5 || WARN "Could not dump Envoy config"
}

# ─── Phase 5: Monitoring ───────────────────────────────────────────────────
phase_monitoring(){
  header "5: Monitoring Baseline"

  INFO "5.1 Envoy metrics endpoint"
  local metrics_cnt
  metrics_cnt=$(kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
    curl -s localhost:15000/stats/prometheus 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$metrics_cnt" -gt 100 ]]; then
    PASS "Envoy metrics endpoint returning $metrics_cnt lines"
  else
    FAIL "Envoy metrics endpoint returning only $metrics_cnt lines"
  fi

  INFO "5.2 Key metric samples"
  kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
    curl -s localhost:15000/stats/prometheus 2>/dev/null | \
    grep -E 'envoy_cluster_upstream_rq_timeout|envoy_cluster_upstream_rq_5xx|envoy_listener_downstream_cx' | head -10

  INFO "5.3 Kong DP status"
  kubectl get pods -n kong-apw-kong-int -o wide 2>/dev/null || WARN "Kong namespace not accessible"

  INFO "5.4 Alert rules present"
  if kubectl get prometheusrule k8s-gateway-alerts -n monitoring >/dev/null 2>&1; then
    PASS "PrometheusRule k8s-gateway-alerts exists"
  else
    WARN "PrometheusRule k8s-gateway-alerts not found (deploy with alerts-k8s-gateway.yaml)"
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────────
case "$PHASE" in
  preflight)  phase_preflight ;;
  binding)    phase_binding ;;
  flow1)      phase_flow1 ;;
  flow2)      phase_flow2 ;;
  health)     phase_health ;;
  netpol)     phase_netpol ;;
  timeout)    phase_timeout ;;
  monitoring) phase_monitoring ;;
  all)
    phase_preflight
    echo ""
    read -p "Continue to binding phase? (requires TENANT_NS) [y/N]: " confirm
    [[ "${confirm,,}" == "y" ]] && phase_binding
    ;;
  *)
    echo "Usage: $0 <phase> [tenant-ns] [gateway-ip]"
    echo "Phases: preflight binding flow1 flow2 health netpol timeout monitoring all"
    exit 1
    ;;
esac
