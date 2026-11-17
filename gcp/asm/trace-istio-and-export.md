```bash
#!/usr/bin/env bash
# =============================================================================
# trace-istio.sh — Istio full-chain tracer + YAML template exporter
# Purpose : Reverse-trace URL -> Gateway -> VirtualService -> DestinationRule
#           -> Service -> Deployment and export clean YAML templates for
#           direct use in new API onboarding.
# Requires: kubectl, jq, bash >= 4.0
# Usage   : ./trace-istio.sh --url https://api.example.com/v1/health
#           ./trace-istio.sh --url https://api.example.com/v1/health --export-yaml
#           ./trace-istio.sh --url https://api.example.com/v1/health \
#                            --export-yaml --out-dir ./my-templates
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Colors & formatters
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
MAGENTA='\033[0;35m'; WHITE='\033[1;37m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${WHITE}  $*${RESET}"; \
            echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; }
row()     { printf "  ${CYAN}%-28s${RESET} %s\n" "$1" "$2"; }

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
TARGET_URL=""
HINT_NS=""             # optional: narrow Gateway search to one namespace
OUTPUT_JSON=false      # --json  -> write raw JSON to <out-dir>/trace-output.json
EXPORT_YAML=false      # --export-yaml -> write clean YAML templates
OUT_DIR=""             # --out-dir -> custom output directory

usage() {
  cat <<EOF
Usage: $(basename "$0") --url <URL> [OPTIONS]

  --url           Target URL, e.g. https://api.example.com/v1/health
  --namespace     Optional: restrict Gateway search to this namespace
  --json          Also write raw trace data to <out-dir>/trace-output.json
  --export-yaml   Export a clean YAML template for every resource in the chain
                  (suitable for direct use in new API onboarding)
  --out-dir DIR   Output directory for YAML/JSON files
                  (default: ./istio-trace-<host>-<timestamp>)
  -h, --help      Show this help

Examples:
  $(basename "$0") --url https://api.example.com/v1/health
  $(basename "$0") --url https://api.example.com/v1/health --export-yaml
  $(basename "$0") --url https://api.example.com/v1/health \\
      --export-yaml --out-dir ./templates --json
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)         TARGET_URL="$2"; shift 2 ;;
    --namespace)   HINT_NS="$2";    shift 2 ;;
    --json)        OUTPUT_JSON=true; shift ;;
    --export-yaml) EXPORT_YAML=true; shift ;;
    --out-dir)     OUT_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) error "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "$TARGET_URL" ]] && { error "--url is required"; usage; }

# --------------------------------------------------------------------------- #
# Parse URL into host + path
# --------------------------------------------------------------------------- #
_no_schema="${TARGET_URL#*://}"
INPUT_HOST="${_no_schema%%/*}"
INPUT_PATH="/${_no_schema#*/}"
[[ "$INPUT_PATH" == "/$INPUT_HOST" || "$INPUT_PATH" == "/" ]] && INPUT_PATH="/"

# --------------------------------------------------------------------------- #
# Dependency check
# --------------------------------------------------------------------------- #
for cmd in kubectl jq; do
  command -v "$cmd" &>/dev/null || { error "Missing dependency: $cmd"; exit 1; }
done

# --------------------------------------------------------------------------- #
# Global JSON result object (for --json output)
# --------------------------------------------------------------------------- #
RESULT_JSON='{}'

append_json() {
  local key="$1" val="$2"
  RESULT_JSON=$(echo "$RESULT_JSON" | jq --argjson v "$val" ". + {\"$key\": \$v}")
}

# --------------------------------------------------------------------------- #
# Output directory setup
# --------------------------------------------------------------------------- #
_HOST_SLUG=$(echo "$INPUT_HOST" | tr '.' '-')
_TIMESTAMP=$(date +%Y%m%d%H%M%S)
[[ -z "$OUT_DIR" ]] && OUT_DIR="./istio-trace-${_HOST_SLUG}-${_TIMESTAMP}"

if [[ "$EXPORT_YAML" == true || "$OUTPUT_JSON" == true ]]; then
  mkdir -p "$OUT_DIR"
  info "Output directory: $(realpath "$OUT_DIR")"
fi

# --------------------------------------------------------------------------- #
# clean_yaml <kind> <name> <namespace> [<out_file>]
#   Fetch the resource and strip runtime-only fields so the result is
#   directly usable as a kubectl apply template.
#   Removed: managedFields, resourceVersion, uid, generation,
#            creationTimestamp, selfLink, status block,
#            last-applied-configuration annotation
# --------------------------------------------------------------------------- #
clean_yaml() {
  local kind="$1" name="$2" ns="$3" out_file="${4:-}"

  local raw
  raw=$(kubectl get "$kind" "$name" -n "$ns" -o yaml 2>/dev/null) || {
    warn "Cannot fetch ${kind}/${name} -n ${ns}"; return 1
  }

  local cleaned
  cleaned=$(echo "$raw" | python3 -c "
import sys, yaml

data = yaml.safe_load(sys.stdin)
if not data:
    sys.exit(0)

# Strip runtime metadata fields
meta = data.get('metadata', {})
for field in ['managedFields', 'resourceVersion', 'uid', 'generation',
              'creationTimestamp', 'selfLink']:
    meta.pop(field, None)

# Strip noisy annotations
ann = meta.get('annotations', {})
ann.pop('kubectl.kubernetes.io/last-applied-configuration', None)
ann.pop('deployment.kubernetes.io/revision', None)
if not ann:
    meta.pop('annotations', None)

# Drop status block entirely
data.pop('status', None)

# For Deployments: also clean pod template metadata
if data.get('kind') == 'Deployment':
    tmpl_meta = data.get('spec', {}).get('template', {}).get('metadata', {})
    tmpl_meta.pop('creationTimestamp', None)

print(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
" 2>/dev/null) || {
    warn "python3 yaml module unavailable, falling back to line-filter..."
    cleaned=$(echo "$raw" | python3 -c "
import sys
lines = sys.stdin.readlines()
result = []
i = 0
while i < len(lines):
    line = lines[i]
    # Drop entire status block
    if line.startswith('status:'):
        i += 1
        while i < len(lines) and (lines[i].startswith(' ') or lines[i] == '\n'):
            i += 1
        continue
    # Drop managedFields block
    if '  managedFields:' in line:
        i += 1
        while i < len(lines) and (lines[i].startswith('  - ') or lines[i].startswith('    ')):
            i += 1
        continue
    # Drop single-line runtime fields
    skip = False
    for k in ['  resourceVersion:', '  uid:', '  generation:', '  creationTimestamp:', '  selfLink:']:
        if line.strip().startswith(k.strip()):
            skip = True; break
    if not skip:
        result.append(line)
    i += 1
print(''.join(result))
")
  }

  if [[ -n "$out_file" ]]; then
    {
      echo "# ============================================================"
      echo "# Resource : ${kind}/${name}"
      echo "# Namespace: ${ns}"
      echo "# Exported : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      echo "# Source   : $TARGET_URL"
      echo "# NOTE     : Runtime fields removed (status / managedFields /"
      echo "#            uid / resourceVersion / creationTimestamp)."
      echo "#            Edit and apply directly: kubectl apply -f <file>"
      echo "# ============================================================"
      echo ""
      echo "$cleaned"
    } > "$out_file"
    success "  -> $(basename "$out_file")"
  else
    echo "$cleaned"
  fi
}

# --------------------------------------------------------------------------- #
# export_resource <kind> <name> <namespace> <file_prefix>
#   Wrapper: only writes when --export-yaml is active.
# --------------------------------------------------------------------------- #
export_resource() {
  local kind="$1" name="$2" ns="$3" prefix="$4"
  if [[ "$EXPORT_YAML" == true ]]; then
    local fname="${OUT_DIR}/${prefix}-$(echo "$ns" | tr '/' '-')-${name}.yaml"
    clean_yaml "$kind" "$name" "$ns" "$fname"
  fi
}

# =============================================================================
# STEP 0 — Print trace target
# =============================================================================
section "🚀 Istio Full-Chain Tracer"
row "Target URL"       "$TARGET_URL"
row "Host"             "$INPUT_HOST"
row "Path"             "$INPUT_PATH"
[[ -n "$HINT_NS" ]] && row "Hint namespace" "$HINT_NS"
echo ""

# =============================================================================
# STEP 1 — Locate Gateway
# =============================================================================
section "📍 STEP 1 — Locate Gateway"

info "Fetching all Gateway resources..."
GW_NS_FLAG="${HINT_NS:+-n $HINT_NS}"
ALL_GW_JSON=$(kubectl get gateway ${GW_NS_FLAG:--A} -o json 2>/dev/null || echo '{"items":[]}')

GW_COUNT=$(echo "$ALL_GW_JSON" | jq '.items | length')
info "Found ${GW_COUNT} Gateway(s) in cluster"

# Match logic: exact host first, wildcard (*) as fallback
MATCHED_GW=$(echo "$ALL_GW_JSON" | jq --arg host "$INPUT_HOST" '
  [ .items[] |
    . as $gw |
    (.metadata.namespace) as $ns |
    (.metadata.name) as $name |
    (.spec.selector // {}) as $sel |
    [ .spec.servers[]?.hosts[]? |
      select(. == $host or . == "*" or
             (startswith("*.") and ($host | endswith(ltrimstr("*", .))))
      )
    ] |
    if length > 0 then {
      name: $name,
      namespace: $ns,
      selector: $sel,
      matched_host: .[0],
      is_wildcard: (.[0] == "*")
    } else empty end
  ] | sort_by(.is_wildcard)
')

GW_MATCH_COUNT=$(echo "$MATCHED_GW" | jq 'length')

if [[ "$GW_MATCH_COUNT" -eq 0 ]]; then
  error "No Gateway matched host='$INPUT_HOST' (including wildcard *)"
  exit 1
fi

echo "$MATCHED_GW" | jq -r '.[] |
  "  \(if .is_wildcard then "⚠ [wildcard]" else "✓ [exact]" end) \(.namespace)/\(.name)  matched_host=\(.matched_host)  selector=\(.selector | to_entries | map("\(.key)=\(.value)") | join(","))"'

# Use first result (exact match sorted first)
SELECTED_GW=$(echo "$MATCHED_GW" | jq '.[0]')
GW_NAME=$(echo "$SELECTED_GW" | jq -r '.name')
GW_NS=$(echo "$SELECTED_GW" | jq -r '.namespace')
GW_SELECTOR=$(echo "$SELECTED_GW" | jq -r '.selector | to_entries | map("\(.key)=\(.value)") | join(",")')

echo ""
success "Using Gateway: ${GW_NS}/${GW_NAME}  (selector: ${GW_SELECTOR})"

# Show IngressGateway pods
info "Looking up IngressGateway pods (selector: ${GW_SELECTOR})..."
IGW_PODS=$(kubectl get pods -A -l "$GW_SELECTOR" \
  --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP" 2>/dev/null || true)

if [[ -n "$IGW_PODS" ]]; then
  echo -e "\n  ${BOLD}IngressGateway Pods:${RESET}"
  echo "$IGW_PODS" | while read -r line; do echo "    $line"; done
else
  warn "No IngressGateway pods found for selector '${GW_SELECTOR}'"
fi

append_json "gateway" "$SELECTED_GW"

# Export Gateway YAML
export_resource "gateway" "$GW_NAME" "$GW_NS" "01-gateway"

# =============================================================================
# STEP 2 — Resolve VirtualService
# =============================================================================
section "🔀 STEP 2 — Resolve VirtualService"

info "Fetching all VirtualService resources..."
ALL_VS_JSON=$(kubectl get virtualservice -A -o json 2>/dev/null || echo '{"items":[]}')

VS_COUNT=$(echo "$ALL_VS_JSON" | jq '.items | length')
info "Found ${VS_COUNT} VirtualService(s) in cluster"

# Match: gateways field contains GW_NAME or GW_NS/GW_NAME, hosts match
MATCHED_VS=$(echo "$ALL_VS_JSON" | jq --arg gwname "$GW_NAME" --arg gwns "$GW_NS" --arg host "$INPUT_HOST" --arg path "$INPUT_PATH" '
  [ .items[] |
    . as $vs |
    (.metadata.namespace) as $vsns |
    select(
      .spec.gateways // [] |
      any(
        . == $gwname or
        . == "\($gwns)/\($gwname)" or
        . == "mesh"
      )
    ) |
    select(
      .spec.hosts // [] |
      any(. == $host or . == "*")
    ) |
    {
      name: .metadata.name,
      namespace: $vsns,
      gateways: (.spec.gateways // []),
      hosts: (.spec.hosts // []),
      http_routes: [ (.spec.http // [])[] |
        {
          match_uris: [ (.match // [])[]?.uri | to_entries[] | "\(.key)=\(.value)" ],
          route_destinations: [ (.route // [])[] | {
            host: .destination.host,
            subset: .destination.subset,
            port: .destination.port.number,
            weight: .weight
          }],
          headers: (.headers // null),
          retries: (.retries // null),
          timeout: (.timeout // null)
        }
      ]
    }
  ]
')

VS_MATCH_COUNT=$(echo "$MATCHED_VS" | jq 'length')
if [[ "$VS_MATCH_COUNT" -eq 0 ]]; then
  error "No VirtualService found linked to Gateway '${GW_NS}/${GW_NAME}' with a matching host"
  exit 1
fi

info "Found ${VS_MATCH_COUNT} candidate VirtualService(s)"

# Filter routes by input path prefix
PATH_MATCHED_VS=$(echo "$MATCHED_VS" | jq --arg path "$INPUT_PATH" '
  [ .[] |
    . as $vs |
    (.http_routes | map(
      select(
        .match_uris == [] or
        (.match_uris | any(
          (startswith("prefix=") and ($path | startswith(ltrimstr("prefix=", .)))) or
          (startswith("exact=")  and (ltrimstr("exact=", .) == $path)) or
          (startswith("regex="))
        ))
      )
    )) as $matched_routes |
    if ($matched_routes | length) > 0 then
      $vs + {matched_routes: $matched_routes}
    else empty end
  ]
')

PATH_MATCH_COUNT=$(echo "$PATH_MATCHED_VS" | jq 'length')
if [[ "$PATH_MATCH_COUNT" -eq 0 ]]; then
  warn "No route matched path '${INPUT_PATH}', falling back to all linked VirtualServices"
  PATH_MATCHED_VS=$(echo "$MATCHED_VS" | jq '[.[] | . + {matched_routes: .http_routes}]')
fi

echo "$PATH_MATCHED_VS" | jq -r '.[] | "  ✓ \(.namespace)/\(.name)  hosts=\(.hosts | join(","))"'

append_json "virtualservices" "$PATH_MATCHED_VS"

# =============================================================================
# STEP 3 — Extract Destinations & DestinationRules
# =============================================================================
section "🎯 STEP 3 — Extract Destinations & DestinationRules"

info "Fetching all DestinationRule resources..."
ALL_DR_JSON=$(kubectl get destinationrule -A -o json 2>/dev/null || echo '{"items":[]}')

# Collect all destination hosts from matched VS routes
ALL_DEST_JSON=$(echo "$PATH_MATCHED_VS" | jq '
  [ .[] |
    .namespace as $vsns |
    .matched_routes[]?.route_destinations[]? |
    {
      raw_host: .host,
      subset: .subset,
      port: .port,
      weight: .weight,
      vs_namespace: $vsns
    }
  ] | unique_by(.raw_host + (.subset // ""))
')

DEST_COUNT=$(echo "$ALL_DEST_JSON" | jq 'length')
info "Found ${DEST_COUNT} destination(s)"

# Enrich each destination: expand FQDN + link DestinationRule
ENRICHED_DEST=$(echo "$ALL_DEST_JSON" | jq --argjson drs "$ALL_DR_JSON" '
  [ .[] |
    . as $dest |
    ($dest.raw_host) as $rh |
    ($dest.vs_namespace) as $vsns |
    (if ($rh | contains(".svc.cluster.local")) then $rh
     elif ($rh | contains(".")) then $rh
     else "\($rh).\($vsns).svc.cluster.local" end) as $fqdn |
    ($rh | split(".")[0]) as $svcname |
    ([ $drs.items[] |
       select(
         .spec.host == $rh or
         .spec.host == $fqdn or
         (.spec.host | split(".")[0]) == $svcname
       ) |
       {
         name: .metadata.name,
         namespace: .metadata.namespace,
         host: .spec.host,
         subsets: (.spec.subsets // []),
         trafficPolicy: (.spec.trafficPolicy // null)
       }
    ]) as $matched_drs |
    $dest + {
      fqdn: $fqdn,
      svc_name: $svcname,
      destination_rules: $matched_drs
    }
  ]
')

echo "$ENRICHED_DEST" | jq -r '.[] |
  "  ✓ host=\(.raw_host)  subset=\(.subset // "-")  port=\(.port // "-")  weight=\(.weight // 100)",
  "    FQDN: \(.fqdn)",
  (if (.destination_rules | length) > 0 then
    "    DestinationRule: \(.destination_rules | map("\(.namespace)/\(.name)") | join(", "))"
  else
    "    DestinationRule: (none)"
  end)'

append_json "destinations" "$ENRICHED_DEST"

# Export VirtualService YAMLs
if [[ "$EXPORT_YAML" == true ]]; then
  info "Exporting VirtualService YAML(s)..."
  while IFS= read -r vs_item; do
    _vs_name=$(echo "$vs_item" | jq -r '.name')
    _vs_ns=$(echo "$vs_item" | jq -r '.namespace')
    export_resource "virtualservice" "$_vs_name" "$_vs_ns" "02-virtualservice"
  done < <(echo "$PATH_MATCHED_VS" | jq -c '.[]')
fi

# Export DestinationRule YAMLs
if [[ "$EXPORT_YAML" == true ]]; then
  info "Exporting DestinationRule YAML(s)..."
  echo "$ENRICHED_DEST" | jq -c '[.[].destination_rules[] | {name,namespace}] | unique[]' | \
  while IFS= read -r dr_item; do
    _dr_name=$(echo "$dr_item" | jq -r '.name')
    _dr_ns=$(echo "$dr_item" | jq -r '.namespace')
    export_resource "destinationrule" "$_dr_name" "$_dr_ns" "03-destinationrule"
  done
fi

# =============================================================================
# STEP 4 — Map to Kubernetes Service, Endpoints & Pods
# =============================================================================
section "⚙️  STEP 4 — Kubernetes Service / Endpoints / Pods"

SVC_DETAIL_LIST='[]'

while IFS= read -r dest_item; do
  SVC_NAME=$(echo "$dest_item" | jq -r '.svc_name')
  SVC_NS=$(echo "$dest_item" | jq -r '.vs_namespace')
  SUBSET=$(echo "$dest_item" | jq -r '.subset // ""')

  info "Looking up Service: ${SVC_NS}/${SVC_NAME}"

  SVC_JSON=$(kubectl get service "$SVC_NAME" -n "$SVC_NS" -o json 2>/dev/null || echo 'null')

  if [[ "$SVC_JSON" == "null" ]]; then
    warn "Service '${SVC_NS}/${SVC_NAME}' not found, searching all namespaces..."
    SVC_JSON=$(kubectl get service "$SVC_NAME" -A -o json 2>/dev/null | jq '.items[0] // null')
    [[ "$SVC_JSON" == "null" ]] && { warn "Service '$SVC_NAME' not found anywhere, skipping"; continue; }
    SVC_NS=$(echo "$SVC_JSON" | jq -r '.metadata.namespace')
    info "Found Service in namespace '$SVC_NS'"
  fi

  SVC_LABELS=$(echo "$SVC_JSON" | jq -r '.metadata.labels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
  SVC_SELECTOR=$(echo "$SVC_JSON" | jq -r '.spec.selector // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
  SVC_CLUSTERIP=$(echo "$SVC_JSON" | jq -r '.spec.clusterIP // "-"')
  SVC_TYPE=$(echo "$SVC_JSON" | jq -r '.spec.type // "-"')
  SVC_PORTS=$(echo "$SVC_JSON" | jq -r '.spec.ports // [] | map("\(.port)/\(.protocol // "TCP") -> \(.targetPort)") | join(", ")')

  echo -e "\n  ${BOLD}Service: ${SVC_NS}/${SVC_NAME}${RESET}"
  row "  Type"       "$SVC_TYPE"
  row "  ClusterIP"  "$SVC_CLUSTERIP"
  row "  Ports"      "$SVC_PORTS"
  row "  Selector"   "${SVC_SELECTOR:-'(no selector)'}"
  row "  Labels"     "${SVC_LABELS}"

  # Endpoints
  EP_JSON=$(kubectl get endpoints "$SVC_NAME" -n "$SVC_NS" -o json 2>/dev/null || echo 'null')
  EP_ADDRS=$(echo "$EP_JSON" | jq -r '
    [ .subsets[]?.addresses[]? | "\(.ip):\(.targetRef.name // "?")" ] | join(", ")
  ' 2>/dev/null || echo "-")
  row "  Endpoints"  "${EP_ADDRS:-'(no ready endpoints)'}"

  # Pods
  POD_INFO=""
  if [[ -n "$SVC_SELECTOR" ]]; then
    POD_JSON=$(kubectl get pods -n "$SVC_NS" -l "$SVC_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
    POD_COUNT=$(echo "$POD_JSON" | jq '.items | length')
    row "  Pod count"  "$POD_COUNT"

    if [[ "$POD_COUNT" -gt 0 ]]; then
      echo -e "\n  ${BOLD}  Pod list:${RESET}"
      POD_INFO=$(echo "$POD_JSON" | jq -r '
        .items[] |
        "    \(.metadata.name)  IP=\(.status.podIP // "-")  Node=\(.spec.nodeName // "-")  Phase=\(.status.phase // "-")  Ready=\(
          [.status.containerStatuses[]?.ready] | all | if . then "✓" else "✗" end
        )  Version=\(.metadata.labels["version"] // .metadata.labels["app.kubernetes.io/version"] // "-")"
      ')
      echo "$POD_INFO"
    fi

    # Validate subset label matching
    if [[ -n "$SUBSET" && "$SUBSET" != "null" ]]; then
      echo ""
      info "Validating pods for subset='${SUBSET}'..."
      DR_SUBSET_LABELS=$(echo "$dest_item" | jq -r --arg sub "$SUBSET" '
        .destination_rules[0].subsets // [] |
        map(select(.name == $sub)) |
        .[0].labels // {} |
        to_entries | map("\(.key)=\(.value)") | join(",")
      ')
      if [[ -n "$DR_SUBSET_LABELS" ]]; then
        SUBSET_PODS=$(kubectl get pods -n "$SVC_NS" -l "${SVC_SELECTOR},${DR_SUBSET_LABELS}" --no-headers \
          -o custom-columns="NAME:.metadata.name,IP:.status.podIP,PHASE:.status.phase" 2>/dev/null | wc -l | tr -d ' ')
        row "  Subset pods" "${SUBSET_PODS} pod(s) matching labels: ${DR_SUBSET_LABELS}"
      else
        warn "Subset '${SUBSET}' has no label definition in DestinationRule"
      fi
    fi
  else
    warn "Service has no selector (may be ExternalName or headless)"
  fi

  # Assemble SVC detail JSON
  SVC_DETAIL=$(jq -n \
    --arg name "$SVC_NAME" \
    --arg ns "$SVC_NS" \
    --arg clusterip "$SVC_CLUSTERIP" \
    --arg type "$SVC_TYPE" \
    --arg ports "$SVC_PORTS" \
    --arg selector "$SVC_SELECTOR" \
    --arg endpoints "$EP_ADDRS" \
    --arg podinfo "$POD_INFO" \
    '{name: $name, namespace: $ns, clusterIP: $clusterip, type: $type, ports: $ports, selector: $selector, endpoints: $endpoints, pods: $podinfo}')

  SVC_DETAIL_LIST=$(echo "$SVC_DETAIL_LIST" | jq --argjson s "$SVC_DETAIL" '. + [$s]')

  # Export Service YAML
  export_resource "service" "$SVC_NAME" "$SVC_NS" "04-service"

  # Locate and export Deployment (or StatefulSet)
  if [[ -n "$SVC_SELECTOR" ]]; then
    info "Looking up Deployment(s) for selector: ${SVC_SELECTOR}..."
    DEPLOY_JSON=$(kubectl get deployment -n "$SVC_NS" -o json 2>/dev/null || echo '{"items":[]}')
    MATCHED_DEPLOYS=$(echo "$DEPLOY_JSON" | jq -r --arg sel "$SVC_SELECTOR" '
      ( $sel | split(",") | map(split("=") | {key: .[0], value: .[1]}) ) as $pairs |
      [ .items[] |
        . as $d |
        (.spec.selector.matchLabels // {}) as $ml |
        select(
          $pairs | all(.key as $k | .value as $v | $ml[$k] == $v)
        ) |
        .metadata.name
      ] | .[]
    ' 2>/dev/null || true)

    if [[ -n "$MATCHED_DEPLOYS" ]]; then
      echo -e "\n  ${BOLD}  Linked Deployment(s):${RESET}"
      while IFS= read -r deploy_name; do
        [[ -z "$deploy_name" ]] && continue
        row "    Deployment" "${SVC_NS}/${deploy_name}"
        export_resource "deployment" "$deploy_name" "$SVC_NS" "05-deployment"
      done <<< "$MATCHED_DEPLOYS"
    else
      warn "No Deployment matched selector '${SVC_SELECTOR}', trying StatefulSet..."
      SS_JSON=$(kubectl get statefulset -n "$SVC_NS" -o json 2>/dev/null || echo '{"items":[]}')
      MATCHED_SS=$(echo "$SS_JSON" | jq -r --arg sel "$SVC_SELECTOR" '
        ( $sel | split(",") | map(split("=") | {key: .[0], value: .[1]}) ) as $pairs |
        [ .items[] |
          (.spec.selector.matchLabels // {}) as $ml |
          select($pairs | all(.key as $k | .value as $v | $ml[$k] == $v)) |
          .metadata.name
        ] | .[]
      ' 2>/dev/null || true)
      if [[ -n "$MATCHED_SS" ]]; then
        while IFS= read -r ss_name; do
          [[ -z "$ss_name" ]] && continue
          row "    StatefulSet" "${SVC_NS}/${ss_name}"
          export_resource "statefulset" "$ss_name" "$SVC_NS" "05-statefulset"
        done <<< "$MATCHED_SS"
      fi
    fi
  fi

done < <(echo "$ENRICHED_DEST" | jq -c '.[]')

append_json "services" "$SVC_DETAIL_LIST"

# =============================================================================
# STEP 5 — Full-chain mapping summary
# =============================================================================
section "📊 STEP 5 — Full-Chain Mapping Summary"

echo -e "${BOLD}"
printf "  %-18s %-35s %-25s\n" "Layer" "Resource (Namespace/Name)" "Key Info"
echo -e "${RESET}${BLUE}  ──────────────────────────────────────────────────────────────────────────────${RESET}"

printf "  ${GREEN}%-18s${RESET} %-35s %-25s\n" \
  "[1] Gateway" \
  "${GW_NS}/${GW_NAME}" \
  "selector: ${GW_SELECTOR}"

echo "$PATH_MATCHED_VS" | jq -r '.[] | "\(.namespace)/\(.name)|\(.hosts | join(","))"' | while IFS='|' read -r vsref vshosts; do
  printf "  ${YELLOW}%-18s${RESET} %-35s %-25s\n" "[2] VirtualService" "$vsref" "hosts: $vshosts"
done

echo "$ENRICHED_DEST" | jq -r '.[] | "\(.raw_host)|\(.subset // "-")|\(.port // "-")|\(.weight // 100)|\(.destination_rules | map(.namespace + "/" + .name) | join(",") | if . == "" then "(none)" else . end)"' | \
while IFS='|' read -r h sub port wt dr; do
  printf "  ${MAGENTA}%-18s${RESET} %-35s %-25s\n" "[3] Destination" "host: $h  subset: $sub" "port: $port  weight: ${wt}%"
  [[ "$dr" != "(none)" ]] && printf "  ${MAGENTA}%-18s${RESET} %-35s\n" "  DestinationRule" "$dr"
done

echo "$SVC_DETAIL_LIST" | jq -r '.[] | "\(.namespace)/\(.name)|\(.clusterIP)|\(.ports)|\(.endpoints)"' | while IFS='|' read -r sref cip ports ep; do
  printf "  ${CYAN}%-18s${RESET} %-35s %-25s\n" "[4] Service" "$sref" "ClusterIP: $cip"
  printf "  ${CYAN}%-18s${RESET} %-35s\n" "    Ports" "$ports"
  printf "  ${CYAN}%-18s${RESET} %-35s\n" "    Endpoints" "${ep:-'(none)'}"
done

echo -e "${BLUE}  ──────────────────────────────────────────────────────────────────────────────${RESET}"
echo ""
success "Trace complete."

# =============================================================================
# STEP 6 — YAML export file index
# =============================================================================
if [[ "$EXPORT_YAML" == true ]]; then
  section "📁 STEP 6 — Exported YAML Template Index"
  echo -e "  Output dir: ${BOLD}$(realpath "$OUT_DIR")${RESET}\n"

  YAML_FILES_FOUND=false
  declare -A KIND_EMOJI=(
    ["gateway"]="🌐" ["virtualservice"]="🔀" ["destinationrule"]="🎯"
    ["service"]="⚙️ " ["deployment"]="🚀" ["statefulset"]="🗄️ "
  )

  while IFS= read -r fpath; do
    [[ ! -f "$fpath" ]] && continue
    YAML_FILES_FOUND=true
    fname=$(basename "$fpath")
    fsize=$(wc -l < "$fpath")
    ns_line=$(grep "^# Namespace" "$fpath" 2>/dev/null | head -1 | sed 's/# Namespace *: *//')
    kind_key=$(echo "$fname" | sed 's/^[0-9]*-//' | cut -d'-' -f1)
    emoji="${KIND_EMOJI[$kind_key]:-📄}"
    printf "  %s  ${BOLD}%-45s${RESET}  ns: %-20s  [%d lines]\n" \
      "$emoji" "$fname" "$ns_line" "$fsize"
  done < <(find "$OUT_DIR" -name "*.yaml" | sort)

  if [[ "$YAML_FILES_FOUND" == false ]]; then
    warn "No YAML files were generated (resources may not exist or insufficient permissions)"
  else
    echo ""
    echo -e "  ${BOLD}How to use:${RESET}"
    echo -e "  ${CYAN}# Inspect a template${RESET}"
    echo -e "  cat ${OUT_DIR}/02-virtualservice-*.yaml"
    echo ""
    echo -e "  ${CYAN}# Edit and apply for a new API${RESET}"
    echo -e "  kubectl apply -f ${OUT_DIR}/02-virtualservice-*.yaml"
    echo ""
    echo -e "  ${CYAN}# Apply all resources in order${RESET}"
    echo -e "  for f in \$(ls ${OUT_DIR}/*.yaml | sort); do kubectl apply -f \"\$f\"; done"
  fi
fi

# =============================================================================
# JSON output
# =============================================================================
if [[ "$OUTPUT_JSON" == true ]]; then
  OUT_FILE="${OUT_DIR}/trace-output.json"
  FINAL_JSON=$(jq -n \
    --arg url "$TARGET_URL" \
    --arg host "$INPUT_HOST" \
    --arg path "$INPUT_PATH" \
    --argjson result "$RESULT_JSON" \
    '{ traced_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")), input: {url: $url, host: $host, path: $path}, chain: $result }')
  echo "$FINAL_JSON" > "$OUT_FILE"
  success "JSON output written to: $OUT_FILE"
fi
```