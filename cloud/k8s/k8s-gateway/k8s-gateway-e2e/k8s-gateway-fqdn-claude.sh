#!/usr/bin/env bash
# k8s-gateway-fqdn-claude.sh
# Usage: ./k8s-gateway-fqdn-claude.sh <fqdn>
# 根据输入 FQDN 追踪: HTTPRoute -> DestinationRule -> Service -> Deployment -> Health URL
#
# Example: ./k8s-gateway-fqdn-claude.sh app.team-a.example.com

set -euo pipefail

FQDN="${1:-}"
[[ -z "$FQDN" ]] && { echo "Usage: $0 <fqdn>"; exit 1; }

# ── Colors & helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
PASS()  { echo -e "${GREEN}[PASS]${NC} $1"; }
FAIL()  { echo -e "${RED}[FAIL]${NC} $1"; }
WARN()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
INFO()  { echo -e "${CYAN}${BOLD}>>> $1${NC}"; }
SEP()   { echo -e "${BOLD}───────────────────────────────────────────────────${NC}"; }

banner(){
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  FQDN Tracer: ${CYAN}${FQDN}${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo ""
}

# ── Global state (populated as we trace) ─────────────────────────────────────
declare -a CANDIDATE_URLS=()
ROUTE_NS=""
ROUTE_NAME=""
BACKEND_SVC=""
BACKEND_PORT=""
BACKEND_NS=""
DR_NAME=""
SVC_PORT=""
DEPLOY_NAME=""
HEALTH_PATH="/health"
LIVENESS_PATH=""

# ── Step 1: Find HTTPRoute matching FQDN ─────────────────────────────────────
step_httproute(){
  SEP
  INFO "Step 1: Locate HTTPRoute matching hostname: ${FQDN}"
  SEP

  # Scan all namespaces for HTTPRoute whose spec.hostnames contains FQDN
  local found=false
  while IFS= read -r line; do
    local ns name hostnames
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    # Get hostnames array for this route
    hostnames=$(kubectl get httproute "$name" -n "$ns" \
      -o jsonpath='{range .spec.hostnames[*]}{@}{"\n"}{end}' 2>/dev/null)

    # Match exact or wildcard
    while IFS= read -r h; do
      # Exact match
      if [[ "$h" == "$FQDN" ]]; then
        PASS "HTTPRoute match [exact]: $ns/$name  hostname=$h"
        ROUTE_NS="$ns"; ROUTE_NAME="$name"; found=true; break 2
      fi
      # Wildcard match: *.foo.example.com vs bar.foo.example.com
      if [[ "$h" == \** ]]; then
        local pattern="${h#\*.}"
        local fqdn_suffix="${FQDN#*.}"
        if [[ "$fqdn_suffix" == "$pattern" ]]; then
          PASS "HTTPRoute match [wildcard]: $ns/$name  hostname=$h"
          ROUTE_NS="$ns"; ROUTE_NAME="$name"; found=true; break 2
        fi
      fi
    done <<< "$hostnames"
  done < <(kubectl get httproute --all-namespaces --no-headers \
             -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' 2>/dev/null)

  if ! $found; then
    FAIL "No HTTPRoute found matching FQDN: ${FQDN}"
    exit 1
  fi
}

# ── Step 2: Extract rules / matches / backendRefs ────────────────────────────
step_routes(){
  SEP
  INFO "Step 2: Extract Rules, Matches, BackendRefs from $ROUTE_NS/$ROUTE_NAME"
  SEP

  echo ""
  echo -e "${BOLD}[HTTPRoute] ${ROUTE_NS}/${ROUTE_NAME}${NC}"
  echo ""

  # Print all listeners / parent refs
  echo "Parent Refs:"
  kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
    -o jsonpath='{range .spec.parentRefs[*]}  - {.name}/{.sectionName} (ns:{.namespace}){"\n"}{end}' 2>/dev/null
  echo ""

  # Rules: for each rule print matches + backendRefs
  local rule_count
  rule_count=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
    -o jsonpath='{range .spec.rules[*]}{@}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')
  echo "Rules count: $rule_count"
  echo ""

  # Collect all backendRef svc+port (pick first match for tracing)
  local idx=0
  while true; do
    local svc port bns
    svc=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].backendRefs[0].name}" 2>/dev/null) || break
    [[ -z "$svc" ]] && break

    port=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].backendRefs[0].port}" 2>/dev/null)
    bns=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].backendRefs[0].namespace}" 2>/dev/null)
    [[ -z "$bns" ]] && bns="$ROUTE_NS"  # default to same namespace

    # Matches for this rule
    local match_paths match_headers
    match_paths=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{range .spec.rules[$idx].matches[*]}{.path.type}:{.path.value}{'  '}{end}" 2>/dev/null)
    match_headers=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{range .spec.rules[$idx].matches[*]}{range .headers[*]}{.name}={.value}{'  '}{end}{end}" 2>/dev/null)

    # Timeouts
    local t_req t_be
    t_req=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].timeouts.request}" 2>/dev/null)
    t_be=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].timeouts.backendRequest}" 2>/dev/null)

    echo "  Rule[$idx]:"
    echo "    backendRef : $bns/$svc:$port"
    [[ -n "$match_paths"   ]] && echo "    path match : $match_paths"
    [[ -n "$match_headers" ]] && echo "    hdr match  : $match_headers"
    [[ -n "$t_req"         ]] && echo "    timeout    : request=$t_req backendRequest=$t_be"

    # Capture first rule for downstream tracing
    if [[ $idx -eq 0 ]]; then
      BACKEND_SVC="$svc"
      BACKEND_PORT="$port"
      BACKEND_NS="$bns"
    fi

    (( idx++ )) || true
  done

  echo ""
  PASS "Primary backendRef: ${BACKEND_NS}/${BACKEND_SVC}:${BACKEND_PORT}"
}

