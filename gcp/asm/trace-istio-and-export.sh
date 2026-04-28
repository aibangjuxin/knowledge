#!/usr/bin/env bash
# =============================================================================
# trace-istio.sh — Istio Full-Chain Asset Tracing + YAML Template Export Script
# Purpose: Reverse-trace from URL to Gateway -> VirtualService -> DestinationRule -> Service -> Deployment
#          Export each key resource as a clean YAML template (ready for new API onboarding)
# Dependencies: kubectl, jq, bash >= 4.0
# Usage: ./trace-istio.sh --url https://api.example.com/v1/health
#        ./trace-istio.sh --url https://api.example.com/v1/health --export-yaml
#        ./trace-istio.sh --url https://api.example.com/v1/health --export-yaml --out-dir ./my-templates
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Colors & Formatting
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
MAGENTA='\033[0;35m'; WHITE='\033[1;37m'

info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; \
echo -e "${BOLD}${WHITE} $*${RESET}"; \
echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; }
row() { printf " ${CYAN}%-28s${RESET} %s\n" "$1" "$2"; }

# --------------------------------------------------------------------------- #
# Argument Parsing
# --------------------------------------------------------------------------- #
TARGET_URL=""
HINT_NS="" # Optional: narrow search scope
OUTPUT_JSON=false # --json output raw JSON data
EXPORT_YAML=false # --export-yaml export clean YAML templates
OUT_DIR="" # --out-dir specify output directory

usage() {
cat <<EOF
Usage: $(basename "$0") --url <URL> [OPTIONS]

--url URL          Target URL, e.g. https://api.example.com/v1/health
--namespace NS     Optional, specify Gateway Namespace to speed up search
--json             Also output raw JSON data to <out-dir>/trace-output.json
--export-yaml      Export clean YAML templates for each resource in the chain (ready for new API onboarding)
--out-dir DIR      Specify YAML/JSON output directory (default: ./istio-trace-<host>-<timestamp>)
-h, --help         Show this help message

Examples:
$(basename "$0") --url https://api.example.com/v1/health
$(basename "$0") --url https://api.example.com/v1/health --export-yaml
$(basename "$0") --url https://api.example.com/v1/health --export-yaml --out-dir ./templates --json
EOF
exit 0
}

while [[ $# -gt 0 ]]; do
case "$1" in
--url) TARGET_URL="$2"; shift 2 ;;
--namespace) HINT_NS="$2"; shift 2 ;;
--json) OUTPUT_JSON=true; shift ;;
--export-yaml) EXPORT_YAML=true; shift ;;
--out-dir) OUT_DIR="$2"; shift 2 ;;
-h|--help) usage ;;
*) error "Unknown argument: $1"; usage ;;
esac
done

[[ -z "$TARGET_URL" ]] && { error "--url is required"; usage; }

# --------------------------------------------------------------------------- #
# URL Parsing
# --------------------------------------------------------------------------- #
# Strip schema and extract host and path
_no_schema="${TARGET_URL#*://}"
INPUT_HOST="${_no_schema%%/*}"
INPUT_PATH="/${_no_schema#*/}"
# Default to / if no path
[[ "$INPUT_PATH" == "/$INPUT_HOST" || "$INPUT_PATH" == "/" ]] && INPUT_PATH="/"

# --------------------------------------------------------------------------- #
# Dependency Check
# --------------------------------------------------------------------------- #
for cmd in kubectl jq; do
command -v "$cmd" &>/dev/null || { error "Missing dependency: $cmd"; exit 1; }
done

# --------------------------------------------------------------------------- #
# Global JSON Result Object (for --json output)
# --------------------------------------------------------------------------- #
RESULT_JSON='{}'

append_json() {
local key="$1" val="$2"
RESULT_JSON=$(echo "$RESULT_JSON" | jq --argjson v "$val" ". + {\"$key\": \$v}")
}

# --------------------------------------------------------------------------- #
# Output Directory Initialization
# --------------------------------------------------------------------------- #
_HOST_SLUG=$(echo "$INPUT_HOST" | tr '.' '-')
_TIMESTAMP=$(date +%Y%m%d%H%M%S)
[[ -z "$OUT_DIR" ]] && OUT_DIR="./istio-trace-${_HOST_SLUG}-${_TIMESTAMP}"

