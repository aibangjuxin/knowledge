# Shell Scripts Collection

Generated on: 2026-06-04 11:02:51
Directory: /Users/lex/git/knowledge/cloud/k8s/k8s-gateway/k8s-gateway-e2e

## `k8s-gateway-fqdn-minimax-eng.sh`

```bash
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

```

## `k8s-gateway-fqdn-minimax.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# k8s-gateway-fqdn-minimax.sh — K8s Gateway FQDN 链路深度探索 & E2E URL 构建器
#
# 用途: 给定一个 Ingress 域名 (FQDN)，自动穿透 K8s Gateway API 核心链路:
#       HTTPRoute ──► ParentRef(Gateway/ListenerSet)
#                    ──► BackendRef(Service, 支持跨 NS) ──► DestinationRule
#                    ──► Service ──► Deployment ──► Probes (readiness/liveness/startup)
#       并生成精准的、可直接用于 E2E 测试的 curl 验证命令(自动适配 listener
#       协议、SNI --resolve、PathPrefix/Exact/Regex 路径合并)。
#
# 用法: ./k8s-gateway-fqdn-minimax.sh <FQDN> [TENANT_NAMESPACE] [--validate]
#
# 设计融合:
#   - 主架构借鉴 k8s-gateway-fqdn-gemini.sh(纯 jq 流水线、跨 NS 扫描、配色)
#   - Listener 协议/端口检测借鉴 k8s-gateway-fqdn-chatgpt.sh(自动 http/https)
#   - Probe 全枚举借鉴 chatgpt (readiness / liveness / startup, 跨 container)
#   - 路径合并逻辑借鉴 chatgpt join_prefix_probe (PathPrefix/Exact/Regex)
#   - Cross-namespace backendRef 借鉴 chatgpt
#   - 可选 --validate curl 验证借鉴 chatgpt + claude
#   - 修复昨日版 fqdn.sh 的 `kubectl apply` 误用、HTTPRoutes 拼写错
#   - 修复 claude.sh 的 hardcoded /health、`((idx++)) || true` 不可靠循环
#   - 修复 chatgpt.sh 的 TENANT_NS / --validate 参数冲突(改为标准 --flag)
#
# 依赖: kubectl, jq, curl
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
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
# 默认配置(支持环境变量覆盖)
# --------------------------------------------------------------------------- #
GATEWAY_NS="${GATEWAY_NS:-abjx-gw-int}"
GATEWAY_NAME="${GATEWAY_NAME:-abjx-gw-int}"
DEFAULT_SCHEME="${DEFAULT_SCHEME:-https}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

# --------------------------------------------------------------------------- #
# 参数解析(标准 --flag 风格, 修复 chatgpt.sh 的 TENANT_NS/--validate 冲突)
# --------------------------------------------------------------------------- #
usage() {
  echo -e "$(cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") <FQDN> [TENANT_NAMESPACE] [--validate|-v] [--help|-h]

${BOLD}参数说明:${RESET}
  <FQDN>              目标 Ingress 域名 (例如: api.team1-int.uk.aibang.local)
  [TENANT_NAMESPACE]  租户命名空间(可选；省略时先尝试从 FQDN 第 2 段推断, 失败则全集群扫)
  --validate, -v      可选: 实际执行 curl 验证生成的 E2E URL

${BOLD}环境变量覆盖:${RESET}
  GATEWAY_NS          Gateway 所在 namespace(默认: ${GATEWAY_NS})
  GATEWAY_NAME        Gateway 资源名(默认: ${GATEWAY_NAME})
  DEFAULT_SCHEME      listener 协议无法判断时使用的 URL scheme(默认: ${DEFAULT_SCHEME})
  CURL_TIMEOUT        验证时的 curl 超时秒数(默认: ${CURL_TIMEOUT})

${BOLD}使用示例:${RESET}
  $(basename "$0") api.team1-int.uk.aibang.local
  $(basename "$0") app.team2.example.com team2
  $(basename "$0") api.team1-int.uk.aibang.local team1-int --validate

${BOLD}链路勘测范围:${RESET}
  HTTPRoute → ParentRef(Gateway / ListenerSet) → Listener 协议/端口
           → BackendRef(Service, 支持跨 NS) → DestinationRule
           → Service (ClusterIP, selector, port mapping)
           → Deployment (跨 container 枚举 readiness/liveness/startup probe)
           → 生成 E2E URL + 多种 curl 验证命令 (SNI / IP 直连 / DNS 依赖)

EOF
)"
  exit 1
}

INPUT_FQDN=""
TENANT_NS=""
VALIDATE="false"

# 第一遍扫描: 收集 FQDN 与 TENANT_NS(前两个非 flag 参数)
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --validate|-v) VALIDATE="true" ;;
    --help|-h)     usage ;;
    --*)           err "未知 flag: $arg"; exit 1 ;;
    *)             POSITIONAL+=("$arg") ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 ]] && INPUT_FQDN="${POSITIONAL[0]}"
[[ ${#POSITIONAL[@]} -ge 2 ]] && TENANT_NS="${POSITIONAL[1]}"
[[ ${#POSITIONAL[@]} -gt 2 ]] && { err "多余的位置参数: ${POSITIONAL[*]:2}"; usage; }

[[ -z "$INPUT_FQDN" ]] && usage

# --------------------------------------------------------------------------- #
# 依赖检查
# --------------------------------------------------------------------------- #
for cmd in kubectl jq curl; do
  if ! command -v "$cmd" &>/dev/null; then
    err "本脚本依赖 '$cmd' 命令, 请先安装。"
    exit 1
  fi
done

# --------------------------------------------------------------------------- #
# 工具函数
# --------------------------------------------------------------------------- #
# 安全地读取 JSON(失败返回空 items)
kj() { kubectl "$@" -o json 2>/dev/null || echo '{"items":[]}'; }

# 规范化路径(去除重复 /,确保以 / 开头)
norm_path() {
  local p="${1:-/}"
  [[ -z "$p" ]] && p="/"
  [[ "${p:0:1}" != "/" ]] && p="/$p"
  printf '%s' "$p" | sed -E 's#/+#/#g'
}

# 合并路由 path 与 probe path(借鉴 chatgpt join_prefix_probe, 并增强)
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
      # 拼接时保留 probe 路径的前导 '/', 再把多余 '/' 折叠为单个
      printf '%s%s' "$route_path" "$probe_path" | sed -E 's#/+#/#g'
      ;;
    *)
      printf '%s' "$route_path"
      ;;
  esac
}

# URL authority builder: 仅在非默认端口时附加 :port
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

# 对单个 URL 执行 curl 验证并打印结果(避免在 pipe 子 shell 中使用 case)
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
    401|403)         printf "    %sHTTP %s%s  %s (auth-required, 链路通)\n" "$YELLOW" "$code" "$RESET" "$url" ;;
    404)             printf "    %sHTTP %s%s  %s (404 — 后端路由不匹配!)\n" "$RED" "$code" "$RESET" "$url" ;;
    000)             printf "    %sCONN-FAIL%s  %s (网络不可达)\n" "$RED" "$RESET" "$url" ;;
    *)               printf "    %sHTTP %s%s  %s\n" "$RED" "$code" "$RESET" "$url" ;;
  esac
}

# --------------------------------------------------------------------------- #
# 横幅
# --------------------------------------------------------------------------- #
echo ""
divider
echo -e "  ${BOLD}${MAGENTA}🛰️  K8s Gateway FQDN 链路深度勘测工具 (MiniMax 增强版)${RESET}"
echo -e "  目标域名:      ${BOLD}${GREEN}${INPUT_FQDN}${RESET}"
echo -e "  租户命名空间:  ${BOLD}${TENANT_NS:-<auto>}${RESET}"
echo -e "  Gateway:       ${BOLD}${GATEWAY_NS}/${GATEWAY_NAME}${RESET}"
echo -e "  验证模式:      ${BOLD}${VALIDATE}${RESET}"
divider