# ── Step 3: DestinationRule ───────────────────────────────────────────────────
step_dr(){
  SEP
  INFO "Step 3: DestinationRule for service: ${BACKEND_SVC} in ${BACKEND_NS}"
  SEP

  # Search by host field (short name or FQDN)
  DR_NAME=$(kubectl get destinationrule -n "$BACKEND_NS" \
    -o jsonpath="{range .items[?(@.spec.host=='${BACKEND_SVC}')]}{.metadata.name}{'\n'}{end}" 2>/dev/null | head -1)

  if [[ -z "$DR_NAME" ]]; then
    # Try full FQDN form
    DR_NAME=$(kubectl get destinationrule -n "$BACKEND_NS" \
      -o jsonpath="{range .items[*]}{.metadata.name}{'\t'}{.spec.host}{'\n'}{end}" 2>/dev/null | \
      awk -v svc="$BACKEND_SVC" '$2 ~ svc {print $1}' | head -1)
  fi

  if [[ -z "$DR_NAME" ]]; then
    WARN "No DestinationRule found for ${BACKEND_SVC} in ${BACKEND_NS} (may be normal for direct container)"
    return 0
  fi

  PASS "DestinationRule: ${BACKEND_NS}/${DR_NAME}"
  echo ""

  # Print key DR fields
  kubectl get destinationrule "$DR_NAME" -n "$BACKEND_NS" \
    -o jsonpath='Host:        {.spec.host}{"\n"}TrafficPolicy:
  ConnectTO:   {.spec.trafficPolicy.connectionPool.tcp.connectTimeout}{"\n"}  ReqTO:       {.spec.trafficPolicy.connectionPool.http.http1MaxPendingRequests}{"\n"}  OutlierDet:  ejectionTime={.spec.trafficPolicy.outlierDetection.baseEjectionTime}  consecutive5xx={.spec.trafficPolicy.outlierDetection.consecutive5xxErrors}{"\n"}' \
    2>/dev/null || true

  echo ""
  # Subsets
  local subset_cnt
  subset_cnt=$(kubectl get destinationrule "$DR_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{range .spec.subsets[*]}{.name}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')
  echo "Subsets: $subset_cnt"
  kubectl get destinationrule "$DR_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{range .spec.subsets[*]}  - {.name}  labels={.labels}{"\n"}{end}' 2>/dev/null || true
}

# ── Step 4: Service ───────────────────────────────────────────────────────────
step_svc(){
  SEP
  INFO "Step 4: Service ${BACKEND_NS}/${BACKEND_SVC}"
  SEP

  if ! kubectl get svc "$BACKEND_SVC" -n "$BACKEND_NS" >/dev/null 2>&1; then
    FAIL "Service ${BACKEND_NS}/${BACKEND_SVC} not found"
    return 1
  fi

  PASS "Service found"
  echo ""
  kubectl get svc "$BACKEND_SVC" -n "$BACKEND_NS" -o wide
  echo ""

  # Capture selector labels for Deployment lookup
  local selector
  selector=$(kubectl get svc "$BACKEND_SVC" -n "$BACKEND_NS" \
    -o jsonpath='{range .spec.selector}{@k}{"\n"}{end}' 2>/dev/null)
  # Better: get selector as label selector string
  selector=$(kubectl get svc "$BACKEND_SVC" -n "$BACKEND_NS" \
    -o json 2>/dev/null | \
    python3 -c "
import sys,json
d=json.load(sys.stdin)
sel=d.get('spec',{}).get('selector',{})
print(','.join(f'{k}={v}' for k,v in sel.items()))
" 2>/dev/null || echo "")

  echo "  Selector labels: $selector"

  # Port mapping: find ClusterIP port and targetPort
  SVC_PORT=$(kubectl get svc "$BACKEND_SVC" -n "$BACKEND_NS" \
    -o jsonpath="{range .spec.ports[?(@.port==${BACKEND_PORT})]}{.targetPort}{end}" 2>/dev/null)
  [[ -z "$SVC_PORT" ]] && SVC_PORT=$(kubectl get svc "$BACKEND_SVC" -n "$BACKEND_NS" \
    -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)

  echo "  TargetPort: $SVC_PORT"
  echo ""

  # Find Deployment via selector
  if [[ -n "$selector" ]]; then
    DEPLOY_NAME=$(kubectl get deploy -n "$BACKEND_NS" \
      -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  fi
  # Fallback: same name as service
  [[ -z "$DEPLOY_NAME" ]] && DEPLOY_NAME="$BACKEND_SVC"
  PASS "Deployment candidate: ${BACKEND_NS}/${DEPLOY_NAME}"
}

# ── Step 5: Deployment → health/liveness paths ───────────────────────────────
step_deployment(){
  SEP
  INFO "Step 5: Deployment ${BACKEND_NS}/${DEPLOY_NAME}"
  SEP

  if ! kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" >/dev/null 2>&1; then
    WARN "Deployment ${BACKEND_NS}/${DEPLOY_NAME} not found — trying same name as svc"
    DEPLOY_NAME="$BACKEND_SVC"
    kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" >/dev/null 2>&1 || {
      FAIL "Deployment not found"; return 1; }
  fi

  PASS "Deployment found"
  echo ""
  kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" -o wide
  echo ""

  # Extract container port, liveness, readiness paths from first container
  local container_port liveness readiness liveness_scheme readiness_scheme
  container_port=$(kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null || echo "")

  liveness=$(kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null || echo "")
  liveness_scheme=$(kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.scheme}' 2>/dev/null || echo "HTTP")

  readiness=$(kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || echo "")
  readiness_scheme=$(kubectl get deploy "$DEPLOY_NAME" -n "$BACKEND_NS" \
    -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.scheme}' 2>/dev/null || echo "HTTP")

  echo "  ContainerPort  : ${container_port:-<not set>}"
  echo "  LivenessProbe  : ${liveness:-<not set>}  (scheme: ${liveness_scheme})"
  echo "  ReadinessProbe : ${readiness:-<not set>}  (scheme: ${readiness_scheme})"
  echo ""

  # Prefer liveness > readiness > default /health
  if [[ -n "$liveness" ]]; then
    HEALTH_PATH="$liveness"
    PASS "Using livenessProbe path: $HEALTH_PATH"
  elif [[ -n "$readiness" ]]; then
    HEALTH_PATH="$readiness"
    PASS "Using readinessProbe path: $HEALTH_PATH"
  else
    WARN "No probe path found, defaulting to: $HEALTH_PATH"
  fi
  LIVENESS_PATH="$liveness"
}

# ── Step 6: Build E2E URLs ────────────────────────────────────────────────────
step_build_urls(){
  SEP
  INFO "Step 6: E2E Test URL Summary"
  SEP

  # Determine scheme from Gateway listener or assume https
  local scheme="https"

  # Get all path matches from HTTPRoute for URL generation
  echo ""
  echo -e "${BOLD}Generated E2E Test URLs:${NC}"
  echo ""

  local idx=0
  while true; do
    local match_path match_type
    match_path=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].matches[0].path.value}" 2>/dev/null) || break
    [[ -z "$match_path" ]] && break

    match_type=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].matches[0].path.type}" 2>/dev/null)

    local bsvc bport bns url_path
    bsvc=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].backendRefs[0].name}" 2>/dev/null)
    bport=$(kubectl get httproute "$ROUTE_NAME" -n "$ROUTE_NS" \
      -o jsonpath="{.spec.rules[$idx].backendRefs[0].port}" 2>/dev/null)

    # Construct path: if PathPrefix, append health path under it
    case "$match_type" in
      PathPrefix)
        # strip trailing slash from prefix, then append health path
        url_path="${match_path%/}${HEALTH_PATH}"
        ;;
      Exact)
        url_path="$match_path"
        ;;
      *)
        url_path="${match_path}${HEALTH_PATH}"
        ;;
    esac

    local full_url="${scheme}://${FQDN}${url_path}"
    CANDIDATE_URLS+=("$full_url")

    printf "  Rule[%d]  %-12s  backend=%-30s  URL: %s\n" \
      "$idx" "${match_type}:${match_path}" "${bns:-$ROUTE_NS}/${bsvc}:${bport}" "$full_url"

    (( idx++ )) || true
  done

  # If no rules produced output, build minimal URL from HEALTH_PATH
  if [[ ${#CANDIDATE_URLS[@]} -eq 0 ]]; then
    local fallback="${scheme}://${FQDN}${HEALTH_PATH}"
    CANDIDATE_URLS+=("$fallback")
    echo "  (no path matches found — using health path directly)"
    echo "  URL: $fallback"
  fi
}

# ── Step 7: Quick curl validation ─────────────────────────────────────────────
step_curl(){
  SEP
  INFO "Step 7: Quick HTTP Validation (curl)"
  SEP
  echo ""

  # Resolve Gateway ILB IP for --resolve
  local gw_ip
  gw_ip=$(kubectl get svc -A \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' \
    2>/dev/null | grep -v '^$' | head -1 || echo "")

  for url in "${CANDIDATE_URLS[@]}"; do
    echo -e "  ${BOLD}Testing:${NC} $url"
    local http_code
    local curl_opts=(-s -o /dev/null -w "%{http_code}" --max-time 10 -k)
    [[ -n "$gw_ip" ]] && curl_opts+=(--resolve "${FQDN}:443:${gw_ip}" --resolve "${FQDN}:80:${gw_ip}")

    http_code=$(curl "${curl_opts[@]}" "$url" 2>/dev/null || echo "000")

    case "$http_code" in
      200|201|204)      PASS "HTTP $http_code ← $url" ;;
      301|302|307|308)  WARN "HTTP $http_code (redirect) ← $url" ;;
      401|403)          WARN "HTTP $http_code (auth required) ← $url" ;;
      404)              FAIL "HTTP $http_code (not found) ← $url" ;;
      000)              FAIL "Connection failed ← $url" ;;
      *)                FAIL "HTTP $http_code ← $url" ;;
    esac
  done
}