if [[ "$EXPORT_YAML" == true || "$OUTPUT_JSON" == true ]]; then
mkdir -p "$OUT_DIR"
info "Output directory: $(realpath "$OUT_DIR")"
fi

# --------------------------------------------------------------------------- #
# clean_yaml: Remove runtime noise fields from kubectl get -o yaml output
# Usage: clean_yaml <kind> <name> <namespace> [<out_file>]
# --------------------------------------------------------------------------- #
clean_yaml() {
local kind="$1" name="$2" ns="$3" out_file="${4:-}"

local raw
raw=$(kubectl get "$kind" "$name" -n "$ns" -o yaml 2>/dev/null) || { warn "Cannot get ${kind}/${name} -n ${ns}"; return 1; }

# kubectl --export is deprecated, use jq/python for cleaning
# Remove fields: metadata.{managedFields, resourceVersion, uid, generation,
# creationTimestamp, annotations."kubectl.kubernetes.io/last-applied-configuration"}
# Remove: status block
local cleaned
cleaned=$(echo "$raw" | python3 -c "
import sys, yaml, json

data = yaml.safe_load(sys.stdin)
if not data:
    sys.exit(0)

# Clean metadata
meta = data.get('metadata', {})
for field in ['managedFields', 'resourceVersion', 'uid', 'generation',
              'creationTimestamp', 'selfLink']:
    meta.pop(field, None)

# Clean annotations
ann = meta.get('annotations', {})
ann.pop('kubectl.kubernetes.io/last-applied-configuration', None)
ann.pop('deployment.kubernetes.io/revision', None)
# Remove all kubectl/k8s internal annotations (optional, enable as needed)
# meta['annotations'] = {k: v for k, v in ann.items() if not k.startswith('kubectl.')}
if not ann:
    meta.pop('annotations', None)

# Remove status block entirely
data.pop('status', None)

# For Deployment: clean pod template runtime fields
if data.get('kind') == 'Deployment':
    spec = data.get('spec', {})
    tmpl_meta = spec.get('template', {}).get('metadata', {})
    for f in ['creationTimestamp']:
        tmpl_meta.pop(f, None)

print(yaml.dump(data, default_flow_style=False, allow_unicode=True, sort_keys=False))
" 2>/dev/null) || { warn "python3 yaml module unavailable, falling back to jq cleaning..."; cleaned=$(echo "$raw" | kubectl neat 2>/dev/null || \
echo "$raw" | python3 -c "
import sys
lines = sys.stdin.readlines()
skip = False
result = []
skip_keys = {' managedFields:', ' resourceVersion:', ' uid:', ' generation:',
             ' creationTimestamp:', ' selfLink:', 'status:'}
i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    # Skip status block entirely
    if line.startswith('status:'):
        i += 1
        while i < len(lines) and (lines[i].startswith(' ') or lines[i] == '\n'):
            i += 1
        continue
    # Skip managedFields block
    if ' managedFields:' in line:
        i += 1
        while i < len(lines) and lines[i].startswith(' - ') or (i < len(lines) and lines[i].startswith(' ')):
            i += 1
        continue
    # Skip single-line noise fields
    skip_this = False
    for k in [' resourceVersion:', ' uid:', ' generation:', ' creationTimestamp:', ' selfLink:']:
        if line.strip().startswith(k.strip()):
            skip_this = True; break
    if not skip_this:
        result.append(line)
    i += 1
print(''.join(result))
"); }

if [[ -n "$out_file" ]]; then
{ echo "# ============================================================"; \
echo "# Resource : ${kind}/${name}"; \
echo "# Namespace: ${ns}"; \
echo "# Exported : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; \
echo "# Source   : $TARGET_URL"; \
echo "# NOTE     : status/managedFields/uid/resourceVersion etc. removed"; \
echo "#            Can be modified and used with kubectl apply -f"; \
echo "# ============================================================"; \
echo ""; \
echo "$cleaned"; } > "$out_file"
success " → $(basename "$out_file")"
else
echo "$cleaned"
fi
}

# --------------------------------------------------------------------------- #
# export_resource: Unified entry, decide whether to write file
# Usage: export_resource <kind> <name> <namespace> <label_prefix>
# --------------------------------------------------------------------------- #
export_resource() {
local kind="$1" name="$2" ns="$3" prefix="$4"
if [[ "$EXPORT_YAML" == true ]]; then
local fname="${OUT_DIR}/${prefix}-$(echo "$ns" | tr '/' '-')-${name}.yaml"
clean_yaml "$kind" "$name" "$ns" "$fname"
fi
}

section "🚀 Istio Full-Chain Tracing"
row "Target URL" "$TARGET_URL"
row "Parsed Host" "$INPUT_HOST"
row "Parsed Path" "$INPUT_PATH"
[[ -n "$HINT_NS" ]] && row "Hint NS" "$HINT_NS"
echo ""

# =============================================================================
# STEP 1: Locate Gateway
# =============================================================================
section "📍 STEP 1 — Locating Gateway"

info "Fetching all Gateway resources..."
GW_NS_FLAG="${HINT_NS:+-n $HINT_NS}"
ALL_GW_JSON=$(kubectl get gateway ${GW_NS_FLAG:--A} -o json 2>/dev/null || echo '{"items":[]}')

GW_COUNT=$(echo "$ALL_GW_JSON" | jq '.items | length')
info "Found ${GW_COUNT} Gateway(s)"

# Matching logic: exact host match, or * wildcard
MATCHED_GW=$(echo "$ALL_GW_JSON" | jq --arg host "$INPUT_HOST" '
[ .items[] |
. as $gw |
(.metadata.namespace) as $ns |
(.metadata.name) as $name |
(.spec.selector // {}) as $sel |
[ .spec.servers[]?.hosts[]? |
select(. == $host or . == "*" or
(startswith("*.") and ($host | endswith(ltrimstr("*", .)))))
] |
if length > 0 then {
name: $name,
namespace: $ns,
selector: $sel,
matched_host: .[0],
is_wildcard: (.[0] == "*")
} else empty end
] | sort_by(.is_wildcard) # Exact match comes first
')

GW_MATCH_COUNT=$(echo "$MATCHED_GW" | jq 'length')

if [[ "$GW_MATCH_COUNT" -eq 0 ]]; then
error "No Gateway found matching host='$INPUT_HOST' (including wildcard *)"
exit 1
fi

echo "$MATCHED_GW" | jq -r '.[] | " \(if .is_wildcard then "⚠ [wildcard]" else "✓ [exact]" end) \(.namespace)/\(.name) matched_host=\(.matched_host) selector=\(.selector | to_entries | map("\(.key)=\(.value)") | join(","))"'

# Use the first one (exact match priority)
SELECTED_GW=$(echo "$MATCHED_GW" | jq '.[0]')
GW_NAME=$(echo "$SELECTED_GW" | jq -r '.name')
GW_NS=$(echo "$SELECTED_GW" | jq -r '.namespace')
GW_SELECTOR=$(echo "$SELECTED_GW" | jq -r '.selector | to_entries | map("\(.key)=\(.value)") | join(",")')

echo ""
success "Using Gateway: ${GW_NS}/${GW_NAME} (selector: ${GW_SELECTOR})"

# Find IngressGateway Pod
info "Finding IngressGateway Pod (selector: ${GW_SELECTOR})..."
IGW_PODS=$(kubectl get pods -A -l "$GW_SELECTOR" \
--no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP" 2>/dev/null || true)

if [[ -n "$IGW_PODS" ]]; then
echo -e "\n ${BOLD}IngressGateway Pods:${RESET}"
echo "$IGW_PODS" | while read -r line; do echo " $line"; done
else
warn "No matching IngressGateway Pod found, selector may not be in default Namespace"
fi

append_json "gateway" "$SELECTED_GW"

# Export Gateway YAML
export_resource "gateway" "$GW_NAME" "$GW_NS" "01-gateway"

# =============================================================================
# STEP 2: Correlate VirtualService
# =============================================================================
section "🔀 STEP 2 — Correlating VirtualService"

info "Fetching all VirtualServices..."
ALL_VS_JSON=$(kubectl get virtualservice -A -o json 2>/dev/null || echo '{"items":[]}')

VS_COUNT=$(echo "$ALL_VS_JSON" | jq '.items | length')
info "Found ${VS_COUNT} VirtualService(s)"

# VS matching logic: gateways field contains GW_NAME or GW_NS/GW_NAME
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
# Also check if vs.spec.hosts matches
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
. as $http |
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
error "No VirtualService found associated with Gateway '${GW_NS}/${GW_NAME}' and matching host"
exit 1
fi

info "Found ${VS_MATCH_COUNT} candidate VirtualService(s)"

# Path filtering: match INPUT_PATH prefix
PATH_MATCHED_VS=$(echo "$MATCHED_VS" | jq --arg path "$INPUT_PATH" '
[ .[] |
. as $vs |
(.http_routes | map(
select(
.match_uris == [] or
(.match_uris | any(
(startswith("prefix=") and ($path | startswith(ltrimstr("prefix=", .)))) or
(startswith("exact=") and (ltrimstr("exact=", .) == $path)) or
(startswith("regex=") )
))
))
)) as $matched_routes |
if ($matched_routes | length) > 0 then
$vs + {matched_routes: $matched_routes}
else empty end
]
')

PATH_MATCH_COUNT=$(echo "$PATH_MATCHED_VS" | jq 'length')
if [[ "$PATH_MATCH_COUNT" -eq 0 ]]; then
warn "Path '${INPUT_PATH}' has no exact match, falling back to show all associated VirtualServices"
PATH_MATCHED_VS="$MATCHED_VS"
PATH_MATCHED_VS=$(echo "$MATCHED_VS" | jq '[.[] | . + {matched_routes: .http_routes}]')
fi

echo "$PATH_MATCHED_VS" | jq -r '.[] | " ✓ \(.namespace)/\(.name) hosts=\(.hosts | join(","))"'

append_json "virtualservices" "$PATH_MATCHED_VS"

# =============================================================================
# STEP 3: Extract Destinations & DestinationRule
# =============================================================================
section "🎯 STEP 3 — Extracting Destinations & DestinationRule"

info "Fetching all DestinationRules..."
ALL_DR_JSON=$(kubectl get destinationrule -A -o json 2>/dev/null || echo '{"items":[]}')

# Extract all destination hosts from matched VS
ALL_DEST_JSON=$(echo "$PATH_MATCHED_VS" | jq '
[ .[] |
.namespace as $vsns |
.matched_routes[]?.route_destinations[]? | {
raw_host: .host,
subset: .subset,
port: .port,
weight: .weight,
vs_namespace: $vsns
}
] | unique_by(.raw_host + (.subset // ""))
')

DEST_COUNT=$(echo "$ALL_DEST_JSON" | jq 'length')
info "Found ${DEST_COUNT} Destination(s)"

# Enrich each destination with FQDN and correlate DR
ENRICHED_DEST=$(echo "$ALL_DEST_JSON" | jq --argjson drs "$ALL_DR_JSON" '
[ .[] |
. as $dest |
($dest.raw_host) as $rh |
($dest.vs_namespace) as $vsns |
# Complete FQDN
(if ($rh | contains(".svc.cluster.local")) then $rh
elif ($rh | contains(".")) then $rh
else "\($rh).\($vsns).svc.cluster.local" end) as $fqdn |
# Short name (for Service lookup)
($rh | split(".")[0]) as $svcname |
# Correlate DestinationRule
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
" ✓ host=\(.raw_host) subset=\(.subset // "-") port=\(.port // "-") weight=\(.weight // 100)",
" FQDN: \(.fqdn)",
(if (.destination_rules | length) > 0 then
" DestinationRule: \(.destination_rules | map("\(.namespace)/\(.name)") | join(", "))"
else
" DestinationRule: (none)"
end)'

append_json "destinations" "$ENRICHED_DEST"

# Export VirtualService YAML (each matched VS)
if [[ "$EXPORT_YAML" == true ]]; then
info "Exporting VirtualService YAML..."
while IFS= read -r vs_item; do
_vs_name=$(echo "$vs_item" | jq -r '.name')
_vs_ns=$(echo "$vs_item" | jq -r '.namespace')
export_resource "virtualservice" "$_vs_name" "$_vs_ns" "02-virtualservice"
done < <(echo "$PATH_MATCHED_VS" | jq -c '.[]')
fi

# Export DestinationRule YAML
if [[ "$EXPORT_YAML" == true ]]; then
info "Exporting DestinationRule YAML..."
echo "$ENRICHED_DEST" | jq -c '[.[].destination_rules[] | {name,namespace}] | unique[]' | \
while IFS= read -r dr_item; do
_dr_name=$(echo "$dr_item" | jq -r '.name')
_dr_ns=$(echo "$dr_item" | jq -r '.namespace')
export_resource "destinationrule" "$_dr_name" "$_dr_ns" "03-destinationrule"
done
fi

# =============================================================================
# STEP 4: Map Kubernetes Service & Pods
# =============================================================================
section "⚙️ STEP 4 — Kubernetes Service & Endpoints & Pods"

SVC_DETAIL_LIST='[]'

while IFS= read -r dest_item; do
SVC_NAME=$(echo "$dest_item" | jq -r '.svc_name')
SVC_NS=$(echo "$dest_item" | jq -r '.vs_namespace')
SUBSET=$(echo "$dest_item" | jq -r '.subset // ""')

info "Finding Service: ${SVC_NS}/${SVC_NAME}"

SVC_JSON=$(kubectl get service "$SVC_NAME" -n "$SVC_NS" -o json 2>/dev/null || echo 'null')

if [[ "$SVC_JSON" == "null" ]]; then
warn "Service '${SVC_NS}/${SVC_NAME}' does not exist, trying cross-Namespace search..."
SVC_JSON=$(kubectl get service "$SVC_NAME" -A -o json 2>/dev/null | jq '.items[0] // null')
[[ "$SVC_JSON" == "null" ]] && { warn "Service '$SVC_NAME' not found, skipping"; continue; }
SVC_NS=$(echo "$SVC_JSON" | jq -r '.metadata.namespace')
info "Found Service in Namespace '$SVC_NS'"
fi

SVC_LABELS=$(echo "$SVC_JSON" | jq -r '.metadata.labels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
SVC_SELECTOR=$(echo "$SVC_JSON" | jq -r '.spec.selector // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
SVC_CLUSTERIP=$(echo "$SVC_JSON" | jq -r '.spec.clusterIP // "-"')
SVC_TYPE=$(echo "$SVC_JSON" | jq -r '.spec.type // "-"')
SVC_PORTS=$(echo "$SVC_JSON" | jq -r '.spec.ports // [] | map("\(.port)/\(.protocol // "TCP") -> \(.targetPort)") | join(", ")')

echo -e "\n ${BOLD}Service: ${SVC_NS}/${SVC_NAME}${RESET}"
row " Type" "$SVC_TYPE"
row " ClusterIP" "$SVC_CLUSTERIP"
row " Ports" "$SVC_PORTS"
row " Selector" "${SVC_SELECTOR:-'(no selector)'}"
row " Labels" "${SVC_LABELS}"

# Endpoints
EP_JSON=$(kubectl get endpoints "$SVC_NAME" -n "$SVC_NS" -o json 2>/dev/null || echo 'null')
EP_ADDRS=$(echo "$EP_JSON" | jq -r '
[ .subsets[]?.addresses[]? | "\(.ip):\(.targetRef.name // "?")" ] | join(", ")
' 2>/dev/null || echo "-")
row " Endpoints" "${EP_ADDRS:-'(no ready endpoint)'}"

# Pods
POD_INFO=""
if [[ -n "$SVC_SELECTOR" ]]; then
POD_JSON=$(kubectl get pods -n "$SVC_NS" -l "$SVC_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(echo "$POD_JSON" | jq '.items | length')
row " Pod Count" "$POD_COUNT"

if [[ "$POD_COUNT" -gt 0 ]]; then
echo -e "\n ${BOLD} Pod List:${RESET}"
POD_INFO=$(echo "$POD_JSON" | jq -r '
.items[] |
" \(.metadata.name) IP=\(.status.podIP // "-") Node=\(.spec.nodeName // "-") Phase=\(.status.phase // "-") Ready=\(
[.status.containerStatuses[]?.ready] | all | if . then "✓" else "✗" end
) Version=\(.metadata.labels["version"] // .metadata.labels["app.kubernetes.io/version"] // "-")"
')
echo "$POD_INFO"
fi

# Subset version validation
if [[ -n "$SUBSET" && "$SUBSET" != "null" ]]; then
echo ""
info "Validating Pod match for Subset='${SUBSET}'..."
DR_SUBSET_LABELS=$(echo "$dest_item" | jq -r --arg sub "$SUBSET" '
.destination_rules[0].subsets // [] |
map(select(.name == $sub)) |
.[0].labels // {} |
to_entries | map("\(.key)=\(.value)") | join(",")
')
if [[ -n "$DR_SUBSET_LABELS" ]]; then
SUBSET_PODS=$(kubectl get pods -n "$SVC_NS" -l "${SVC_SELECTOR},${DR_SUBSET_LABELS}" --no-headers \
-o custom-columns="NAME:.metadata.name,IP:.status.podIP,PHASE:.status.phase" 2>/dev/null | wc -l | tr -d ' ')
row " Subset Pods" "${SUBSET_PODS} (labels: ${DR_SUBSET_LABELS})"
else
warn "Subset '${SUBSET}' has no labels defined in DestinationRule"
fi
fi
else
warn "Service has no selector (may be ExternalName or Headless)"
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

# ── Export Service YAML ──────────────────────────────────────────────────────
export_resource "service" "$SVC_NAME" "$SVC_NS" "04-service"

# ── Find and Export Associated Deployment ────────────────────────────────────
if [[ -n "$SVC_SELECTOR" ]]; then
info "Finding Associated Deployment (selector: ${SVC_SELECTOR})..."
DEPLOY_JSON=$(kubectl get deployment -n "$SVC_NS" -o json 2>/dev/null || echo '{"items":[]}')
# Find Deployment with selector matchLabels containing Service selector
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
echo -e "\n ${BOLD} Associated Deployment:${RESET}"
while IFS= read -r deploy_name; do
[[ -z "$deploy_name" ]] && continue
row " Deployment" "${SVC_NS}/${deploy_name}"
export_resource "deployment" "$deploy_name" "$SVC_NS" "05-deployment"
done <<< "$MATCHED_DEPLOYS"
else
warn "No Deployment found matching selector '${SVC_SELECTOR}' (may be StatefulSet or other controller)"
# Try StatefulSet
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
row " StatefulSet" "${SVC_NS}/${ss_name}"
export_resource "statefulset" "$ss_name" "$SVC_NS" "05-statefulset"
done <<< "$MATCHED_SS"
fi
fi
fi

done < <(echo "$ENRICHED_DEST" | jq -c '.[]')

append_json "services" "$SVC_DETAIL_LIST"

# =============================================================================
# STEP 5: Summary Mapping Table
# =============================================================================
section "📊 STEP 5 — Full-Chain Mapping Summary"

echo -e "${BOLD}"
printf " %-18s %-35s %-25s\n" "Layer" "Resource (Namespace/Name)" "Key Info"
echo -e "${RESET}${BLUE} ──────────────────────────────────────────────────────────────────────────────${RESET}"

printf " ${GREEN}%-18s${RESET} %-35s %-25s\n" \
"[1] Gateway" \
"${GW_NS}/${GW_NAME}" \
"selector: ${GW_SELECTOR}"

echo "$PATH_MATCHED_VS" | jq -r '.[] | "\(.namespace)/\(.name)|\(.hosts | join(","))"' | while IFS='|' read -r vsref vshosts; do
printf " ${YELLOW}%-18s${RESET} %-35s %-25s\n" "[2] VirtualService" "$vsref" "hosts: $vshosts"
done

echo "$ENRICHED_DEST" | jq -r '.[] | "\(.raw_host)|\(.subset // "-")|\(.port // "-")|\(.weight // 100)|\(.destination_rules | map(.namespace + "/" + .name) | join(",") | if . == "" then "(noDR)" else . end)"' | \
while IFS='|' read -r h sub port wt dr; do
printf " ${MAGENTA}%-18s${RESET} %-35s %-25s\n" "[3] Destination" "host: $h subset: $sub" "port: $port weight: ${wt}%"
[[ "$dr" != "(noDR)" ]] && printf " ${MAGENTA}%-18s${RESET} %-35s\n" " DestinationRule" "$dr"
done

echo "$SVC_DETAIL_LIST" | jq -r '.[] | "\(.namespace)/\(.name)|\(.clusterIP)|\(.ports)|\(.endpoints)"' | while IFS='|' read -r sref cip ports ep; do
printf " ${CYAN}%-18s${RESET} %-35s %-25s\n" "[4] Service" "$sref" "ClusterIP: $cip"
printf " ${CYAN}%-18s${RESET} %-35s\n" " Ports" "$ports"
printf " ${CYAN}%-18s${RESET} %-35s\n" " Endpoints" "${ep:-'(none)'}"
done

echo -e "${BLUE} ──────────────────────────────────────────────────────────────────────────────${RESET}"
echo ""
success "Chain tracing complete!"

# =============================================================================
# STEP 6: YAML Export File Index
# =============================================================================
if [[ "$EXPORT_YAML" == true ]]; then
section "📁 STEP 6 — YAML Template Export Index"
echo -e " Output directory: ${BOLD}$(realpath "$OUT_DIR")${RESET}\n"

YAML_FILES_FOUND=false
declare -A KIND_EMOJI=(
["gateway"]="🌐" ["virtualservice"]="🔀" ["destinationrule"]="🎯"
["service"]="⚙️ " ["deployment"]="🚀" ["statefulset"]="🗄️ "
)

# List in filename order (01- 02- ... ensures order)
while IFS= read -r fpath; do
[[ ! -f "$fpath" ]] && continue
YAML_FILES_FOUND=true
fname=$(basename "$fpath")
fsize=$(wc -l < "$fpath")
# Extract resource info from file header comment
res_line=$(grep "^# Resource" "$fpath" 2>/dev/null | head -1 | sed 's/# Resource *: *//')
ns_line=$(grep "^# Namespace" "$fpath" 2>/dev/null | head -1 | sed 's/# Namespace *: *//')
kind_key=$(echo "$fname" | sed 's/^[0-9]*-//' | cut -d'-' -f1)
emoji="${KIND_EMOJI[$kind_key]:-📄}"
printf " %s ${BOLD}%-45s${RESET} %s [%d lines]\n" \
"$emoji" "$fname" "ns: $ns_line" "$fsize"
done < <(find "$OUT_DIR" -name "*.yaml" | sort)

if [[ "$YAML_FILES_FOUND" == false ]]; then
warn "No YAML files generated (resources may not exist or insufficient permissions)"
else
echo ""
echo -e " ${BOLD}Usage:${RESET}"
echo -e " ${CYAN}# View a specific template${RESET}"
echo -e " cat ${OUT_DIR}/02-virtualservice-*.yaml"
echo ""
echo -e " ${CYAN}# Modify and apply directly (new API onboarding)${RESET}"
echo -e " kubectl apply -f ${OUT_DIR}/02-virtualservice-*.yaml"
echo ""
echo -e " ${CYAN}# Apply all in order${RESET}"
echo -e " for f in \$(ls ${OUT_DIR}/*.yaml | sort); do kubectl apply -f \$f; done"
fi
fi

# =============================================================================
# JSON Output
# =============================================================================
if [[ "$OUTPUT_JSON" == true ]]; then
OUT_FILE="./trace-output-$(date +%Y%m%d%H%M%S).json"
FINAL_JSON=$(jq -n \
--arg url "$TARGET_URL" \
--arg host "$INPUT_HOST" \
--arg path "$INPUT_PATH" \
--argjson result "$RESULT_JSON" \
'{ traced_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")), input: {url: $url, host: $host, path: $path}, chain: $result }')
echo "$FINAL_JSON" > "$OUT_FILE"
success "JSON result written to: $OUT_FILE"
fi