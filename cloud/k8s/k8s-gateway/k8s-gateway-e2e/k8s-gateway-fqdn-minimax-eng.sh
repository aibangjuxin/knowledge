#!/usr/bin/env bash
# =============================================================================
# k8s-gateway-fqdn-minimax.sh — K8s Gateway FQDN Deep Chain Explorer & E2E URL Builder
#
# Purpose: Given an Ingress domain (FQDN), auto-traverse the K8s Gateway API core chain:
#       HTTPRoute ──► ParentRef(Gateway/ListenerSet)
#                    ──► BackendRef(Service, cross-NS) ──► DestinationRule
#                    ──► Service ──► Deployment ──► Probes (readiness/liveness/startup)
#       and generate precise curl commands for E2E testing (auto-adapts to listener
#       protocol, SNI --resolve, PathPrefix/Exact/Regex path joining).
#
# Usage: ./k8s-gateway-fqdn-minimax.sh <FQDN> [TENANT_NAMESPACE] [--validate]
#
# Design fusion:
#   - Core architecture inspired by k8s-gateway-fqdn-gemini.sh(pure jq pipeline, cross-NS scan, color scheme)
#   - Listener protocol/port detection inspired by k8s-gateway-fqdn-chatgpt.sh(auto http/https)
#   - Probe full enumeration inspired by chatgpt (readiness / liveness / startup, cross-container)
#   - Path joining logic inspired by chatgpt join_prefix_probe (PathPrefix/Exact/Regex)
#   - Cross-namespace backendRef inspired by chatgpt
#   - Optional --validate curl verification inspired by chatgpt + claude
#   - Fixed yesterday's fqdn.sh `kubectl apply` misuse and HTTPRoutes typo
#   - Fixed claude.sh's hardcoded /health and `((idx++)) || true` unreliable loop
#   - Fixed chatgpt.sh's TENANT_NS / --validate parameter conflict (changed to standard --flag)
#
# Dependencies: kubectl, jq, curl
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Colors & formatting
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[✔]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}# $*${RESET}"; }
divider() { echo -e "${DIM}$(printf '═%.0s' {1..88})${RESET}"; }
subdiv()  { echo -e "${DIM}$(printf '─%.0s' {1..88})${RESET}"; }

# --------------------------------------------------------------------------- #
# Default configuration (environment variable overrides supported)
# --------------------------------------------------------------------------- #
GATEWAY_NS="${GATEWAY_NS:-abjx-gw-int}"
GATEWAY_NAME="${GATEWAY_NAME:-abjx-gw-int}"
DEFAULT_SCHEME="${DEFAULT_SCHEME:-https}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

# --------------------------------------------------------------------------- #
# Argument parsing (standard --flag style, fixed chatgpt.sh's TENANT_NS/--validate conflict)
# --------------------------------------------------------------------------- #
usage() {
  echo -e "$(cat <<EOF

${BOLD}Usage:${RESET} $(basename "$0") <FQDN> [TENANT_NAMESPACE] [--validate|-v] [--help|-h]

${BOLD}Arguments:${RESET}
  <FQDN>              Target Ingress domain (e.g.: api.team1-int.uk.aibang.local)
  [TENANT_NAMESPACE]  Tenant namespace (optional; if omitted, infer from FQDN 2nd segment first, fall back to cluster-wide scan)
  --validate, -v      Optional: actually run curl to verify generated E2E URLs

${BOLD}Environment variables:${RESET}
  GATEWAY_NS          Gateway's namespace (default: ${GATEWAY_NS})
  GATEWAY_NAME        Gateway resource name (default: ${GATEWAY_NAME})
  DEFAULT_SCHEME      URL scheme when listener protocol cannot be determined (default: ${DEFAULT_SCHEME})
  CURL_TIMEOUT        curl timeout in seconds for validation (default: ${CURL_TIMEOUT})

${BOLD}Examples:${RESET}
  $(basename "$0") api.team1-int.uk.aibang.local
  $(basename "$0") app.team2.example.com team2
  $(basename "$0") api.team1-int.uk.aibang.local team1-int --validate

${BOLD}Chain inspection scope:${RESET}
  HTTPRoute → ParentRef(Gateway / ListenerSet) → Listener protocol/port
           → BackendRef(Service, cross-NS) → DestinationRule
           → Service (ClusterIP, selector, port mapping)
           → Deployment (cross-container enumeration of readiness/liveness/startup probe)
           → generate E2E URL + multiple curl verification commands (SNI / direct IP / DNS dependent)

EOF
)"
  exit 1
}

INPUT_FQDN=""
TENANT_NS=""
VALIDATE="false"