# ── Final summary ─────────────────────────────────────────────────────────────
step_summary(){
  SEP
  INFO "Summary"
  SEP
  echo ""
  printf "  %-20s %s\n" "Input FQDN:"    "$FQDN"
  printf "  %-20s %s\n" "HTTPRoute:"     "${ROUTE_NS}/${ROUTE_NAME}"
  printf "  %-20s %s\n" "BackendSvc:"    "${BACKEND_NS}/${BACKEND_SVC}:${BACKEND_PORT}"
  printf "  %-20s %s\n" "DestRule:"      "${DR_NAME:-<none>}"
  printf "  %-20s %s\n" "Service:"       "${BACKEND_NS}/${BACKEND_SVC}"
  printf "  %-20s %s\n" "Deployment:"    "${BACKEND_NS}/${DEPLOY_NAME}"
  printf "  %-20s %s\n" "HealthPath:"    "$HEALTH_PATH"
  printf "  %-20s %s\n" "LivenessPath:"  "${LIVENESS_PATH:-<same>}"
  echo ""
  echo -e "${BOLD}E2E URLs:${NC}"
  for u in "${CANDIDATE_URLS[@]}"; do
    echo "  → $u"
  done
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
banner
step_httproute
step_routes
step_dr
step_svc
step_deployment
step_build_urls
step_curl
step_summary