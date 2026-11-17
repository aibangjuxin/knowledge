#!/usr/bin/env bash
# K8s Gateway FQDN Resource Explorer & URL Builder
# Usage: ./k8s-gateway-fqdn.sh <fqdn> [tenant-namespace]
#
# Given an FQDN, this script traces through the K8s Gateway API resource chain:
#   HTTPRoute → DestinationRule → Service → Deployment
# and produces complete test URLs for E2E testing.
#
# It handles both routing modes:
#   - Direct container (apigateway: NONE) — no Kong sidecar
#   - Kong DP proxied (apigateway: KONG)  — Kong sidecar injected
#
# Output: table of resources + constructed HTTPS URLs ready for curl/Playwright

set -euo pipefail

# ── Arguments ────────────────────────────────────────────────────────────────
INPUT_FQDN="${1:-}"
TENANT_NS="${2:-}"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'

PASS(){  echo -e "${GREEN}[PASS]${NC} $1"; }
FAIL(){  echo -e "${RED}[FAIL]${NC} $1"; }
WARN(){  echo -e "${YELLOW}[WARN]${NC} $1"; }
INFO(){  echo -e "${CYAN}=== $1 ===${NC}"; }
SECTION(){ echo ""; echo -e "${BOLD}${MAGENTA}## $1${NC}"; }

# ── Derive defaults ─────────────────────────────────────────────────────────
GATEWAY_NS="${GATEWAY_NS:-infrastructure}"
GATEWAY_NAME="${GATEWAY_NAME:-abjx-gw-int}"
GATEWAY_ILB_IP="${GATEWAY_ILB_IP:-$(kubectl get svc -n "$GATEWAY_NS" -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")}"

# ── Usage check ─────────────────────────────────────────────────────────────
usage(){
  echo "Usage: $0 <fqdn> [tenant-namespace]"
  echo "  <fqdn>             — Fully qualified domain name (e.g. api.teamname-int.uk.aibang.local)"
  echo "  [tenant-namespace] — Kubernetes namespace (auto-detected if omitted)"
  echo ""
  echo "Examples:"
  echo "  $0 api.teamname-int.uk.aibang.local"
  echo "  $0 api.teamname-int.uk.aibang.local teamname-int"
  exit 1
}

[[ -z "$INPUT_FQDN" ]] && usage

# ── Helpers ─────────────────────────────────────────────────────────────────
json_escape(){
  # Escape special chars in jsonpath strings for safe use in commands
  echo "$1" | sed 's/"/\\"/g'
}

kubectl_safe(){
  kubectl "$@" 2>/dev/null
}

# ── Banner ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  K8s Gateway FQDN Explorer"
echo "  Input FQDN : $INPUT_FQDN"
echo "  Tenant NS  : ${TENANT_NS:-auto}"
echo "  Gateway ILB: ${GATEWAY_ILB_IP:-auto}"
echo "═══════════════════════════════════════════════════════════════"

# ══════════════════════════════════════════════════════════════════
# STEP 1 — Find HTTPRoute by hostname
# ══════════════════════════════════════════════════════════════════
SECTION "STEP 1 — HTTPRoute Discovery"

# Auto-detect tenant NS from FQDN if not provided
if [[ -z "$TENANT_NS" ]]; then
  # FQDN pattern: <prefix>.<tenant-ns>.<domain-suffix>
  # e.g. api.teamname-int.uk.aibang.local → extract "teamname-int"
  TENANT_NS=$(echo "$INPUT_FQDN" | awk -F. '{print $2}')
  [[ -z "$TENANT_NS" ]] && { FAIL "Cannot auto-detect tenant namespace from FQDN: $INPUT_FQDN"; exit 1; }
  INFO "Auto-detected tenant namespace: $TENANT_NS"
fi

# Find all HTTPRoutes in the tenant namespace
HTTPRoute_CANDIDATES=($(kubectl_safe get httproute -n "$TENANT_NS" -o jsonpath='{.items[*].metadata.name}'))