# First pass: collect FQDN and TENANT_NS (first two non-flag arguments)
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --validate|-v) VALIDATE="true" ;;
    --help|-h)     usage ;;
    --*)           err "Unknown flag: $arg"; exit 1 ;;
    *)             POSITIONAL+=("$arg") ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 ]] && INPUT_FQDN="${POSITIONAL[0]}"
[[ ${#POSITIONAL[@]} -ge 2 ]] && TENANT_NS="${POSITIONAL[1]}"
[[ ${#POSITIONAL[@]} -gt 2 ]] && { err "Extra positional arguments: ${POSITIONAL[*]:2}"; usage; }

[[ -z "$INPUT_FQDN" ]] && usage

# --------------------------------------------------------------------------- #
# Dependency check
# --------------------------------------------------------------------------- #
for cmd in kubectl jq curl; do
  if ! command -v "$cmd" &>/dev/null; then
    err "This script depends on '$cmd', please install it first."
    exit 1
  fi
done

# --------------------------------------------------------------------------- #
# Utility functions
# --------------------------------------------------------------------------- #
# Safely read JSON (return empty items on failure)
kj() { kubectl "$@" -o json 2>/dev/null || echo '{"items":[]}'; }

# Normalize path (remove duplicate /, ensure leading /)
norm_path() {
  local p="${1:-/}"
  [[ -z "$p" ]] && p="/"
  [[ "${p:0:1}" != "/" ]] && p="/$p"
  printf '%s' "$p" | sed -E 's#/+#/#g'
}

# Join route path with probe path (inspired by chatgpt join_prefix_probe, enhanced)
join_path() {
  local match_type="$1" route_path="$2" probe_path="$3"
  route_path="$(norm_path "$route_path")"
  probe_path="$(norm_path "$probe_path")"

  case "$match_type" in
    Exact)
      printf '%s' "$route_path"
      ;;
    PathPrefix|"")
      if [[ "$route_path" == "/" ]]; then
        printf '%s' "$probe_path"
      elif [[ "$probe_path" == "$route_path" || "$probe_path" == "${route_path}/"* ]]; then
        printf '%s' "$probe_path"
      else
        printf '%s/%s' "${route_path%/}" "${probe_path#/}" | sed -E 's#/+#/#g'
      fi
      ;;
    RegularExpression|ImplementationSpecific)
      # Keep probe path's leading '/' while joining, then collapse multiple '/' into one
      printf '%s%s' "$route_path" "$probe_path" | sed -E 's#/+#/#g'
      ;;
    *)
      printf '%s' "$route_path"
      ;;
  esac
}

# URL authority builder: only append :port for non-default ports
url_authority() {
  local scheme="$1" port="$2"
  if [[ "$scheme" == "https" && "$port" == "443" ]] \
     || [[ "$scheme" == "http" && "$port" == "80" ]] \
     || [[ -z "$port" ]]; then
    printf '%s' "$INPUT_FQDN"
  else
    printf '%s:%s' "$INPUT_FQDN" "$port"
  fi
}

# Execute curl validation on a single URL and print result (avoid case in pipe subshell)
do_validate_one() {
  local url="$1" port="$2" gw_ip="$3"
  local -a args=(-k -s -o /dev/null -w "%{http_code}" --max-time "$CURL_TIMEOUT")
  if [[ -n "$gw_ip" ]]; then
    args+=(--resolve "${INPUT_FQDN}:${port}:${gw_ip}")
  fi
  local code
  code="$(curl "${args[@]}" "$url" 2>/dev/null || echo "000")"

  case "$code" in
    200|201|202|204) printf "    %sHTTP %s%s  %s\n" "$GREEN" "$code" "$RESET" "$url" ;;
    301|302|307|308) printf "    %sHTTP %s%s  %s (redirect)\n" "$YELLOW" "$code" "$RESET" "$url" ;;
    401|403)         printf "    %sHTTP %s%s  %s (auth-required, chain reachable)\n" "$YELLOW" "$code" "$RESET" "$url" ;;
    404)             printf "    %sHTTP %s%s  %s (404 — backend route mismatch!)\n" "$RED" "$code" "$RESET" "$url" ;;
    000)             printf "    %sCONN-FAIL%s  %s (network unreachable)\n" "$RED" "$RESET" "$url" ;;
    *)               printf "    %sHTTP %s%s  %s\n" "$RED" "$code" "$RESET" "$url" ;;
  esac
}

# --------------------------------------------------------------------------- #
# Banner
# --------------------------------------------------------------------------- #
echo ""
divider
echo -e "  ${BOLD}${MAGENTA}🛰️  K8s Gateway FQDN Deep Chain Inspector (MiniMax Enhanced)${RESET}"
echo -e "  Target FQDN:    ${BOLD}${GREEN}${INPUT_FQDN}${RESET}"
echo -e "  Tenant NS:      ${BOLD}${TENANT_NS:-<auto>}${RESET}"
echo -e "  Gateway:       ${BOLD}${GATEWAY_NS}/${GATEWAY_NAME}${RESET}"
echo -e "  Validate mode:  ${BOLD}${VALIDATE}${RESET}"
divider