# --------------------------------------------------------------------------- #
# 智能 tenant namespace 推断(从 FQDN 第 2 段)— 借鉴昨日 fqdn.sh 的启发
# --------------------------------------------------------------------------- #
if [[ -z "$TENANT_NS" ]]; then
  CANDIDATE_NS="$(echo "$INPUT_FQDN" | awk -F. '{print $2}')"
  if [[ -n "$CANDIDATE_NS" ]]; then
    if kj get namespace "$CANDIDATE_NS" 2>/dev/null | grep -q "\"name\":\"$CANDIDATE_NS\""; then
      TENANT_NS="$CANDIDATE_NS"
      info "从 FQDN 第 2 段智能推断 tenant namespace: ${BOLD}${TENANT_NS}${RESET}"
    else
      info "FQDN 第 2 段 '$CANDIDATE_NS' 不是有效 namespace, 将进行全集群 HTTPRoute 扫描。"
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# Step 1: 智能 FQDN 路由检索(跨 NS, 支持 exact + 通配符)
# --------------------------------------------------------------------------- #
header "Step 1 / 6 — HTTPRoute 智能发现"

info "扫描绑定域名 ${INPUT_FQDN} 的 HTTPRoute${TENANT_NS:+ (限定 NS: $TENANT_NS)}..."

if [[ -n "$TENANT_NS" ]]; then
  ROUTES_JSON="$(kj get httproute -n "$TENANT_NS")"
else
  ROUTES_JSON="$(kj get httproute -A)"
fi

# 用 jq 做严格匹配(借鉴 chatgpt 的 host_match, 修复 gemini 不去尾点的问题)
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
  err "未发现任何 HTTPRoute 绑定域名: ${INPUT_FQDN}"
  warn "集群中现有 HTTPRoute 列表(供参考):"
  jq -r '.items[]? | [.metadata.namespace, .metadata.name, ((.spec.hostnames // ["<empty>"]) | join(","))] | @tsv' <<<"$ROUTES_JSON" \
    | awk -F'\t' '{printf "    %-30s %-40s hostnames=%s\n", $1, $2, $3}' >&2
  exit 1
fi

ROUTE_COUNT="$(printf '%s\n' "$MATCHED_ROUTES" | wc -l | tr -d ' ')"
ok "匹配到 ${BOLD}${ROUTE_COUNT}${RESET} 个 HTTPRoute"
printf '%s\n' "$MATCHED_ROUTES" | awk -F'\t' '{printf "    • %s/%s\n      hostnames: %s\n", $1, $2, $3}'

# --------------------------------------------------------------------------- #
# 收集器
# --------------------------------------------------------------------------- #
declare -a ALL_E2E_URLS=()        # 完整 URL(供汇总)
declare -a ALL_CURL_COMMANDS=()   # 完整 curl 命令
declare -a ALL_VALIDATION=()      # 用于 --validate: URL<TAB>port<TAB>gw_ip