if [[ ${#HTTPRoute_CANDIDATES[@]} -eq 0 ]] || [[ -z "${HTTPRoute_CANDIDATES[0]}" ]]; then
  FAIL "No HTTPRoute found in namespace: $TENANT_NS"
  exit 1
fi

echo ""
INFO "HTTPRoute candidates in $TENANT_NS: ${HTTPRoutes[*]}"

# Filter HTTPRoutes whose hostname matches INPUT_FQDN
declare -a MATCHED_HTTPRouteS=()
for HRT in "${HTTPRoute_CANDIDATES[@]}"; do
  HRT_HOSTNAMES=$(kubectl_safe get httproute "$HRT" -n "$TENANT_NS" \
    -o jsonpath='{range .spec.hostnames[*]}{.}{"\n"}{end}' 2>/dev/null)
  while IFS= read -r hostname; do
    # Normalize: strip trailing dot, match exact or wildcard prefix
    hn_normalized="${hostname%.}"
    fqdn_normalized="${INPUT_FQDN%.}"
    if [[ "$hn_normalized" == "$fqdn_normalized" ]] || \
       [[ "$hn_normalized" == "*.$fqdn_normalized" ]] || \
       [[ "$fqdn_normalized" == "$hn_normalized" ]] || \
       [[ "$fqdn_normalized" == *"$hn_normalized" ]]; then
      MATCHED_HTTPRouteS+=("$HRT")
      break
    fi
  done <<< "$HRT_HOSTNAMES"
done

if [[ ${#MATCHED_HTTPRouteS[@]} -eq 0 ]]; then
  FAIL "No HTTPRoute matches FQDN: $INPUT_FQDN in NS: $TENANT_NS"
  echo ""
  echo "All HTTPRoutes in $TENANT_NS:"
  kubectl_safe get httproute -n "$TENANT_NS" -o wide
  exit 1
fi

HTTPRoute_NAME="${MATCHED_HTTPRouteS[0]}"
INFO "Matched HTTPRoute: $HTTPRoute_NAME"

# ══════════════════════════════════════════════════════════════════
# STEP 2 — Extract HTTPRoute details
# ══════════════════════════════════════════════════════════════════
SECTION "STEP 2 — HTTPRoute Detail"

HRT_YAML=$(kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" -o yaml)

# Hostname
HRT_HOSTNAMES=$(kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" \
  -o jsonpath='{range .spec.hostnames[*]}{.}{"\n"}{end}')
echo -e "  Hostnames : ${CYAN}${HRT_HOSTNAMES}${NC}"

# Parent refs (Gateway binding)
HRT_PARENTS=$(kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" \
  -o jsonpath='{range .status.parents[*]}{.parentRef.name}{"/"}{.parentRef.sectionName}{" → "}{range .conditions[*]}{.type}{":"}{.status}{"; "}{end}{"\n"}{end}')
echo -e "  ParentRefs: ${CYAN}${HRT_PARENTS}${NC}"

# Rules + matches + backendRefs
echo ""
echo "  Rules & Matches:"
kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" \
  -o jsonpath='{range .spec.rules[*]}{
    .name}{": backendRefs=["}{range .backendRefs[*]}{.name}{":"}{.port}{"("}{.weight}{"), "}{end}{"]"}{"\n"}{
    "  Matches:"}{range .matches[*]}{"  - "}{.name}{": "}{range .matches[*].headers[*]}{.name}{"="}{.value}{", "}{end}{range .matches[*].path[*]}{.type}{":"}{.value}{", "}{end}{"\n"}{end}' | \
  while IFS= read -r line; do echo "    $line"; done

# ══════════════════════════════════════════════════════════════════
# STEP 3 — Extract backendRef details (Service → Deployment)
# ══════════════════════════════════════════════════════════════════
SECTION "STEP 3 — Backend Chain (HTTPRoute → Service → Deployment)"

# Extract all backendRefs from all rules
BACKEND_REFS=$(kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" \
  -o jsonpath='{range .spec.rules[*]}{range .backendRefs[*]}{.name}{"#"}{.port}{"\n"}{end}{end}')

if [[ -z "$BACKEND_REFS" ]]; then
  FAIL "No backendRefs found in HTTPRoute: $HTTPRoute_NAME"
  exit 1
fi

declare -a SVC_NAMES=()
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  svc_name="${ref%%#*}"
  port="${ref##*#}"
  SVC_NAMES+=("$svc_name:$port")
done <<< "$BACKEND_REFS"

INFO "Discovered Services: ${SVC_NAMES[*]}"

# ── Per-Service analysis ───────────────────────────────────────────────────
declare -a TEST_URLS=()

for svc_ref in "${SVC_NAMES[@]}"; do
  SVC_NAME="${svc_ref%%:*}"
  SVC_PORT="${svc_ref##*:}"

  echo ""
  echo -e "${BOLD}  Service: $SVC_NAME:$SVC_PORT${NC}"

  # Get Service details
  SVC_CLUSTER_IP=$(kubectl_safe get svc "$SVC_NAME" -n "$TENANT_NS" \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
  SVC_TYPE=$(kubectl_safe get svc "$SVC_NAME" -n "$TENANT_NS" \
    -o jsonpath='{.spec.type}' 2>/dev/null || echo "ClusterIP")
  SVC_APIGATEWAY=$(kubectl_safe get svc "$SVC_NAME" -n "$TENANT_NS" \
    -o jsonpath='{.metadata.annotations.apigateway\.net/v1alpha1}' 2>/dev/null || echo "")
  echo "    ClusterIP   : $SVC_CLUSTER_IP"
  echo "    Type        : $SVC_TYPE"
  echo "    apigateway  : $SVC_APIGATEWAY"

  # Determine routing mode
  ROUTING_MODE="unknown"
  if [[ "$SVC_APIGATEWAY" == *"NONE"* ]]; then
    ROUTING_MODE="direct"
    echo -e "    Mode        : ${GREEN}direct (no Kong)${NC}"
  elif [[ "$SVC_APIGATEWAY" == *"KONG"* ]]; then
    ROUTING_MODE="kong"
    echo -e "    Mode        : ${YELLOW}kong (Kong sidecar)${NC}"
  fi

  # Find Pods for this Service via selector
  SVC_SELECTOR=$(kubectl_safe get svc "$SVC_NAME" -n "$TENANT_NS" \
    -o jsonpath='{.spec.selector}' 2>/dev/null | tr ',' '\n' | awk -F: '{print $1":"$2}' | tr '\n' ',' | sed 's/,$//')

  if [[ -n "$SVC_SELECTOR" ]]; then
    echo "    Selector    : $SVC_SELECTOR"
    POD_CNT=$(kubectl_safe get pods -n "$TENANT_NS" -l "$SVC_SELECTOR" \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w | tr -d ' ')
    echo "    Pod count   : $POD_CNT"
  fi

  # ── Find DestinationRule ────────────────────────────────────────────────
  DR_YAML=$(kubectl_safe get destinationrule -n "$TENANT_NS" \
    -o yaml 2>/dev/null)

  DR_NAME=""
  DR_TIMEOUT=""
  DR_CONNECT_TIMEOUT=""

  if echo "$DR_YAML" | grep -q "items:"; then
    DR_NAME=$(echo "$DR_YAML" | kubectl_safe apply -f - \
      --dry-run=client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    # Match DR by host that matches the service name pattern
    DR_ALL=$(kubectl_safe get destinationrule -n "$TENANT_NS" -o json \
      --ignore-not-found)

    if [[ -n "$DR_ALL" ]] && echo "$DR_ALL" | python3 -c "
import sys,json
drs=json.load(sys.stdin)
for dr in drs.get('items',[]):
    h=dr.get('spec',{}).get('host','')
    n=dr.get('metadata',{}).get('name','')
    t=dr.get('spec',{}).get('trafficPolicy',{}).get('timeout','')
    ct=dr.get('spec',{}).get('trafficPolicy',{}).get('connectionPool',{}).get('tcp',{}).get('connectTimeout','')
    print(n,'|',h,'|',t,'|',ct)
" 2>/dev/null | while IFS='|' read -r name host timeout ct; do
      # Match by service name substring in host
      if [[ "$host" == *"$SVC_NAME"* ]] || [[ "$SVC_NAME" == *"$host"* ]] || [[ -z "$host" ]]; then
        DR_NAME="$name"
        DR_TIMEOUT="$timeout"
        DR_CONNECT_TIMEOUT="$ct"
        break
      fi
    done
  fi

  echo "    DestinationRule: ${DR_NAME:-<none>}"
  [[ -n "$DR_TIMEOUT" ]] && echo "    DR timeout      : $DR_TIMEOUT"
  [[ -n "$DR_CONNECT_TIMEOUT" ]] && echo "    DR connectTimeout: $DR_CONNECT_TIMEOUT"

  # ── Find Deployment ─────────────────────────────────────────────────────
  # Try to find Deployment via the Service selector or via pod owner references
  DEPLOY_NAME=""
  DEPLOY_NS="$TENANT_NS"
  HEALTH_URL=""
  LIVENESS_URL=""
  READY_CHECK_URL=""

  # Method A: selector-based pod lookup → owner reference
  if [[ -n "$SVC_SELECTOR" ]]; then
    OWNER_DEPLOY=$(kubectl_safe get pods -n "$TENANT_NS" -l "$SVC_SELECTOR" \
      -o jsonpath='{range .items[*]}{range .metadata.ownerReferences[*]}{.kind}{":"}{.name}{"\n"}{end}{end}' 2>/dev/null | \
      grep "Deployment" | head -1 | awk -F: '{print $2}')
    if [[ -n "$OWNER_DEPLOY" ]]; then
      DEPLOY_NAME="$OWNER_DEPLOY"
    fi
  fi

  # Method B: search all Deployments in NS whose selector matches
  if [[ -z "$DEPLOY_NAME" ]]; then
    for dep in $(kubectl_safe get deploy -n "$TENANT_NS" -o jsonpath='{.items[*].metadata.name}'); do
      DEP_SELECTOR=$(kubectl_safe get deploy "$dep" -n "$TENANT_NS" \
        -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null | tr -d '{}' | tr ',' '\n' | awk -F: '{print $1":"$2}' | sort | tr '\n' ',' | sed 's/,$//')
      SVC_SELECTOR_SORTED=$(echo "$SVC_SELECTOR" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
      if [[ "$DEP_SELECTOR" == "$SVC_SELECTOR_SORTED" ]]; then
        DEPLOY_NAME="$dep"
        break
      fi
    done
  fi

  if [[ -n "$DEPLOY_NAME" ]]; then
    echo "    Deployment   : $DEPLOY_NAME"
    DEPLOY_NS="$TENANT_NS"

    # Extract health/liveness from Deployment spec
    CONTAINER_NAME=$(kubectl_safe get deploy "$DEPLOY_NAME" -n "$DEPLOY_NS" \
      -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null || echo "")

    HEALTH_URL=$(kubectl_safe get deploy "$DEPLOY_NAME" -n "$DEPLOY_NS" \
      -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || echo "")
    LIVENESS_URL=$(kubectl_safe get deploy "$DEPLOY_NAME" -n "$DEPLOY_NS" \
      -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null || echo "")
    INITIAL_DELAY=$(kubectl_safe get deploy "$DEPLOY_NAME" -n "$DEPLOY_NS" \
      -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.initialDelaySeconds}' 2>/dev/null || echo "")

    [[ -n "$HEALTH_URL" ]] && echo "    Health probe : $HEALTH_URL"
    [[ -n "$LIVENESS_URL" ]] && echo "    Liveness probe: $LIVENESS_URL"
  else
    echo "    Deployment   : ${YELLOW}<not found via selector matching>${NC}"
  fi

  # ── Construct complete URLs ────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Constructed Test URLs:${NC}"

  PROTOCOL="https"
  BASE_URL="${PROTOCOL}://${INPUT_FQDN}"

  # Flow 1: Direct via ILB → Envoy → HTTPRoute → Container
  if [[ "$ROUTING_MODE" == "direct" ]]; then
    TEST_URLS+=("${BASE_URL}${HEALTH_URL:-/health}")
    echo -e "    [Flow-1 Direct] ${CYAN}${BASE_URL}${HEALTH_URL:-/health}${NC}"

    if [[ -n "$GATEWAY_ILB_IP" ]]; then
      echo -e "    [Flow-1 Alt]   ${CYAN}https://${GATEWAY_ILB_IP}${HEALTH_URL:-/health}${NC} (Host: ${INPUT_FQDN})"
    fi

  # Flow 2: Via Kong DP (apigateway: KONG)
  elif [[ "$ROUTING_MODE" == "kong" ]]; then
    # Kong DP typically strips /api prefix or routes on specific paths
    KONG_PATHS=("/api/v1/health" "/" "/health" "/api/health")
    for kpath in "${KONG_PATHS[@]}"; do
      TEST_URLS+=("${BASE_URL}${kpath}")
      echo -e "    [Flow-2 Kong]  ${CYAN}${BASE_URL}${kpath}${NC}"
    done

    if [[ -n "$GATEWAY_ILB_IP" ]]; then
      for kpath in "${KONG_PATHS[@]}"; do
        echo -e "    [Flow-2 Alt]   ${CYAN}https://${GATEWAY_ILB_IP}${kpath}${NC} (Host: ${INPUT_FQDN})"
      done
    fi

  else
    echo -e "    ${YELLOW}[unknown mode — skipping URL construction]${NC}"
  fi

  # Per-backendRef URL
  echo -e "    [BackendRef]  ${CYAN}${BASE_URL}/{route-path}${HEALTH_URL:-/health}${NC}"

done

# ══════════════════════════════════════════════════════════════════
# STEP 4 — HTTPRoute timeout config
# ══════════════════════════════════════════════════════════════════
SECTION "STEP 4 — HTTPRoute Timeout Configuration"

HRT_TIMEOUT=$(kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" \
  -o jsonpath='{range .spec.rules[*]}{.name}{": request="}{.timeouts.request}{", backend="}{.timeouts.backendTimeout}{"\n"}{end}')
HRT_BACKEND_TIMEOUT=$(kubectl_safe get httproute "$HTTPRoute_NAME" -n "$TENANT_NS" \
  -o jsonpath='{range .spec.rules[*]}{range .backendRefs[*]}{.name}{":"}{.port}{" [weight="}{.weight}{"]"}{"\n"}{end}{end}')

if [[ -n "$HRT_TIMEOUT" ]]; then
  echo -e "  Request timeout : ${CYAN}$(echo "$HRT_TIMEOUT" | head -1)${NC}"
  echo -e "  Backend timeout : ${CYAN}$(echo "$HRT_TIMEOUT" | tail -1)${NC}"
else
  echo -e "  Timeouts        : ${YELLOW}<not set — uses Envoy defaults>${NC}"
fi

# ══════════════════════════════════════════════════════════════════
# STEP 5 — Envoy cluster / route config for this FQDN
# ══════════════════════════════════════════════════════════════════
SECTION "STEP 5 — Envoy Cluster Config (Gateway Pod)"

GATEWAY_POD=$(kubectl_safe get pods -n "$GATEWAY_NS" -l app=envoy \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$GATEWAY_POD" ]]; then
  echo "  Gateway Pod: $GATEWAY_POD"

  # Try to find route config for this FQDN
  CONFIG_DUMP=$(kubectl exec -n "$GATEWAY_NS" deploy/"$GATEWAY_NAME" -- \
    curl -s localhost:15000/config_dump 2>/dev/null || echo "")

  if [[ -n "$CONFIG_DUMP" ]]; then
    # Look for virtual_hosts entry matching the FQDN
    ROUTE_ENTRY=$(echo "$CONFIG_DUMP" | grep -A5 "route_config" | \
      grep -E "route_name|domains|matched" | head -20)
    if [[ -n "$ROUTE_ENTRY" ]]; then
      echo -e "  Route config  : ${CYAN}${ROUTE_ENTRY}${NC}"
    fi

    # Cluster connect timeout
    CLUSTER_TIMEOUT=$(echo "$CONFIG_DUMP" | grep -o 'connect_timeout":[0-9]*' | sort -u | head -5)
    [[ -n "$CLUSTER_TIMEOUT" ]] && echo -e "  Cluster timeouts: ${CYAN}${CLUSTER_TIMEOUT}${NC}"
  else
    echo -e "  ${YELLOW}Could not retrieve Envoy config dump${NC}"
  fi
else
  echo -e "  ${YELLOW}No Gateway pod found in $GATEWAY_NS${NC}"
fi

# ══════════════════════════════════════════════════════════════════
# STEP 6 — Summary table
# ══════════════════════════════════════════════════════════════════
SECTION "STEP 6 — Complete E2E Test URLs Summary"

echo ""
printf "  %-20s %s\n" "FQDN" "$INPUT_FQDN"
printf "  %-20s %s\n" "Tenant Namespace" "$TENANT_NS"
printf "  %-20s %s\n" "HTTPRoute" "$HTTPRoute_NAME"
printf "  %-20s %s\n" "Gateway ILB IP" "${GATEWAY_ILB_IP:-<auto-detect>}"
printf "  %-20s %s\n" "Routing Mode" "$ROUTING_MODE"
[[ -n "$DR_NAME" ]] && printf "  %-20s %s\n" "DestinationRule" "$DR_NAME"
[[ -n "$DR_TIMEOUT" ]] && printf "  %-20s %s\n" "DR Timeout" "$DR_TIMEOUT"
printf "  %-20s %s\n" "Health Probe" "${HEALTH_URL:-<none>}"
printf "  %-20s %s\n" "Liveness Probe" "${LIVENESS_URL:-<none>}"

echo ""
echo "  Ready-to-use curl commands:"
for url in "${TEST_URLS[@]}"; do
  if [[ -n "$GATEWAY_ILB_IP" ]]; then
    echo -e "    ${CYAN}curl -k --max-time 10 -H \"Host: ${INPUT_FQDN}\" \"https://${GATEWAY_ILB_IP}${url##*$INPUT_FQDN}\"${NC}"
  fi
  echo -e "    ${CYAN}curl -k --max-time 10 \"${url}\"${NC}"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  Done. FQDN: ${GREEN}${INPUT_FQDN}${NC}"
echo "═══════════════════════════════════════════════════════════════"