# --------------------------------------------------------------------------- #
# Smart tenant namespace inference (from FQDN 2nd segment) — inspired by yesterday's fqdn.sh
# --------------------------------------------------------------------------- #
if [[ -z "$TENANT_NS" ]]; then
  CANDIDATE_NS="$(echo "$INPUT_FQDN" | awk -F. '{print $2}')"
  if [[ -n "$CANDIDATE_NS" ]]; then
    if kj get namespace "$CANDIDATE_NS" 2>/dev/null | grep -q "\"name\":\"$CANDIDATE_NS\""; then
      TENANT_NS="$CANDIDATE_NS"
      info "Smart-inferred tenant namespace from FQDN 2nd segment: ${BOLD}${TENANT_NS}${RESET}"
    else
      info "FQDN 2nd segment '$CANDIDATE_NS' is not a valid namespace, will perform cluster-wide HTTPRoute scan."
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# Step 1: Smart FQDN route discovery (cross-NS, exact + wildcard supported)
# --------------------------------------------------------------------------- #
header "Step 1 / 6 — HTTPRoute Smart Discovery"

info "Scanning HTTPRoute bound to domain ${INPUT_FQDN}${TENANT_NS:+ (scoped to NS: $TENANT_NS)}..."

if [[ -n "$TENANT_NS" ]]; then
  ROUTES_JSON="$(kj get httproute -n "$TENANT_NS")"
else
  ROUTES_JSON="$(kj get httproute -A)"
fi