# --------------------------------------------------------------------------- #
# Step 2 ~ 6: 逐个 HTTPRoute 深入链路
# --------------------------------------------------------------------------- #
while IFS=$'\t' read -r ROUTE_NS ROUTE_NAME ROUTE_HOSTNAMES; do
  [[ -z "$ROUTE_NS" || -z "$ROUTE_NAME" ]] && continue

  header "HTTPRoute: ${BOLD}${ROUTE_NS}/${ROUTE_NAME}${RESET}"
  ROUTE_JSON="$(kj get httproute "$ROUTE_NAME" -n "$ROUTE_NS")"
  [[ -z "$ROUTE_JSON" ]] && { warn "无法读取 HTTPRoute, 跳过"; continue; }

  # 2.1 显示 hostnames
  subdiv
  echo -e "  ${BOLD}Hostnames:${RESET}"
  jq -r '.spec.hostnames[]? // empty' <<<"$ROUTE_JSON" | sed 's/^/    - /'

  # 2.2 显示 ParentRefs(支持 Gateway 与 ListenerSet)
  echo ""
  echo -e "  ${BOLD}ParentRefs (Gateway / ListenerSet):${RESET}"

  URL_SCHEME="$DEFAULT_SCHEME"
  URL_PORT="443"
  GATEWAY_IP=""

  PARENTS_JSON="$(jq -c '.spec.parentRefs[]? // empty' <<<"$ROUTE_JSON")"
  if [[ -z "$PARENTS_JSON" ]]; then
    warn "    HTTPRoute 无 spec.parentRefs (可能未被任何 Gateway 接管)"
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
        warn "      Gateway ${P_NS}/${P_NAME} 无法读取"
        continue
      fi

      # 提取 Gateway status IP(优先 status.addresses)
      THIS_IP="$(jq -r '.status.addresses[]? | select(.type == "IP" or .type == "Hostname" or .type == null) | .value' <<<"$GW_JSON" | head -n 1)"
      [[ -z "$GATEWAY_IP" && -n "$THIS_IP" ]] && GATEWAY_IP="$THIS_IP"

      # 显示 listener 详情
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

      # 协议/端口检测(取第一个匹配的 listener)
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

  # 兜底: 如果 parentRefs 没拿到 IP, 去 LoadBalancer Service 里找
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
  echo -e "  ${BOLD}检测结果:${RESET}"
  echo -e "    • listener scheme: ${CYAN}${URL_SCHEME}${RESET}"
  echo -e "    • listener port:   ${CYAN}${URL_PORT}${RESET}"
  echo -e "    • gateway IP:      ${CYAN}${GATEWAY_IP:-<未找到>}${RESET}"

  # 2.3 显示 HTTPRoute status.parents(绑定状态)
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
    warn "    (无 status.parents — 路由可能尚未被 Gateway 接受)"
  fi

  # ------------------------------------------------------------------------- #
  # Step 3: 遍历 rules
  # ------------------------------------------------------------------------- #
  header "Step 3 / 6 — Rules / Matches / Backends"
  RULES_COUNT="$(jq '.spec.rules | length // 0' <<<"$ROUTE_JSON")"
  [[ "$RULES_COUNT" == "0" ]] && { warn "HTTPRoute 无 rules, 跳过"; continue; }

  for ((rule_idx=0; rule_idx<RULES_COUNT; rule_idx++)); do
    RULE_JSON="$(jq -c ".spec.rules[$rule_idx]" <<<"$ROUTE_JSON")"
    RULE_NAME="$(jq -r '.name // ""' <<<"$RULE_JSON")"

    subdiv
    echo -e "  ${BOLD}⚡ Rule[$rule_idx]${RULE_NAME:+ (name=$RULE_NAME)}${RESET}"

    # 3.1 matches — 输出 TSV: type<TAB>path<TAB>headers<TAB>queryParams<TAB>methods
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

    # 3.3 遍历 backendRefs
    BACKENDS="$(jq -c '.backendRefs[]? // empty' <<<"$RULE_JSON")"
    if [[ -z "$BACKENDS" ]]; then
      warn "  Rule[$rule_idx] 无 backendRefs"
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
        warn "      backend kind='$B_KIND' (非 Service), 跳过 Service/Deployment 链路探测"
        continue
      fi

      # --------------------------------------------------------------------- #
      # Step 4: DestinationRule(支持多种 host 形式)
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
        err "      Service ${B_NS}/${B_NAME} 未找到, 跳过"
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
      # Step 6: Deployment + Probes(跨 container, 全 probe 类型)
      # --------------------------------------------------------------------- #
      DEPLOY_NAME=""
      if [[ -n "$SVC_SELECTOR" ]]; then
        # Method A: 通过 selector 直接匹配 deploy (借鉴 gemini)
        DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -l "$SVC_SELECTOR" \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
      fi
      if [[ -z "$DEPLOY_NAME" ]]; then
        # Method B: 通过 Pod ownerReferences 溯源
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
        # Method C: 通过 Deployment spec.selector 匹配 SVC selector (借鉴 gemini)
        DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -o json 2>/dev/null \
          | jq -r --arg sel "$SVC_SELECTOR" '
              .items[]?
              | select((.spec.selector.matchLabels // {}) | to_entries | map(.key + "=" + .value) | join(",") == $sel)
              | .metadata.name
            ' | head -n 1 || true)"
      fi

      # 不再用 "$B_NAME" 兜底 (这是 claude.sh 的坑, 容易张冠李戴)
      if [[ -n "$DEPLOY_NAME" ]]; then
        DEPLOY_JSON="$(kj get deploy "$DEPLOY_NAME" -n "$B_NS")"
        READY="$(jq -r '.status.readyReplicas // 0' <<<"$DEPLOY_JSON")"
        DESIRED="$(jq -r '.spec.replicas // 0' <<<"$DEPLOY_JSON")"
        echo -e "      ${BOLD}Deployment:${RESET} ${GREEN}${B_NS}/${DEPLOY_NAME}${RESET} ready=${READY}/${DESIRED}"

        # 跨 container 枚举所有 HTTP probe(借鉴 chatgpt)
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
          warn "        (无 readiness/liveness/startup HTTP probe)"
        fi
      else
        warn "      Deployment 未定位到 (selector 匹配失败且无 Pod 可溯源)"
        DEPLOY_JSON=""
        PROBES_JSON=""
      fi

      # --------------------------------------------------------------------- #
      # Step 7: 生成 E2E URL + curl 命令
      # --------------------------------------------------------------------- #
      echo ""
      echo -e "    ${BOLD}🔗 E2E URLs (rule[$rule_idx] / ${B_NAME}:${B_PORT})${RESET}"

      # 构造 probe path 列表(若 Deployment 不存在, 用 /health 兜底但不静默)
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

          # 方法 A: 本地 DNS/Hosts 已就绪
          echo -e "      ${DIM}方法 A (本地 DNS/Hosts 就绪):${RESET}"
          echo -e "        ${CYAN}curl -k -v --max-time ${CURL_TIMEOUT} \"${FULL_URL}\"${RESET}"

          # 方法 B: SNI --resolve 绕过 DNS
          if [[ -n "$GATEWAY_IP" ]]; then
            echo -e "      ${DIM}方法 B (SNI --resolve 绕过 DNS, 强制走 Gateway):${RESET}"
            RESOLVE_HOST="${INPUT_FQDN}:${URL_PORT}:${GATEWAY_IP}"
            CURL_CMD="curl -k -v --max-time ${CURL_TIMEOUT} --resolve \"${RESOLVE_HOST}\" \"${FULL_URL}\""
            echo -e "        ${BOLD}${YELLOW}${CURL_CMD}${RESET}"
            ALL_CURL_COMMANDS+=("$CURL_CMD")
            ALL_VALIDATION+=("${FULL_URL}"$'\t'"${URL_PORT}"$'\t'"${GATEWAY_IP}")
          else
            ALL_CURL_COMMANDS+=("curl -k -v --max-time ${CURL_TIMEOUT} \"${FULL_URL}\"")
            ALL_VALIDATION+=("${FULL_URL}"$'\t'"${URL_PORT}"$'\t'"")
          fi

          # 方法 C: IP 直连 + Host 头(内网调试用)
          if [[ -n "$GATEWAY_IP" ]]; then
            echo -e "      ${DIM}方法 C (IP 直连 + Host 头, 内网/跨网段调试):${RESET}"
            echo -e "        ${CYAN}curl -k -v --max-time ${CURL_TIMEOUT} -H \"Host: ${INPUT_FQDN}\" \"${URL_SCHEME}://${GATEWAY_IP}${FINAL_PATH}\"${RESET}"
          fi
          echo ""
          ROUTE_GENERATED=$((ROUTE_GENERATED + 1))
        done
      done <<<"$MATCH_LINES"

      if [[ $ROUTE_GENERATED -eq 0 ]]; then
        warn "      (未生成任何 URL — 可能是 match 解析失败)"
      else
        ok "      本 backend 生成 ${BOLD}${ROUTE_GENERATED}${RESET} 个 E2E URL"
      fi

    done <<<"$BACKENDS"
  done  # end for rule_idx

done <<<"$MATCHED_ROUTES"

# --------------------------------------------------------------------------- #
# Step 8: 汇总 + 唯一化
# --------------------------------------------------------------------------- #
header "Step 8 / 6 — E2E 汇总 (去重 & 排序)"

if [[ ${#ALL_E2E_URLS[@]} -eq 0 ]]; then
  err "未生成任何 E2E URL, 请检查上述链路配置"
  exit 1
fi

UNIQUE_URLS=($(printf '%s\n' "${ALL_E2E_URLS[@]}" | awk 'NF && !seen[$0]++'))
UNIQUE_CURLS=($(printf '%s\n' "${ALL_CURL_COMMANDS[@]}" | awk 'NF && !seen[$0]++'))

echo -e "  ${BOLD}全部唯一 URL 列表 (${#UNIQUE_URLS[@]}):${RESET}"
printf '    %s\n' "${UNIQUE_URLS[@]}"

echo ""
echo -e "  ${BOLD}全部 curl 命令 (${#UNIQUE_CURLS[@]}):${RESET}"
printf '    %s\n' "${UNIQUE_CURLS[@]}"

# --------------------------------------------------------------------------- #
# Step 9 (可选): 实际执行 curl 验证
# --------------------------------------------------------------------------- #
if [[ "$VALIDATE" == "true" ]]; then
  header "Step 9 / 6 — 实际 curl 验证"
  warn "即将对生成的 URL 执行实际 HTTP 请求 (--max-time=${CURL_TIMEOUT}s)..."

  # 去重 ALL_VALIDATION
  UNIQUE_VAL=($(printf '%s\n' "${ALL_VALIDATION[@]}" | awk 'NF && !seen[$0]++'))

  PASS=0; WARN_C=0; FAIL_C=0
  for line in "${UNIQUE_VAL[@]}"; do
    IFS=$'\t' read -r url port gw_ip <<<"$line"
    [[ -z "$url" ]] && continue

    # 重新跑一次拿 code 以便计数(简单起见, 直接靠函数内的颜色区分)
    # 这里用临时数组收集行, 然后统计
    OUT="$(do_validate_one "$url" "$port" "$gw_ip")"
    echo "$OUT"

    # 通过 ANSI 颜色粗略统计(简化)
    if   [[ "$OUT" == *"${GREEN}HTTP 2"* ]]; then ((PASS+=1));
    elif [[ "$OUT" == *"${YELLOW}HTTP"* || "$OUT" == *"${YELLOW}CONN"* ]]; then ((WARN_C+=1));
    else ((FAIL_C+=1)); fi
  done

  echo ""
  echo -e "  ${BOLD}验证汇总:${RESET} ${GREEN}PASS=${PASS}${RESET}  ${YELLOW}WARN=${WARN_C}${RESET}  ${RED}FAIL=${FAIL_C}${RESET}"
fi

# --------------------------------------------------------------------------- #
# 结束
# --------------------------------------------------------------------------- #
divider
success "链路勘测完成！共 ${BOLD}${#UNIQUE_URLS[@]}${RESET} 个唯一 E2E URL, ${BOLD}${#UNIQUE_CURLS[@]}${RESET} 个 curl 命令"
echo -e "  ${DIM}提示: 复制 curl 命令即可在终端执行 SNI 绕过 DNS 的 E2E 验证。${RESET}"
divider
echo ""

```

## `k8s-gateway-fqdn-chatgpt.sh`

```bash
#!/usr/bin/env bash
# K8s Gateway FQDN Resource Explorer and E2E URL Builder
# Usage:
#   ./k8s-gateway-fqdn-chatgpt.sh <fqdn> [namespace] [--validate]
#
# Given a public FQDN, this script traces the Gateway API chain:
#   HTTPRoute -> Gateway listener -> DestinationRule -> Service -> Deployment
# and prints complete client-facing URLs that can be used for E2E tests.

set -euo pipefail

FQDN="${1:-}"
TENANT_NS="${2:-}"
VALIDATE="${3:-}"

if [[ "${TENANT_NS:-}" == "--validate" ]]; then
  VALIDATE="--validate"
  TENANT_NS=""
fi

GATEWAY_NS_DEFAULT="${GATEWAY_NS:-infrastructure}"
GATEWAY_NAME_DEFAULT="${GATEWAY_NAME:-central-gateway}"
DEFAULT_SCHEME="${DEFAULT_SCHEME:-https}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; }
section() { echo ""; echo -e "${BOLD}# $*${NC}"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <fqdn> [namespace] [--validate]

Examples:
  $(basename "$0") api.team-a.example.com
  $(basename "$0") api.team-a.example.com team-a
  $(basename "$0") api.team-a.example.com team-a --validate

Environment overrides:
  GATEWAY_NS       Default gateway namespace fallback. Current: ${GATEWAY_NS_DEFAULT}
  GATEWAY_NAME     Default gateway name fallback. Current: ${GATEWAY_NAME_DEFAULT}
  DEFAULT_SCHEME   URL scheme when listener protocol cannot be detected. Current: ${DEFAULT_SCHEME}
EOF
  exit 1
}

[[ -z "$FQDN" ]] && usage

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command not found: $1"
    exit 1
  fi
}

need_cmd kubectl
need_cmd jq

kubectl_json() {
  kubectl "$@" -o json 2>/dev/null || true
}

normalize_path() {
  local p="${1:-/}"
  [[ -z "$p" ]] && p="/"
  [[ "$p" != /* ]] && p="/$p"
  printf '%s' "$p" | sed -E 's#/+#/#g'
}

join_prefix_probe() {
  local match_type="$1"
  local route_path
  local probe_path
  route_path="$(normalize_path "$2")"
  probe_path="$(normalize_path "$3")"

  case "$match_type" in
    Exact)
      printf '%s' "$route_path"
      ;;
    PathPrefix|"")
      if [[ "$route_path" == "/" ]]; then
        printf '%s' "$probe_path"
      elif [[ "$probe_path" == "$route_path" || "$probe_path" == "$route_path/"* ]]; then
        printf '%s' "$probe_path"
      else
        printf '%s/%s' "${route_path%/}" "${probe_path#/}" | sed -E 's#/+#/#g'
      fi
      ;;
    *)
      printf '%s' "$route_path"
      ;;
  esac
}

unique_lines() {
  awk 'NF && !seen[$0]++'
}

url_authority() {
  local scheme="$1"
  local port="$2"
  if [[ "$scheme" == "https" && "$port" == "443" ]] || [[ "$scheme" == "http" && "$port" == "80" ]] || [[ -z "$port" ]]; then
    printf '%s' "$FQDN"
  else
    printf '%s:%s' "$FQDN" "$port"
  fi
}

print_banner() {
  echo ""
  echo "============================================================"
  echo "  K8s Gateway FQDN Explorer"
  echo "  FQDN      : $FQDN"
  echo "  Namespace : ${TENANT_NS:-auto}"
  echo "============================================================"
}

print_banner

section "Discover HTTPRoute"

if [[ -n "$TENANT_NS" ]]; then
  ROUTES_JSON="$(kubectl_json get httproute -n "$TENANT_NS")"
else
  ROUTES_JSON="$(kubectl_json get httproute -A)"
fi

if [[ -z "$ROUTES_JSON" ]]; then
  fail "Could not read HTTPRoute resources${TENANT_NS:+ in namespace $TENANT_NS}."
  exit 1
fi

if [[ "$(jq '.items // [] | length' <<<"$ROUTES_JSON")" == "0" ]]; then
  fail "No HTTPRoute resources found${TENANT_NS:+ in namespace $TENANT_NS}."
  exit 1
fi

MATCHED_ROUTES="$(jq -r --arg fqdn "${FQDN%.}" '
  def norm: rtrimstr(".");
  def host_match($fqdn; $host):
    ($host | norm) as $h |
    if $h == $fqdn then true
    elif ($h | startswith("*.")) then
      ($h | ltrimstr("*.")) as $suffix |
      (($fqdn | endswith("." + $suffix)) and (($fqdn | split(".") | length) == ($h | split(".") | length)))
    else false
    end;

  .items[]
  | select(any(.spec.hostnames[]?; host_match($fqdn; .)))
  | [.metadata.namespace, .metadata.name, ((.spec.hostnames // []) | join(","))]
  | @tsv
' <<<"$ROUTES_JSON")"

if [[ -z "$MATCHED_ROUTES" ]]; then
  warn "No direct HTTPRoute spec.hostnames match for $FQDN. Listing known hostnames for quick check:"
  jq -r '.items[] | [.metadata.namespace, .metadata.name, ((.spec.hostnames // ["<empty>"]) | join(","))] | @tsv' <<<"$ROUTES_JSON" |
    sed 's/^/  /'
  exit 1
fi

ROUTE_COUNT="$(wc -l <<<"$MATCHED_ROUTES" | tr -d ' ')"
ok "Matched HTTPRoute count: $ROUTE_COUNT"
printf '%s\n' "$MATCHED_ROUTES" | awk -F'\t' '{printf "  - %s/%s hostnames=%s\n", $1, $2, $3}'

declare -a GENERATED_URLS=()
declare -a CURL_COMMANDS=()
declare -a VALIDATION_TARGETS=()

while IFS=$'\t' read -r ROUTE_NS ROUTE_NAME ROUTE_HOSTNAMES; do
  [[ -z "$ROUTE_NS" || -z "$ROUTE_NAME" ]] && continue

  section "HTTPRoute: ${ROUTE_NS}/${ROUTE_NAME}"
  ROUTE_JSON="$(kubectl_json get httproute "$ROUTE_NAME" -n "$ROUTE_NS")"
  if [[ -z "$ROUTE_JSON" ]]; then
    warn "Cannot read HTTPRoute ${ROUTE_NS}/${ROUTE_NAME}; skipping."
    continue
  fi

  echo "Hostnames:"
  jq -r '.spec.hostnames[]? // empty' <<<"$ROUTE_JSON" | sed 's/^/  - /'

  echo ""
  echo "ParentRefs and listener context:"
  PARENTS="$(jq -c '.spec.parentRefs[]? // empty' <<<"$ROUTE_JSON")"
  if [[ -z "$PARENTS" ]]; then
    warn "HTTPRoute has no spec.parentRefs."
  fi

  GATEWAY_IP=""
  URL_SCHEME="$DEFAULT_SCHEME"
  URL_PORT="443"

  while IFS= read -r parent; do
    [[ -z "$parent" ]] && continue
    P_KIND="$(jq -r '.kind // "Gateway"' <<<"$parent")"
    P_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$parent")"
    P_NAME="$(jq -r '.name' <<<"$parent")"
    P_SECTION="$(jq -r '.sectionName // ""' <<<"$parent")"

    printf '  - %s %s/%s' "$P_KIND" "$P_NS" "$P_NAME"
    [[ -n "$P_SECTION" ]] && printf ' sectionName=%s' "$P_SECTION"
    echo ""

    if [[ "$P_KIND" == "Gateway" ]]; then
      GW_JSON="$(kubectl_json get gateway "$P_NAME" -n "$P_NS")"
      if [[ -z "$GW_JSON" ]]; then
        warn "    Gateway not readable: ${P_NS}/${P_NAME}"
        continue
      fi

      THIS_IP="$(jq -r '.status.addresses[0].value // empty' <<<"$GW_JSON")"
      [[ -z "$GATEWAY_IP" && -n "$THIS_IP" ]] && GATEWAY_IP="$THIS_IP"

      jq -r --arg section "$P_SECTION" '
        .spec.listeners[]
        | select($section == "" or .name == $section)
        | "    listener=" + .name
          + " protocol=" + (.protocol // "<none>")
          + " port=" + ((.port // "") | tostring)
          + " hostname=" + (.hostname // "<all>")
      ' <<<"$GW_JSON"

      LISTENER_HINT="$(jq -r --arg section "$P_SECTION" '
        [.spec.listeners[]
         | select($section == "" or .name == $section)
         | {protocol: (.protocol // ""), port: (.port // 0)}][0]
        | if . == null then "" else [.protocol, (.port | tostring)] | @tsv end
      ' <<<"$GW_JSON")"
      if [[ -n "$LISTENER_HINT" ]]; then
        L_PROTOCOL="$(cut -f1 <<<"$LISTENER_HINT")"
        L_PORT="$(cut -f2 <<<"$LISTENER_HINT")"
        case "$L_PROTOCOL" in
          HTTPS|TLS) URL_SCHEME="https" ;;
          HTTP) URL_SCHEME="http" ;;
        esac
        [[ "$L_PORT" != "0" && -n "$L_PORT" ]] && URL_PORT="$L_PORT"
      fi
    elif [[ "$P_KIND" == "ListenerSet" ]]; then
      LS_JSON="$(kubectl_json get listenerset "$P_NAME" -n "$P_NS")"
      if [[ -z "$LS_JSON" ]]; then
        warn "    ListenerSet not readable: ${P_NS}/${P_NAME}"
        continue
      fi
      jq -r --arg section "$P_SECTION" '
        .spec.listeners[]
        | select($section == "" or .name == $section)
        | "    listener=" + .name
          + " protocol=" + (.protocol // "<none>")
          + " port=" + ((.port // "") | tostring)
          + " hostname=" + (.hostname // "<all>")
      ' <<<"$LS_JSON"
    fi
  done <<<"$PARENTS"

  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kubectl get svc -n "$GATEWAY_NS_DEFAULT" -o json 2>/dev/null |
      jq -r '.items[] | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // empty' |
      head -n 1 || true)"
  fi
  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kubectl get gateway "$GATEWAY_NAME_DEFAULT" -n "$GATEWAY_NS_DEFAULT" -o json 2>/dev/null |
      jq -r '.status.addresses[0].value // empty' || true)"
  fi

  echo ""
  echo "Route status parents:"
  jq -r '
    .status.parents[]?
    | "  - " + (.parentRef.namespace // "<same-ns>") + "/" + .parentRef.name
      + "/" + (.parentRef.sectionName // "<all>")
      + " " + ([.conditions[]? | .type + "=" + .status] | join(","))
  ' <<<"$ROUTE_JSON"

  section "Rules, Backends, DestinationRules, Services, Deployments"
  RULES_COUNT="$(jq '.spec.rules | length' <<<"$ROUTE_JSON")"
  if [[ "$RULES_COUNT" == "0" ]]; then
    warn "HTTPRoute has no rules."
    continue
  fi

  for ((rule_idx=0; rule_idx<RULES_COUNT; rule_idx++)); do
    RULE_JSON="$(jq -c ".spec.rules[$rule_idx]" <<<"$ROUTE_JSON")"
    RULE_NAME="$(jq -r '.name // ""' <<<"$RULE_JSON")"
    echo ""
    echo -e "${BOLD}Rule[$rule_idx]${NC}${RULE_NAME:+ name=$RULE_NAME}"

    MATCH_LINES="$(jq -r '
      if ((.matches // []) | length) == 0 then
        "PathPrefix\t/\t<none>"
      else
        .matches[]
        | [(.path.type // "PathPrefix"), (.path.value // "/"), ((.headers // []) | map(.name + "=" + .value) | join(","))]
        | @tsv
      end
    ' <<<"$RULE_JSON")"

    echo "  Matches:"
    printf '%s\n' "$MATCH_LINES" | awk -F'\t' '{printf "    - %s %s headers=%s\n", $1, $2, ($3=="" ? "<none>" : $3)}'

    REQUEST_TIMEOUT="$(jq -r '.timeouts.request // empty' <<<"$RULE_JSON")"
    BACKEND_TIMEOUT="$(jq -r '.timeouts.backendRequest // .timeouts.backendTimeout // empty' <<<"$RULE_JSON")"
    [[ -n "$REQUEST_TIMEOUT$BACKEND_TIMEOUT" ]] &&
      echo "  Timeouts: request=${REQUEST_TIMEOUT:-<none>} backend=${BACKEND_TIMEOUT:-<none>}"

    BACKENDS="$(jq -c '.backendRefs[]? // empty' <<<"$RULE_JSON")"
    if [[ -z "$BACKENDS" ]]; then
      warn "  Rule[$rule_idx] has no backendRefs."
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
      echo "  BackendRef: ${B_KIND} ${B_NS}/${B_NAME}:${B_PORT} weight=${B_WEIGHT}"
      if [[ "$B_KIND" != "Service" ]]; then
        warn "    Backend kind is not Service; downstream Service/Deployment tracing skipped."
        continue
      fi

      DR_JSON="$(kubectl_json get destinationrule -n "$B_NS")"
      MATCHED_DR="$(jq -r --arg svc "$B_NAME" --arg ns "$B_NS" '
        .items[]?
        | select(
            .spec.host == $svc
            or .spec.host == ($svc + "." + $ns)
            or .spec.host == ($svc + "." + $ns + ".svc")
            or .spec.host == ($svc + "." + $ns + ".svc.cluster.local")
            or (.spec.host | contains($svc))
          )
        | [
            .metadata.name,
            .spec.host,
            (.spec.trafficPolicy.connectionPool.tcp.connectTimeout // ""),
            (.spec.trafficPolicy.connectionPool.http.idleTimeout // ""),
            (.spec.trafficPolicy.loadBalancer.simple // (.spec.trafficPolicy.loadBalancer.consistentHash | tojson?) // "")
          ]
        | @tsv
      ' <<<"${DR_JSON:-{\"items\":[]}}" | head -n 1)"
      if [[ -n "$MATCHED_DR" ]]; then
        IFS=$'\t' read -r DR_NAME DR_HOST DR_CONNECT_TIMEOUT DR_IDLE_TIMEOUT DR_LB <<<"$MATCHED_DR"
        echo "    DestinationRule: ${B_NS}/${DR_NAME} host=${DR_HOST}"
        echo "      connectTimeout=${DR_CONNECT_TIMEOUT:-<default>} idleTimeout=${DR_IDLE_TIMEOUT:-<default>} lb=${DR_LB:-<default>}"
      else
        echo "    DestinationRule: <none>"
      fi

      SVC_JSON="$(kubectl_json get svc "$B_NAME" -n "$B_NS")"
      if [[ -z "$SVC_JSON" ]]; then
        warn "    Service not found: ${B_NS}/${B_NAME}"
        continue
      fi

      SVC_TYPE="$(jq -r '.spec.type // "ClusterIP"' <<<"$SVC_JSON")"
      SVC_CLUSTER_IP="$(jq -r '.spec.clusterIP // "<none>"' <<<"$SVC_JSON")"
      SVC_SELECTOR="$(jq -r '.spec.selector // {} | to_entries | map(.key + "=" + .value) | join(",")' <<<"$SVC_JSON")"
      SVC_PORT_INFO="$(jq -r --argjson port "${B_PORT:-0}" '
        (.spec.ports[] | select((.port // 0) == $port)) // .spec.ports[0]
        | "port=" + ((.port // "") | tostring)
          + " targetPort=" + ((.targetPort // "") | tostring)
          + " protocol=" + (.protocol // "TCP")
          + " appProtocol=" + (.appProtocol // "<none>")
      ' <<<"$SVC_JSON")"
      echo "    Service: type=${SVC_TYPE} clusterIP=${SVC_CLUSTER_IP}"
      echo "      selector=${SVC_SELECTOR:-<none>}"
      echo "      ${SVC_PORT_INFO}"

      DEPLOY_NAME=""
      if [[ -n "$SVC_SELECTOR" ]]; then
        POD_JSON="$(kubectl_json get pods -n "$B_NS" -l "$SVC_SELECTOR")"
        RS_NAME="$(jq -r '.items[0].metadata.ownerReferences[]? | select(.kind == "ReplicaSet") | .name' <<<"${POD_JSON:-{\"items\":[]}}" | head -n 1)"
        if [[ -n "$RS_NAME" ]]; then
          DEPLOY_NAME="$(kubectl get rs "$RS_NAME" -n "$B_NS" -o json 2>/dev/null |
            jq -r '.metadata.ownerReferences[]? | select(.kind == "Deployment") | .name' | head -n 1 || true)"
        fi
        if [[ -z "$DEPLOY_NAME" ]]; then
          DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -o json 2>/dev/null |
            jq -r --argjson sel "$(jq -c '.spec.selector // {}' <<<"$SVC_JSON")" '
              .items[]
              | select(
                  ($sel | to_entries) as $s
                  | all($s[]; .spec.selector.matchLabels[.key] == .value)
                )
              | .metadata.name
            ' | head -n 1 || true)"
        fi
      fi
      [[ -z "$DEPLOY_NAME" ]] && DEPLOY_NAME="$B_NAME"

      DEPLOY_JSON="$(kubectl_json get deploy "$DEPLOY_NAME" -n "$B_NS")"
      if [[ -z "$DEPLOY_JSON" ]]; then
        warn "    Deployment not found by selector/name: ${B_NS}/${DEPLOY_NAME}"
        PROBE_PATHS="/health"
      else
        READY="$(jq -r '.status.readyReplicas // 0' <<<"$DEPLOY_JSON")"
        DESIRED="$(jq -r '.spec.replicas // 0' <<<"$DEPLOY_JSON")"
        UPDATED="$(jq -r '.status.updatedReplicas // 0' <<<"$DEPLOY_JSON")"
        echo "    Deployment: ${B_NS}/${DEPLOY_NAME} ready=${READY}/${DESIRED} updated=${UPDATED}"

        PROBES="$(jq -r '
          .spec.template.spec.containers[]
          | .name as $c
          | [
              ["readiness", .readinessProbe.httpGet.path, (.readinessProbe.httpGet.port // ""), (.readinessProbe.httpGet.scheme // "HTTP")],
              ["liveness", .livenessProbe.httpGet.path, (.livenessProbe.httpGet.port // ""), (.livenessProbe.httpGet.scheme // "HTTP")],
              ["startup", .startupProbe.httpGet.path, (.startupProbe.httpGet.port // ""), (.startupProbe.httpGet.scheme // "HTTP")]
            ][]
          | select(.[1] != null and .[1] != "")
          | [$c, .[0], .[1], (.[2] | tostring), .[3]]
          | @tsv
        ' <<<"$DEPLOY_JSON")"

        if [[ -n "$PROBES" ]]; then
          echo "      HTTP probes:"
          printf '%s\n' "$PROBES" |
            awk -F'\t' '{printf "        - container=%s type=%s path=%s port=%s scheme=%s\n", $1, $2, $3, $4, $5}'
          PROBE_PATHS="$(printf '%s\n' "$PROBES" | awk -F'\t' '{print $3}' | unique_lines)"
        else
          warn "      No HTTP readiness/liveness/startup probe found; using /health fallback for URL generation."
          PROBE_PATHS="/health"
        fi
      fi

      echo "    Generated E2E URLs:"
      while IFS=$'\t' read -r MATCH_TYPE MATCH_PATH MATCH_HEADERS; do
        [[ -z "$MATCH_TYPE" ]] && continue
        while IFS= read -r PROBE_PATH; do
          [[ -z "$PROBE_PATH" ]] && continue
          FINAL_PATH="$(join_prefix_probe "$MATCH_TYPE" "$MATCH_PATH" "$PROBE_PATH")"
          URL="${URL_SCHEME}://$(url_authority "$URL_SCHEME" "$URL_PORT")${FINAL_PATH}"
          echo "      - $URL"
          GENERATED_URLS+=("$URL")
          VALIDATION_TARGETS+=("${URL}"$'\t'"${URL_PORT}"$'\t'"${GATEWAY_IP}")

          if [[ -n "$GATEWAY_IP" ]]; then
            CURL_COMMANDS+=("curl -k -v --max-time 10 --resolve '${FQDN}:${URL_PORT}:${GATEWAY_IP}' '${URL}'")
          else
            CURL_COMMANDS+=("curl -k -v --max-time 10 '${URL}'")
          fi
        done <<<"$PROBE_PATHS"
      done <<<"$MATCH_LINES"
    done <<<"$BACKENDS"
  done
done <<<"$MATCHED_ROUTES"

section "Final E2E URL Summary"
if [[ ${#GENERATED_URLS[@]} -eq 0 ]]; then
  fail "No E2E URLs generated."
  exit 1
fi

printf '%s\n' "${GENERATED_URLS[@]}" | unique_lines | sed 's/^/  - /'

echo ""
echo "Curl commands:"
printf '%s\n' "${CURL_COMMANDS[@]}" | unique_lines | sed 's/^/  /'

if [[ "$VALIDATE" == "--validate" ]]; then
  section "Optional curl validation"
  printf '%s\n' "${VALIDATION_TARGETS[@]}" | unique_lines | while IFS=$'\t' read -r url port gateway_ip; do
    [[ -z "$url" ]] && continue
    curl_args=(-k -s -o /dev/null -w '%{http_code}' --max-time 10)
    if [[ -n "${gateway_ip:-}" ]]; then
      curl_args+=(--resolve "${FQDN}:${port}:${gateway_ip}")
    fi
    code="$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo "000")"
    case "$code" in
      200|201|202|204) ok "HTTP $code $url" ;;
      301|302|307|308) warn "HTTP $code redirect $url" ;;
      401|403) warn "HTTP $code auth required $url" ;;
      *) fail "HTTP $code $url" ;;
    esac
  done
fi

```

## `k8s-gateway-fqdn-claude.sh`

```bash
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
```

## `k8s-gateway-fqdn-gemini.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# k8s-gateway-fqdn-gemini.sh — 智能 K8s Gateway 域名链路深度探索与 E2E URL 构建器
#
# 用途: 给定一个 Ingress 域名 (FQDN)，自动穿透 K8s Gateway API 核心链路:
#       HTTPRoute ──► DestinationRule ──► Service ──► Deployment ──► Probes
#       并生成精准的、可直接用于 E2E 测试的 curl 验证命令（自动适配 TLS SNI --resolve 模式）。
#
# 用法: ./k8s-gateway-fqdn-gemini.sh <INPUT_FQDN> [TENANT_NAMESPACE]
#
# 依赖: kubectl, jq
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
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
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}# $*${RESET}"; }
divider() { echo -e "${DIM}$(printf '═%.0s' {1..80})${RESET}"; }
subdivider() { echo -e "${DIM}$(printf '─%.0s' {1..80})${RESET}"; }

# --------------------------------------------------------------------------- #
# 默认环境配置
# --------------------------------------------------------------------------- #
INPUT_FQDN="${1:-}"
TENANT_NS="${2:-}"
GATEWAY_NS="${GATEWAY_NS:-infrastructure}"
GATEWAY_NAME="${GATEWAY_NAME:-central-gateway}"

# --------------------------------------------------------------------------- #
# 参数 & 依赖检查
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") <INPUT_FQDN> [TENANT_NAMESPACE]

${BOLD}参数说明:${RESET}
  <INPUT_FQDN>       目标 Ingress 域名 (例如: api.team1-int.uk.aibang.local)
  [TENANT_NAMESPACE] 租户命名空间 (可选，默认通过 FQDN 或全局路由表智能自动检索)

${BOLD}特性亮点:${RESET}
  1. ${BOLD}跨命名空间智能拓扑${RESET}: 无需指定 NS，脚本能全集群扫描任何绑定了该 FQDN 的 HTTPRoute。
  2. ${BOLD}L4 到 L7 完整穿透${RESET}: 一路解析 HTTPRoute 规则、DestinationRule、Service 及绑定的 Deployment 探针。
  3. ${BOLD}E2E 智能测试地址${RESET}: 根据 HTTPRoute Match 路径与 Deployment Readiness/Liveness 探针智能拼装测试路径。
  4. ${BOLD}专业级 SNI 验证${RESET}: 自动提取 Gateway LB IP，并生成专业的 \`--resolve\` HTTPS 验证 curl 命令。

${BOLD}使用示例:${RESET}
  $(basename "$0") api.team1-int.uk.aibang.local
  $(basename "$0") app.team2.example.com team2

EOF
  exit 1
}

[[ -z "$INPUT_FQDN" ]] && usage

if ! command -v jq &>/dev/null; then
  error "本脚本高度依赖 'jq' 进行 JSON 数据处理，请先安装 jq!"
  exit 1
fi

if ! command -v kubectl &>/dev/null; then
  error "未检测到 'kubectl' 命令行工具，请确认集群连接状况!"
  exit 1
fi

# --------------------------------------------------------------------------- #
# 智能 FQDN 路由检索与 Namespace 定位
# --------------------------------------------------------------------------- #
echo ""
divider
echo -e "${BOLD}${MAGENTA}  🛰️  K8s Gateway 域名链路深度勘测工具 (Gemini 增强版)${RESET}"
echo -e "  目标域名: ${BOLD}${GREEN}${INPUT_FQDN}${RESET}"
divider

# 提取 Ingress Gateway LB IP
info "获取 Ingress Gateway 的外部 IP (命名空间: ${GATEWAY_NS})..."
GATEWAY_IP=$(kubectl get svc -n "$GATEWAY_NS" -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -z "$GATEWAY_IP" ]]; then
  # 尝试通过 Gateway 资源状态获取
  GATEWAY_IP=$(kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
fi

if [[ -n "$GATEWAY_IP" ]]; then
  success "定位到网关 LB IP: ${BOLD}${YELLOW}${GATEWAY_IP}${RESET}"
else
  warn "未能在命名空间 ${GATEWAY_NS} 下找到 LoadBalancer IP，测试命令将仅使用域名形式。"
fi

# 智能命名空间定位与 HTTPRoute 检索
info "正在搜索绑定了域名 '${INPUT_FQDN}' 的 HTTPRoute..."

# 1. 如果指定了命名空间，直接在命名空间下搜索
# 2. 如果未指定，先扫描全集群
HTTPROUTE_JSON=""
if [[ -n "$TENANT_NS" ]]; then
  HTTPROUTE_JSON=$(kubectl get httproute -n "$TENANT_NS" -o json 2>/dev/null || echo "")
else
  HTTPROUTE_JSON=$(kubectl get httproute -A -o json 2>/dev/null || echo "")
fi

if [[ -z "$HTTPROUTE_JSON" || "$HTTPROUTE_JSON" == '{"apiVersion":'* || "$HTTPROUTE_JSON" == '{"items":[]}' ]]; then
  error "未在命名空间中检索到任何 HTTPRoute 资源!"
  exit 1
fi

# 在 JSON 中智能匹配 FQDN (支持精确匹配及通配符匹配，例如 *.example.com)
# 使用 jq 匹配，提取 matched route 的 name, namespace, hostnames
MATCHED_ROUTE=$(echo "$HTTPROUTE_JSON" | jq -r --arg fqdn "$INPUT_FQDN" '
  .items[] | 
  select(
    .spec.hostnames[]? | 
    (
      $fqdn == . or 
      (. | startswith("*.") and ($fqdn | endswith(.[2:])))
    )
  ) | 
  "\(.metadata.name)|\(.metadata.namespace)"
' | head -n 1)

if [[ -z "$MATCHED_ROUTE" ]]; then
  error "在集群内未发现任何绑定了域名 '${INPUT_FQDN}' 的 HTTPRoute!"
  warn "当前集群内存在的所有 HTTPRoute 域名列表如下:"
  kubectl get httproute -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNAMES:.spec.hostnames"
  exit 1
fi

HTTPROUTE_NAME=$(echo "$MATCHED_ROUTE" | cut -d'|' -f1)
TENANT_NS=$(echo "$MATCHED_ROUTE" | cut -d'|' -f2)

success "智能定位成功！"
echo -e "  └─ ${BOLD}HTTPRoute${RESET}:    ${GREEN}${HTTPROUTE_NAME}${RESET}"
echo -e "  └─ ${BOLD}Namespace${RESET}:    ${GREEN}${TENANT_NS}${RESET}"

# --------------------------------------------------------------------------- #
# 解析 HTTPRoute 规则与其后端服务 (L7 -> L4)
# --------------------------------------------------------------------------- #
header "1. 路由解析 (HTTPRoute Rules & BackendRefs)"

HTTPROUTE_OBJ=$(kubectl get httproute "$HTTPROUTE_NAME" -n "$TENANT_NS" -o json)

# 提取绑定的 ParentRefs (Gateway / ListenerSet)
PARENTS=$(echo "$HTTPROUTE_OBJ" | jq -r '
  .spec.parentRefs[]? | 
  "\(.kind // "Gateway"): \(.namespace // "same-ns")/\(.name)\(if .sectionName then " (Port: " + .sectionName + ")" else "" end)"
' 2>/dev/null || echo "无")

echo -e "  ${BOLD}绑定网关入口 (ParentRefs):${RESET}"
echo "$PARENTS" | while read -r line; do
  echo -e "    - ${CYAN}${line}${RESET}"
done

# 提取所有规则与后端服务
RULES_JSON=$(echo "$HTTPROUTE_OBJ" | jq -c '.spec.rules[]')
RULE_IDX=0

declare -a ALL_E2E_URLS=()

while IFS= read -r rule; do
  [[ -z "$rule" ]] && continue
  RULE_IDX=$(( RULE_IDX + 1 ))
  
  subdivider
  echo -e "  ${BOLD}⚡ 路由规则 #${RULE_IDX}${RESET}"
  
  # 提取匹配条件 (Paths / Headers)
  MATCHES=$(echo "$rule" | jq -c '.matches[]?')
  echo -e "  ${BOLD}匹配路径 (Matches):${RESET}"
  declare -a RULE_PATHS=()
  if [[ -z "$MATCHES" ]]; then
    echo -e "    - ${DIM}任何路径 (默认 /*)${RESET}"
    RULE_PATHS+=("/")
  else
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      path_type=$(echo "$m" | jq -r '.path.type // "PathPrefix"')
      path_val=$(echo "$m" | jq -r '.path.value // "/"')
      echo -e "    - 类型: ${BLUE}${path_type}${RESET} | 路径: ${YELLOW}${path_val}${RESET}"
      RULE_PATHS+=("$path_val")
    done <<< "$MATCHES"
  fi

  # 提取超时设定
  RULE_REQ_TIMEOUT=$(echo "$rule" | jq -r '.timeouts.request // "未设置(无限)"')
  RULE_BK_TIMEOUT=$(echo "$rule" | jq -r '.timeouts.backendRequest // "未设置(无限)"')
  echo -e "  ${BOLD}规则级超时 (Timeouts):${RESET}"
  echo -e "    - 客户端总请求超时: ${CYAN}${RULE_REQ_TIMEOUT}${RESET}"
  echo -e "    - 单次后端建连超时: ${CYAN}${RULE_BK_TIMEOUT}${RESET}"

  # 提取该规则下的所有后端服务引用 (BackendRefs)
  BACKENDS=$(echo "$rule" | jq -c '.backendRefs[]?')
  
  if [[ -z "$BACKENDS" ]]; then
    warn "规则 #${RULE_IDX} 下没有配置任何 backendRefs!"
    continue
  fi

  echo -e "  ${BOLD}后端引用 (BackendRefs):${RESET}"
  while IFS= read -r backend; do
    [[ -z "$backend" ]] && continue
    bk_name=$(echo "$backend" | jq -r '.name')
    bk_port=$(echo "$backend" | jq -r '.port')
    bk_weight=$(echo "$backend" | jq -r '.weight // 100')
    
    echo -e "    - 服务名: ${GREEN}${bk_name}${RESET} | 端口: ${YELLOW}${bk_port}${RESET} | 权重: ${bk_weight}%"
    
    # ----------------------------------------------------------------------- #
    # 深入后端服务 (Service ──► DestinationRule ──► Deployment ──► Probes)
    # ----------------------------------------------------------------------- #
    echo -e "      ${DIM}└─ 链路探测:${RESET}"
    
    # 1. 检查 Service
    SVC_OBJ=$(kubectl get svc "$bk_name" -n "$TENANT_NS" -o json 2>/dev/null || echo "")
    if [[ -z "$SVC_OBJ" ]]; then
      error "        ⚠️ 未能在命名空间 ${TENANT_NS} 中找到对应的 Service: ${bk_name}"
      continue
    fi
    
    svc_selector=$(echo "$SVC_OBJ" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null || echo "")
    svc_type=$(echo "$SVC_OBJ" | jq -r '.spec.type // "ClusterIP"')
    svc_api_anno=$(echo "$SVC_OBJ" | jq -r '.metadata.annotations."apigateway.net/v1alpha1" // "NONE"')
    
    echo -e "        ${BOLD}Service 类型${RESET}:    ${svc_type} | 标签选择器: ${BLUE}${svc_selector:-无}${RESET}"
    echo -e "        ${BOLD}API 网关架构${RESET}:    ${YELLOW}${svc_api_anno}${RESET}"

    # 2. 检查 DestinationRule (连接池与 TCP/HTTP 超时)
    # 智能搜索针对该服务 host 设置的 DestinationRule
    DR_OBJ=$(kubectl get destinationrule -n "$TENANT_NS" -o json 2>/dev/null || echo "")
    DR_NAME="<无>"
    DR_CONN_TIMEOUT="<默认>"
    DR_IDLE_TIMEOUT="<默认>"
    
    if [[ -n "$DR_OBJ" && "$DR_OBJ" != '{"items":[]}' ]]; then
      MATCHED_DR=$(echo "$DR_OBJ" | jq -r --arg svc "$bk_name" --arg ns "$TENANT_NS" '
        .items[] | 
        select(
          .spec.host == $svc or 
          .spec.host == "\($svc).\($ns)" or 
          .spec.host == "\($svc).\($ns).svc.cluster.local"
        ) | 
        "\(.metadata.name)|\(.spec.trafficPolicy.connectionPool.tcp.connectTimeout // "default")|\(.spec.trafficPolicy.connectionPool.http.idleTimeout // "default")"
      ' | head -n 1)
      
      if [[ -n "$MATCHED_DR" ]]; then
        DR_NAME=$(echo "$MATCHED_DR" | cut -d'|' -f1)
        DR_CONN_TIMEOUT=$(echo "$MATCHED_DR" | cut -d'|' -f2)
        DR_IDLE_TIMEOUT=$(echo "$MATCHED_DR" | cut -d'|' -f3)
      fi
    fi
    echo -e "        ${BOLD}DestinationRule${RESET}: ${MAGENTA}${DR_NAME}${RESET} (TCP建连超时: ${DR_CONN_TIMEOUT} | 空闲连接超时: ${DR_IDLE_TIMEOUT})"

    # 3. 检查绑定的 Deployment 与健康检查端点 (Health / Liveness Probes)
    DEPLOY_NAME=""
    READINESS_PATH=""
    LIVENESS_PATH=""
    
    if [[ -n "$svc_selector" ]]; then
      # 智能拓扑：通过 labels 寻找 Deployment
      # 先获取运行中 Pod 的 OwnerReference (最精准)
      PODS_JSON=$(kubectl get pods -n "$TENANT_NS" -l "$svc_selector" -o json 2>/dev/null || echo "")
      if [[ -n "$PODS_JSON" && "$PODS_JSON" != '{"items":[]}' ]]; then
        OWNER_NAME=$(echo "$PODS_JSON" | jq -r '.items[0].metadata.ownerReferences[0].name' 2>/dev/null || echo "")
        OWNER_KIND=$(echo "$PODS_JSON" | jq -r '.items[0].metadata.ownerReferences[0].kind' 2>/dev/null || echo "")
        
        if [[ "$OWNER_KIND" == "ReplicaSet" ]]; then
          # 溯源：ReplicaSet ──► Deployment
          RS_OBJ=$(kubectl get replicaset "$OWNER_NAME" -n "$TENANT_NS" -o json 2>/dev/null || echo "")
          if [[ -n "$RS_OBJ" ]]; then
            DEPLOY_NAME=$(echo "$RS_OBJ" | jq -r '.metadata.ownerReferences[0].name' 2>/dev/null || echo "")
          fi
        elif [[ "$OWNER_KIND" == "Deployment" ]]; then
          DEPLOY_NAME="$OWNER_NAME"
        fi
      fi
      
      # 容错：若 Pod 还未运行，通过 selector 匹配 Deployment spec 标签
      if [[ -z "$DEPLOY_NAME" ]]; then
        DEPLOY_NAME=$(kubectl get deploy -n "$TENANT_NS" -o json 2>/dev/null | jq -r --arg selector "$svc_selector" '
          .items[] | 
          select(
            .spec.selector.matchLabels | 
            to_entries | 
            map("\(.key)=\(.value)") | 
            join(",") == $selector
          ) | 
          .metadata.name
        ' | head -n 1)
      fi
    fi
    
    if [[ -n "$DEPLOY_NAME" ]]; then
      DEPLOY_OBJ=$(kubectl get deploy "$DEPLOY_NAME" -n "$TENANT_NS" -o json)
      READINESS_PATH=$(echo "$DEPLOY_OBJ" | jq -r '.spec.template.spec.containers[0].readinessProbe.httpGet.path // ""')
      LIVENESS_PATH=$(echo "$DEPLOY_OBJ" | jq -r '.spec.template.spec.containers[0].livenessProbe.httpGet.path // ""')
      
      echo -e "        ${BOLD}关联 Deployment${RESET}:  ${GREEN}${DEPLOY_NAME}${RESET}"
      echo -e "        ${BOLD}Readiness Probe${RESET}: ${YELLOW}${READINESS_PATH:-无}${RESET}"
      echo -e "        ${BOLD}Liveness Probe${RESET}:  ${YELLOW}${LIVENESS_PATH:-无}${RESET}"
    else
      warn "        ⚠️ 无法根据 Service selector 定位到活动 Deployment 工作负载。"
    fi

    # 4. 根据匹配规则路径与容器探针智能合成测试 URL
    for rpath in "${RULE_PATHS[@]}"; do
      # 组合路径策略：
      # - 如果路由匹配的是具体的 API 路径 (如 /api/v1)，则保留此路径作为 E2E 入口。
      # - 如果路由仅匹配 / 根路径，而应用声明了 ReadinessProbe (如 /healthz)，则将它们智能合并。
      # - 处理双斜杠风险
      combined_path="$rpath"
      if [[ "$rpath" == "/" && -n "$READINESS_PATH" ]]; then
        combined_path="$READINESS_PATH"
      fi
      
      # 去除重复的双斜杠
      combined_path=$(echo "$combined_path" | sed 's/\/\//\//g')
      
      ALL_E2E_URLS+=("https://${INPUT_FQDN}${combined_path}")
    done

  done <<< "$BACKENDS"

done <<< "$RULES_JSON"

# --------------------------------------------------------------------------- #
# 生成 E2E 测试命令汇总
# --------------------------------------------------------------------------- #
header "2. E2E 测试命令生成汇总 (Ready-to-use curl Commands)"

if [[ ${#ALL_E2E_URLS[@]} -eq 0 ]]; then
  warn "未生成任何 E2E 测试 URL，请检查路由规则配置！"
  exit 0
fi

# 去重
UNIQUE_URLS=($(echo "${ALL_E2E_URLS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo -e "  以下为基于域名链路逆向推导出的 ${BOLD}E2E 智能测试 URL${RESET} 列表："
echo ""

for url in "${UNIQUE_URLS[@]}"; do
  path_part=$(echo "$url" | sed -E 's|https://[^/]+||')
  [[ -z "$path_part" ]] && path_part="/"
  
  echo -e "  ${BOLD}🔗 测试终结点:${RESET} ${GREEN}${url}${RESET}"
  
  # A. 域名解析测试（前提是本地 Host 已经绑定或 DNS 已经生效）
  echo -e "    ${DIM}👉 方法 A (本地 DNS/Hosts 已就绪时使用):${RESET}"
  echo -e "    ${CYAN}curl -k -v --max-time 10 \"${url}\"${RESET}"
  
  # B. 专业级网关直通测试 (自动适配 SNI / --resolve)
  if [[ -n "$GATEWAY_IP" ]]; then
    echo -e "    ${DIM}👉 方法 B (专业网关 SNI 直通测试 - 自动绑定 IP & 绕过 DNS 缓存):${RESET}"
    echo -e "    ${BOLD}${YELLOW}curl -k -v --max-time 10 --resolve \"${INPUT_FQDN}:443:${GATEWAY_IP}\" \"https://${INPUT_FQDN}${path_part}\"${RESET}"
  fi
  echo ""
done

divider
echo -e "  ${BOLD}${GREEN}✔ 勘测完成！链路拓扑关系已成功构建并存放于 E2E 目录中。${RESET}"
divider
echo ""

```

## `k8s-gateway-fqdn.sh`

```bash
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
```

## `k8s-gateway-verify.sh`

```bash
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

```