# Strict matching with jq (inspired by chatgpt's host_match, fixed gemini's trailing-dot issue)
MATCHED_ROUTES="$(jq -r --arg fqdn "${INPUT_FQDN%.}" '
  def norm: rtrimstr(".");
  def host_match($fqdn; $host):
    ($host | norm) as $h |
    if $h == $fqdn then true
    elif ($h | startswith("*.")) then
      ($h | ltrimstr("*.")) as $suffix |
      (($fqdn | endswith("." + $suffix)) and (($fqdn | split(".") | length) == ($h | split(".") | length)))
    else false
    end;

  .items[]?
  | select(any(.spec.hostnames[]? // []; host_match($fqdn; .)))
  | [.metadata.namespace, .metadata.name, ((.spec.hostnames // []) | join(","))]
  | @tsv
' <<<"$ROUTES_JSON")"

if [[ -z "$MATCHED_ROUTES" ]]; then
  err "No HTTPRoute found binding to domain: ${INPUT_FQDN}"
  warn "Existing HTTPRoutes in the cluster (for reference):"
  jq -r '.items[]? | [.metadata.namespace, .metadata.name, ((.spec.hostnames // ["<empty>"]) | join(","))] | @tsv' <<<"$ROUTES_JSON" \
    | awk -F'\t' '{printf "    %-30s %-40s hostnames=%s\n", $1, $2, $3}' >&2
  exit 1
fi

ROUTE_COUNT="$(printf '%s\n' "$MATCHED_ROUTES" | wc -l | tr -d ' ')"
ok "Matched ${BOLD}${ROUTE_COUNT}${RESET} HTTPRoute(s)"
printf '%s\n' "$MATCHED_ROUTES" | awk -F'\t' '{printf "    • %s/%s\n      hostnames: %s\n", $1, $2, $3}'

# --------------------------------------------------------------------------- #
# Collectors
# --------------------------------------------------------------------------- #
declare -a ALL_E2E_URLS=()        # Full URLs (for summary)
declare -a ALL_CURL_COMMANDS=()   # Full curl commands
declare -a ALL_VALIDATION=()      # For --validate: URL<TAB>port<TAB>gw_ip

# --------------------------------------------------------------------------- #
# Step 2 ~ 6: Per HTTPRoute deep chain inspection
# --------------------------------------------------------------------------- #
while IFS=$'\t' read -r ROUTE_NS ROUTE_NAME ROUTE_HOSTNAMES; do
  [[ -z "$ROUTE_NS" || -z "$ROUTE_NAME" ]] && continue

  header "HTTPRoute: ${BOLD}${ROUTE_NS}/${ROUTE_NAME}${RESET}"
  ROUTE_JSON="$(kj get httproute "$ROUTE_NAME" -n "$ROUTE_NS")"
  [[ -z "$ROUTE_JSON" ]] && { warn "Failed to read HTTPRoute, skipping"; continue; }

  # 2.1 Show hostnames
  subdiv
  echo -e "  ${BOLD}Hostnames:${RESET}"
  jq -r '.spec.hostnames[]? // empty' <<<"$ROUTE_JSON" | sed 's/^/    - /'

  # 2.2 Show ParentRefs (supports Gateway and ListenerSet)
  echo ""
  echo -e "  ${BOLD}ParentRefs (Gateway / ListenerSet):${RESET}"

  URL_SCHEME="$DEFAULT_SCHEME"
  URL_PORT="443"
  GATEWAY_IP=""

  PARENTS_JSON="$(jq -c '.spec.parentRefs[]? // empty' <<<"$ROUTE_JSON")"
  if [[ -z "$PARENTS_JSON" ]]; then
    warn "    HTTPRoute has no spec.parentRefs (may not be attached to any Gateway)"
  fi

  while IFS= read -r parent; do
    [[ -z "$parent" ]] && continue
    P_KIND="$(jq -r '.kind // "Gateway"' <<<"$parent")"
    P_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$parent")"
    P_NAME="$(jq -r '.name' <<<"$parent")"
    P_SECTION="$(jq -r '.sectionName // ""' <<<"$parent")"

    printf "    • %s ${CYAN}%s/%s${RESET}" "$P_KIND" "$P_NS" "$P_NAME"
    [[ -n "$P_SECTION" ]] && printf " sectionName=%s" "$P_SECTION"
    echo ""

    if [[ "$P_KIND" == "Gateway" ]]; then
      GW_JSON="$(kj get gateway "$P_NAME" -n "$P_NS")"
      if [[ -z "$GW_JSON" ]]; then
        warn "      Gateway ${P_NS}/${P_NAME} unreadable"
        continue
      fi

      # Extract Gateway status IP (prefer status.addresses)
      THIS_IP="$(jq -r '.status.addresses[]? | select(.type == "IP" or .type == "Hostname" or .type == null) | .value' <<<"$GW_JSON" | head -n 1)"
      [[ -z "$GATEWAY_IP" && -n "$THIS_IP" ]] && GATEWAY_IP="$THIS_IP"

      # Show listener details
      LISTENER_DETAIL="$(jq -r --arg section "$P_SECTION" '
        .spec.listeners[]?
        | select($section == "" or .name == $section)
        | "      listener=" + (.name // "?")
          + "  protocol=" + (.protocol // "?")
          + "  port=" + ((.port // "?") | tostring)
          + "  tlsMode=" + (.tls.mode // "-")
          + "  certRefs=" + ((.tls.certificateRefs // []) | length | tostring)
      ' <<<"$GW_JSON")"
      [[ -n "$LISTENER_DETAIL" ]] && echo "$LISTENER_DETAIL"

      # Protocol/port detection (take the first matching listener)
      L_PROTOCOL="$(jq -r --arg section "$P_SECTION" '
        ([.spec.listeners[]?
          | select($section == "" or .name == $section)]
         | .[0].protocol // empty)
      ' <<<"$GW_JSON")"
      L_PORT="$(jq -r --arg section "$P_SECTION" '
        ([.spec.listeners[]?
          | select($section == "" or .name == $section)]
         | .[0].port // empty)
      ' <<<"$GW_JSON")"

      case "$L_PROTOCOL" in
        HTTPS|TLS)  URL_SCHEME="https" ;;
        HTTP)       URL_SCHEME="http" ;;
        *)          ;;
      esac
      [[ -n "$L_PORT" && "$L_PORT" != "0" ]] && URL_PORT="$L_PORT"
    elif [[ "$P_KIND" == "ListenerSet" ]]; then
      LS_JSON="$(kj get listenerset "$P_NAME" -n "$P_NS")"
      if [[ -n "$LS_JSON" ]]; then
        jq -r --arg section "$P_SECTION" '
          .spec.listeners[]?
          | select($section == "" or .name == $section)
          | "      listener=" + (.name // "?")
            + "  protocol=" + (.protocol // "?")
            + "  port=" + ((.port // "?") | tostring)
            + "  (ListenerSet)"
        ' <<<"$LS_JSON"
      fi
    fi
  done <<<"$PARENTS_JSON"

  # Fallback: if parentRefs didn't get IP, look in LoadBalancer Service
  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kj get svc -n "$GATEWAY_NS" \
      | jq -r '.items[]? | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // empty' \
      | head -n 1)"
  fi
  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kj get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" \
      | jq -r '.status.addresses[0].value // empty')"
  fi

  echo ""
  echo -e "  ${BOLD}Detection result:${RESET}"
  echo -e "    • listener scheme: ${CYAN}${URL_SCHEME}${RESET}"
  echo -e "    • listener port:   ${CYAN}${URL_PORT}${RESET}"
  echo -e "    • gateway IP:      ${CYAN}${GATEWAY_IP:-<not found>}${RESET}"

  # 2.3 Show HTTPRoute status.parents (binding status)
  echo ""
  echo -e "  ${BOLD}Route Binding Status (status.parents):${RESET}"
  PARENT_STATUS="$(jq -r '
    .status.parents[]? |
    "    • " + (.parentRef.namespace // "<same-ns>") + "/" + .parentRef.name
    + "/" + (.parentRef.sectionName // "<all>")
    + "  →  " + ([.conditions[]? | .type + "=" + .status] | join(", "))
  ' <<<"$ROUTE_JSON")"
  if [[ -n "$PARENT_STATUS" ]]; then
    echo "$PARENT_STATUS"
  else
    warn "    (no status.parents — route may not yet be accepted by Gateway)"
  fi

  # ------------------------------------------------------------------------- #
  # Step 3: Iterate over rules
  # ------------------------------------------------------------------------- #
  header "Step 3 / 6 — Rules / Matches / Backends"
  RULES_COUNT="$(jq '.spec.rules | length // 0' <<<"$ROUTE_JSON")"
  [[ "$RULES_COUNT" == "0" ]] && { warn "HTTPRoute has no rules, skipping"; continue; }

  for ((rule_idx=0; rule_idx<RULES_COUNT; rule_idx++)); do
    RULE_JSON="$(jq -c ".spec.rules[$rule_idx]" <<<"$ROUTE_JSON")"
    RULE_NAME="$(jq -r '.name // ""' <<<"$RULE_JSON")"

    subdiv
    echo -e "  ${BOLD}⚡ Rule[$rule_idx]${RULE_NAME:+ (name=$RULE_NAME)}${RESET}"

    # 3.1 matches — output TSV: type<TAB>path<TAB>headers<TAB>queryParams<TAB>methods
    MATCH_LINES="$(jq -r '
      if ((.matches // []) | length) == 0 then
        "PathPrefix\t/\t<no-headers>\t<no-qs>\tANY"
      else
        .matches[] |
        [
          (.path.type // "PathPrefix"),
          (.path.value // "/"),
          ([(.headers // [])[] | .name + "=" + (.value // "*")]
            | if length == 0 then "<no-headers>" else join(",") end),
          ([(.queryParams // [])[] | .name + "=" + (.value // "*")]
            | if length == 0 then "<no-qs>" else join(",") end),
          ([(.method // "ANY") | tostring] | if length == 0 then "ANY" else join(",") end)
        ] | @tsv
      end
    ' <<<"$RULE_JSON")"

    echo -e "  ${BOLD}Matches:${RESET}"
    echo "$MATCH_LINES" | awk -F'\t' '{
      printf "    • type=%-15s path=%-20s headers=%-25s query=%-15s method=%s\n", $1, $2, $3, $4, $5
    }'

    # 3.2 timeouts
    REQ_T="$(jq -r '.timeouts.request // empty' <<<"$RULE_JSON")"
    BK_T="$(jq -r '.timeouts.backendRequest // .timeouts.backendTimeout // empty' <<<"$RULE_JSON")"
    if [[ -n "$REQ_T" || -n "$BK_T" ]]; then
      echo -e "  ${BOLD}Timeouts:${RESET} request=${REQ_T:-<default>} backend=${BK_T:-<default>}"
    fi

    # 3.3 Iterate over backendRefs
    BACKENDS="$(jq -c '.backendRefs[]? // empty' <<<"$RULE_JSON")"
    if [[ -z "$BACKENDS" ]]; then
      warn "  Rule[$rule_idx] has no backendRefs"
      continue
    fi

    while IFS= read -r backend; do
      [[ -z "$backend" ]] && continue

      B_KIND="$(jq -r '.kind // "Service"' <<<"$backend")"
      B_NAME="$(jq -r '.name' <<<"$backend")"
      B_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$backend")"
      B_PORT="$(jq -r '.port // ""' <<<"$backend")"
      B_WEIGHT="$(jq -r '.weight // 1' <<<"$backend")"

      echo ""
      echo -e "    ${BOLD}→ BackendRef: ${B_KIND} ${B_NS}/${B_NAME}:${B_PORT} (weight=${B_WEIGHT})${RESET}"

      if [[ "$B_KIND" != "Service" ]]; then
        warn "      backend kind='$B_KIND' (non-Service), skip Service/Deployment chain inspection"
        continue
      fi

      # --------------------------------------------------------------------- #
      # Step 4: DestinationRule (supports multiple host forms)
      # --------------------------------------------------------------------- #
      DR_JSON="$(kj get destinationrule -n "$B_NS")"
      [[ -z "$DR_JSON" || "$DR_JSON" == "null" ]] && DR_JSON='{"items":[]}'
      MATCHED_DR="$(jq -r --arg svc "$B_NAME" --arg ns "$B_NS" '
        .items[]?
        | select(
            .spec.host == $svc
            or .spec.host == ($svc + "." + $ns)
            or .spec.host == ($svc + "." + $ns + ".svc")
            or .spec.host == ($svc + "." + $ns + ".svc.cluster.local")
          )
        | [
            .metadata.name,
            .spec.host,
            (.spec.trafficPolicy.connectionPool.tcp.connectTimeout // ""),
            (.spec.trafficPolicy.connectionPool.http.idleTimeout // ""),
            ((.spec.trafficPolicy.outlierDetection.consecutive5xxErrors // "" | tostring)),
            ((.spec.trafficPolicy.outlierDetection.baseEjectionTime // "" | tostring))
          ]
        | @tsv
      ' <<<"$DR_JSON")"

      if [[ -n "$MATCHED_DR" ]]; then
        IFS=$'\t' read -r DR_NAME DR_HOST DR_CONN DR_IDLE DR_OE5X DR_OEJT <<<"$MATCHED_DR"
        echo -e "      ${BOLD}DestinationRule:${RESET} ${MAGENTA}${B_NS}/${DR_NAME}${RESET} (host=${DR_HOST})"
        echo -e "        • connectTimeout: ${DR_CONN:-<default>}"
        echo -e "        • idleTimeout:    ${DR_IDLE:-<default>}"
        echo -e "        • outlierDet:     consecutive5xx=${DR_OE5X:-<default>} baseEjectionTime=${DR_OEJT:-<default>}"
      else
        echo -e "      ${BOLD}DestinationRule:${RESET} ${DIM}<none>${RESET}"
      fi

      # --------------------------------------------------------------------- #
      # Step 5: Service
      # --------------------------------------------------------------------- #
      SVC_JSON="$(kj get svc "$B_NAME" -n "$B_NS")"
      if [[ -z "$SVC_JSON" ]]; then
        err "      Service ${B_NS}/${B_NAME} not found, skipping"
        continue
      fi

      SVC_TYPE="$(jq -r '.spec.type // "ClusterIP"' <<<"$SVC_JSON")"
      SVC_CLUSTER_IP="$(jq -r '.spec.clusterIP // "<pending>"' <<<"$SVC_JSON")"
      SVC_SELECTOR="$(jq -r '.spec.selector // {} | to_entries | map(.key + "=" + .value) | join(",")' <<<"$SVC_JSON")"
      SVC_APIGW="$(jq -r '.metadata.annotations["apigateway.net/v1alpha1"] // "<none>"' <<<"$SVC_JSON")"

      SVC_PORT_INFO="$(jq -r --argjson port "${B_PORT:-0}" '
        ((.spec.ports // [])[] | select((.port // 0) == $port))
        // (.spec.ports // [])[0]
        | "port=" + ((.port // "") | tostring)
          + " → targetPort=" + ((.targetPort // "") | tostring)
          + " protocol=" + (.protocol // "TCP")
          + " appProtocol=" + (.appProtocol // "<none>")
      ' <<<"$SVC_JSON")"

      echo -e "      ${BOLD}Service:${RESET} type=${SVC_TYPE} clusterIP=${SVC_CLUSTER_IP} apigateway=${SVC_APIGW}"
      echo -e "        • selector: ${SVC_SELECTOR:-<none>}"
      echo -e "        • ${SVC_PORT_INFO}"

      # --------------------------------------------------------------------- #
      # Step 6: Deployment + Probes (cross-container, all probe types)
      # --------------------------------------------------------------------- #
      DEPLOY_NAME=""
      if [[ -n "$SVC_SELECTOR" ]]; then
        # Method A: Match deploy directly via selector (inspired by gemini)
        DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -l "$SVC_SELECTOR" \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      fi
      if [[ -z "$DEPLOY_NAME" ]]; then
        # Method B: Trace via Pod ownerReferences
        if [[ -n "$SVC_SELECTOR" ]]; then
          POD_JSON="$(kj get pods -n "$B_NS" -l "$SVC_SELECTOR")"
          [[ -z "$POD_JSON" || "$POD_JSON" == "null" ]] && POD_JSON='{"items":[]}'
          RS_NAME="$(jq -r '.items[0].metadata.ownerReferences[]? | select(.kind == "ReplicaSet") | .name' <<<"$POD_JSON" | head -n 1 || true)"
          if [[ -n "$RS_NAME" ]]; then
            DEPLOY_NAME="$(kj get rs "$RS_NAME" -n "$B_NS" \
              | jq -r '.metadata.ownerReferences[]? | select(.kind == "Deployment") | .name' | head -n 1 || true)"
          fi
        fi
      fi
      if [[ -z "$DEPLOY_NAME" ]]; then
        # Method C: Match Deployment spec.selector to SVC selector (inspired by gemini)
        DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -o json 2>/dev/null \
          | jq -r --arg sel "$SVC_SELECTOR" '
              .items[]?
              | select((.spec.selector.matchLabels // {}) | to_entries | map(.key + "=" + .value) | join(",") == $sel)
              | .metadata.name
            ' | head -n 1 || true)"
      fi

      # No longer use "$B_NAME" as fallback (this is claude.sh's pitfall, easy to misattribute)
      if [[ -n "$DEPLOY_NAME" ]]; then
        DEPLOY_JSON="$(kj get deploy "$DEPLOY_NAME" -n "$B_NS")"
        READY="$(jq -r '.status.readyReplicas // 0' <<<"$DEPLOY_JSON")"
        DESIRED="$(jq -r '.spec.replicas // 0' <<<"$DEPLOY_JSON")"
        echo -e "      ${BOLD}Deployment:${RESET} ${GREEN}${B_NS}/${DEPLOY_NAME}${RESET} ready=${READY}/${DESIRED}"

        # Enumerate all HTTP probes across containers (inspired by chatgpt)
        PROBES_JSON="$(jq -r '
          .spec.template.spec.containers[]? |
          .name as $c |
          [
            ["readiness", .readinessProbe.httpGet.path // "", (.readinessProbe.httpGet.port // "" | tostring), (.readinessProbe.httpGet.scheme // "HTTP")],
            ["liveness",  .livenessProbe.httpGet.path  // "", (.livenessProbe.httpGet.port  // "" | tostring), (.livenessProbe.httpGet.scheme  // "HTTP")],
            ["startup",   .startupProbe.httpGet.path   // "", (.startupProbe.httpGet.port   // "" | tostring), (.startupProbe.httpGet.scheme   // "HTTP")]
          ][] |
          select(.[1] != null and .[1] != "") |
          [$c, .[0], .[1], .[2], .[3]] | @tsv
        ' <<<"$DEPLOY_JSON")"

        if [[ -n "$PROBES_JSON" ]]; then
          echo -e "        ${BOLD}HTTP Probes:${RESET}"
          echo "$PROBES_JSON" | awk -F'\t' '{
            printf "          • container=%-20s %-10s path=%-20s port=%-5s scheme=%s\n", $1, $2, $3, $4, $5
          }'
        else
          warn "        (no readiness/liveness/startup HTTP probe)"
        fi
      else
        warn "      Deployment not located (selector match failed and no Pod to trace)"
        DEPLOY_JSON=""
        PROBES_JSON=""
      fi

      # --------------------------------------------------------------------- #
      # Step 7: Generate E2E URL + curl commands
      # --------------------------------------------------------------------- #
      echo ""
      echo -e "    ${BOLD}🔗 E2E URLs (rule[$rule_idx] / ${B_NAME}:${B_PORT})${RESET}"

      # Build probe path list (if Deployment missing, fall back to /health but not silently)
      declare -A SEEN_PROBE=()
      declare -a PROBE_PATHS=()
      if [[ -n "${PROBES_JSON:-}" ]]; then
        while IFS=$'\t' read -r _pc _pt pp _rest; do
          [[ -z "$pp" ]] && continue
          if [[ -z "${SEEN_PROBE[$pp]:-}" ]]; then
            SEEN_PROBE[$pp]=1
            PROBE_PATHS+=("$pp")
          fi
        done <<<"$PROBES_JSON"
      fi
      [[ ${#PROBE_PATHS[@]} -eq 0 ]] && PROBE_PATHS=("/health")

      AUTHORITY="$(url_authority "$URL_SCHEME" "$URL_PORT")"
      ROUTE_GENERATED=0
      while IFS=$'\t' read -r MATCH_TYPE MATCH_PATH _HEADERS _QP _METHOD; do
        [[ -z "$MATCH_TYPE" ]] && continue
        for PROBE_PATH in "${PROBE_PATHS[@]}"; do
          [[ -z "$PROBE_PATH" ]] && continue
          FINAL_PATH="$(join_path "$MATCH_TYPE" "$MATCH_PATH" "$PROBE_PATH")"
          FULL_URL="${URL_SCHEME}://${AUTHORITY}${FINAL_PATH}"
          ALL_E2E_URLS+=("$FULL_URL")

          # Method A: Local DNS/Hosts ready
          echo -e "      ${DIM}Method A (local DNS/Hosts ready):${RESET}"
          echo -e "        ${CYAN}curl -k -v --max-time ${CURL_TIMEOUT} \"${FULL_URL}\"${RESET}"

          # Method B: SNI --resolve bypass DNS
          if [[ -n "$GATEWAY_IP" ]]; then
            echo -e "      ${DIM}Method B (SNI --resolve bypass DNS, force via Gateway):${RESET}"
            RESOLVE_HOST="${INPUT_FQDN}:${URL_PORT}:${GATEWAY_IP}"
            CURL_CMD="curl -k -v --max-time ${CURL_TIMEOUT} --resolve \"${RESOLVE_HOST}\" \"${FULL_URL}\""
            echo -e "        ${BOLD}${YELLOW}${CURL_CMD}${RESET}"
            ALL_CURL_COMMANDS+=("$CURL_CMD")
            ALL_VALIDATION+=("${FULL_URL}"$'\t'"${URL_PORT}"$'\t'"${GATEWAY_IP}")
          else
            ALL_CURL_COMMANDS+=("curl -k -v --max-time ${CURL_TIMEOUT} \"${FULL_URL}\"")
            ALL_VALIDATION+=("${FULL_URL}"$'\t'"${URL_PORT}"$'\t'"")
          fi

          # Method C: Direct IP + Host header (internal network debugging)
          if [[ -n "$GATEWAY_IP" ]]; then
            echo -e "      ${DIM}Method C (direct IP + Host header, internal/cross-segment debugging):${RESET}"
            echo -e "        ${CYAN}curl -k -v --max-time ${CURL_TIMEOUT} -H \"Host: ${INPUT_FQDN}\" \"${URL_SCHEME}://${GATEWAY_IP}${FINAL_PATH}\"${RESET}"
          fi
          echo ""
          ROUTE_GENERATED=$((ROUTE_GENERATED + 1))
        done
      done <<<"$MATCH_LINES"

      if [[ $ROUTE_GENERATED -eq 0 ]]; then
        warn "      (no URL generated — may be match parse failure)"
      else
        ok "      this backend generated ${BOLD}${ROUTE_GENERATED}${RESET} E2E URL(s)"
      fi

    done <<<"$BACKENDS"
  done  # end for rule_idx

done <<<"$MATCHED_ROUTES"

# --------------------------------------------------------------------------- #
# Step 8: Summary + deduplication
# --------------------------------------------------------------------------- #
header "Step 8 / 6 — E2E Summary (deduplicate & sort)"

if [[ ${#ALL_E2E_URLS[@]} -eq 0 ]]; then
  err "No E2E URL generated, please check the chain configuration above"
  exit 1
fi

UNIQUE_URLS=($(printf '%s\n' "${ALL_E2E_URLS[@]}" | awk 'NF && !seen[$0]++'))
UNIQUE_CURLS=($(printf '%s\n' "${ALL_CURL_COMMANDS[@]}" | awk 'NF && !seen[$0]++'))

echo -e "  ${BOLD}All unique URLs (${#UNIQUE_URLS[@]}):${RESET}"
printf '    %s\n' "${UNIQUE_URLS[@]}"

echo ""
echo -e "  ${BOLD}All curl commands (${#UNIQUE_CURLS[@]}):${RESET}"
printf '    %s\n' "${UNIQUE_CURLS[@]}"

# --------------------------------------------------------------------------- #
# Step 9 (optional): Actually run curl validation
# --------------------------------------------------------------------------- #
if [[ "$VALIDATE" == "true" ]]; then
  header "Step 9 / 6 — Actual curl validation"
  warn "About to execute actual HTTP requests against generated URLs (--max-time=${CURL_TIMEOUT}s)..."

  # Deduplicate ALL_VALIDATION
  UNIQUE_VAL=($(printf '%s\n' "${ALL_VALIDATION[@]}" | awk 'NF && !seen[$0]++'))

  PASS=0; WARN_C=0; FAIL_C=0
  for line in "${UNIQUE_VAL[@]}"; do
    IFS=$'\t' read -r url port gw_ip <<<"$line"
    [[ -z "$url" ]] && continue

    # Re-run once to get code for counting (simplified, just rely on function's color distinction)
    # Here use a temp array to collect lines, then count
    OUT="$(do_validate_one "$url" "$port" "$gw_ip")"
    echo "$OUT"

    # Rough ANSI-color-based statistics (simplified)
    if   [[ "$OUT" == *"${GREEN}HTTP 2"* ]]; then ((PASS+=1));
    elif [[ "$OUT" == *"${YELLOW}HTTP"* || "$OUT" == *"${YELLOW}CONN"* ]]; then ((WARN_C+=1));
    else ((FAIL_C+=1)); fi
  done

  echo ""
  echo -e "  ${BOLD}Validation summary:${RESET} ${GREEN}PASS=${PASS}${RESET}  ${YELLOW}WARN=${WARN_C}${RESET}  ${RED}FAIL=${FAIL_C}${RESET}"
fi

# --------------------------------------------------------------------------- #
# End
# --------------------------------------------------------------------------- #
divider
success "Chain inspection complete! Total ${BOLD}${#UNIQUE_URLS[@]}${RESET} unique E2E URL(s), ${BOLD}${#UNIQUE_CURLS[@]}${RESET} curl command(s)"
echo -e "  ${DIM}Tip: Copy the curl commands to run SNI-bypass-DNS E2E validation in your terminal.${RESET}"
divider
echo ""
