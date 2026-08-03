# Shell Scripts Collection

Generated on: 2026-08-02 13:14:35
Directory: /Users/lex/git/gcp/gke/opa-gatekeeper

## `verify-gatekeeper.sh`

```bash
#!/usr/bin/env bash
# verify-gatekeeper.sh
# ------------------------------------------------------------------
# One-shot Gatekeeper audit report for a GKE cluster.
#
# Examples:
#   ./verify-gatekeeper.sh -e dev-cn
#   ./verify-gatekeeper.sh --environment lex-in
#   ./verify-gatekeeper.sh -e dev-cn --output json > report.json
#
# Sections printed (categorized):
#   1. Cluster + Gatekeeper installation summary
#   2. ConstraintTemplate inventory (kind + code version)
#   3. Constraint inventory grouped by kind + enforcement status
#   4. Per-constraint violations (compliant vs. violating counts)
#   5. Recent audit events (last N=20) from gatekeeper-system
#   6. Audit / Admission webhook health
#   7. Exempted namespaces summary
#
# Author: Lex + Hermes Agent
# ------------------------------------------------------------------

set -euo pipefail

# ---------- color helpers ----------
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly RED=$'\033[31m'
readonly GREEN=$'\033[32m'
readonly YELLOW=$'\033[33m'
readonly BLUE=$'\033[34m'
readonly CYAN=$'\033[36m'
readonly RESET=$'\033[0m'

# ---------- env table (port your `source.sh` pattern) ----------
declare -A ENV_INFO
ENV_INFO=(
  [dev-cn]="project=aibang-teng-sit-api-dev cluster=dev-cn-cluster-123789 region=europe-west2 https_proxy=10.72.21.119:3128 private_network=aibang-teng-sit-api-dev-cinternal-vpc3"
  [lex-in]="project=aibang-teng-sit-kongs-dev cluster=lex-in-cluster-123456 region=europe-west2 https_proxy=10.72.25.50:3128 private_network=aibang-teng-sit-kongs-dev-cinternal-vpc1"
)

# ---------- flags ----------
ENVIRONMENT=""
NAMESPACE="gatekeeper-system"
OUTPUT_FORMAT="text"   # text|json
AUDIT_TAIL=20

usage() {
  echo -e "$(cat <<EOF
${BOLD}Usage:${RESET} $0 [--environment ENV] [options]

  -e, --environment ENV   Environment key (one of: ${!ENV_INFO[*]})
      --namespace   NS    Gatekeeper namespace (default: gatekeeper-system)
      --output      FMT   text|json (default: text)
      --audit-tail  N     Number of recent audit events to show (default: 20)
  -h, --help              Show this help

  Tip: pair with your source.sh, e.g.
       source ./source.sh -e dev-cn && ./verify-gatekeeper.sh
EOF
)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --namespace)       NAMESPACE="${2:-}"; shift 2 ;;
    --output)          OUTPUT_FORMAT="${2:-}"; shift 2 ;;
    --audit-tail)      AUDIT_TAIL="${2:-20}"; shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *) usage; echo -e "${RED}ERROR: unknown flag: $1${RESET}" >&2; exit 2 ;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then
  usage; echo -e "${RED}ERROR: --environment is required${RESET}" >&2; exit 2
fi
if [[ -z "${ENV_INFO[$ENVIRONMENT]+x}" ]]; then
  echo -e "${RED}ERROR: unknown environment '$ENVIRONMENT'${RESET}" >&2
  echo "Available: ${!ENV_INFO[*]}" >&2
  exit 2
fi
if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
  echo -e "${RED}ERROR: --output must be text or json${RESET}" >&2; exit 2
fi

# ---------- pull env vars ----------
ENV_VARS="${ENV_INFO[$ENVIRONMENT]}"
IFS=' ' read -r -a _var_array <<< "$ENV_VARS"
for _v in "${_var_array[@]}"; do
  if [[ "$_v" == *=* ]]; then
    _k="${_v%%=*}"; _val="${_v#*=}"
    eval "export $_k='$_val'"
  fi
done

# ---------- gcloud + kube context ----------
ctx_init() {
  echo -e "${CYAN}==> Activating gcloud config${RESET}"
  echo "    project:   $project"
  echo "    cluster:    $cluster"
  echo "    region:     $region"
  gcloud config set project "$project" >/dev/null
  gcloud container clusters get-credentials "$cluster" \
    --region "$region" --project "$project" >/dev/null
  echo -e "    context:    $(kubectl config current-context)"
}

# ---------- helpers ----------
bold()  { echo -e "${BOLD}$*${RESET}"; }
sect()  { echo -e "\n${BOLD}${BLUE}==== $* ====${RESET}"; }
ok()    { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $*"; }
err()   { echo -e "  ${RED}✗${RESET} $*"; }
note()  { echo -e "  ${DIM}$*${RESET}"; }

# Capture kubectl json output; tolerate empty/missing CRDs.
# Usage: kjson <kubectl args>; prints "" on empty.
kjson() {
  local out
  out="$(kubectl "$@" -o json 2>/dev/null || true)"
  if [[ -z "$out" || "$out" == "null" ]]; then
    echo ""
  else
    echo "$out"
  fi
}

# ---------- 1. cluster + gatekeeper installation ----------
section_cluster_summary() {
  sect "1. Cluster & Gatekeeper installation"
  local srv ver
  srv=$(kubectl version --output=yaml 2>/dev/null || true)
  local k8s
  k8s=$(echo "$srv" | awk '/serverVersion:/{k=1;next}k&&/gitVersion:/{print;exit}' | awk '{print $2}')
  [[ -z "$k8s" ]] && k8s="$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // empty')"
  echo -e "  Kubernetes:     ${BOLD}${k8s:-unknown}${RESET}"
  echo -e "  Nodes:          $(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo -e "  Context:        $(kubectl config current-context)"

  # Gatekeeper pods
  local pods_running pods_total
  pods_running=$(kubectl get deploy -n "$NAMESPACE" --no-headers 2>/dev/null \
    | awk '$2==$5' | wc -l | tr -d ' ')
  pods_total=$(kubectl get deploy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$pods_total" == "0" ]]; then
    err "No Gatekeeper deployments found in namespace '$NAMESPACE'"
  else
    ok "Gatekeeper control-plane: $pods_running / $pods_total deployments Ready"
  fi

  # Gatekeeper image tags (best-effort)
  local img
  img=$(kubectl get deploy -n "$NAMESPACE" -o jsonpath='{..image}' 2>/dev/null \
    | tr ' ' '\n' | grep -E 'gatekeeper|opa:' | sort -u | head -5 || true)
  if [[ -n "$img" ]]; then
    note "Images:"
    echo "$img" | sed 's/^/      /'
  fi
}

# ---------- 2. ConstraintTemplate inventory ----------
section_templates() {
  sect "2. ConstraintTemplate inventory"
  local json; json=$(kjson get constrainttemplates -n "$NAMESPACE")
  if [[ -z "$json" ]]; then
    warn "No ConstraintTemplate CRDs found (is Gatekeeper / Policy Controller installed?)"
    return
  fi

  local count
  count=$(echo "$json" | jq '.items | length')
  echo -e "  Total templates: ${BOLD}$count${RESET}\n"

  echo "$json" | jq -r '
    .items[] | [
      .metadata.name,
      (.spec.crd.spec.names.kind // "?"),
      (.metadata.creationTimestamp // "?"),
      (.metadata.resourceVersion // "?")
    ] | @tsv
  ' | awk -F'\t' '{printf "  %-40s  %-40s  created=%s  rv=%s\n",$1,$2,$3,$4}'
}

# ---------- 3. Constraint inventory ----------
section_constraints() {
  sect "3. Constraint inventory (grouped by kind)"
  local json; json=$(kjson get constraints -A)
  if [[ -z "$json" ]]; then
    warn "No constraints found (cluster-wide scan)"
    return
  fi

  local count
  count=$(echo "$json" | jq '.items | length')
  echo -e "  Total constraints: ${BOLD}$count${RESET}\n"

  # Per-kind enforcement summary
  echo "$json" | jq -r '
    .items
    | group_by(.kind)[] as $g
    | ($g | length) as $n
    | ($g | map(select(.status.totalViolations != null)) | length) as $have
    | {
        kind: $g[0].kind,
        count: $n,
        enrolled: $have,
        violators: ($g | map(select((.status.totalViolations // 0) > 0)) | length),
        exempt: ($g | map(.spec.match.excludedNamespaces // [] | .[]) | unique | join(","))
      }
    | [.kind, .count, .enrolled, .violators, .exempt] | @tsv
  ' | awk -F'\t' '{
      printf "  %-50s  count=%-3s  audited=%-3s  violating=%-3s  exempt-ns=%s\n",
             $1,$2,$3,$4,$5
    }'

  # Full list table
  echo -e "\n  ${BOLD}Full list:${RESET}"
  echo "$json" | jq -r '
    .items[] | [
      .kind,
      .metadata.name,
      (.metadata.namespace // "cluster"),
      (.spec.match.kinds // [] | map(.kinds // .) | tostring),
      (.status.totalViolations // "-"),
      (.status.violations // [] | length)
    ] | @tsv
  ' | awk -F'\t' '{
      printf "    %-50s  %-30s  ns=%-15s  kinds=%-30s  total=%-4s  stale=%s\n",
             $1,$2,$3,$4,$5,$6
    }'
}

# ---------- 4. Violations ----------
section_violations() {
  sect "4. Violations (compliant vs. violating)"
  local json; json=$(kjson get constraints -A)
  if [[ -z "$json" ]]; then
    warn "No constraints to analyze"
    return
  fi

  local stats
  stats=$(echo "$json" | jq '
    {
      total_constraints: (.items | length),
      audited:           (.items | map(select(.status.totalViolations != null)) | length),
      overall_violations: ([.items[].status.totalViolations // 0] | add),
      violating_constraints: (.items | map(select((.status.totalViolations // 0) > 0)) | length),
      compliant_constraints: (.items | map(select((.status.totalViolations // 0) == 0 and .status.totalViolations != null)) | length),
      unaudited_constraints: (.items | map(select(.status.totalViolations == null)) | length)
    }
  ')
  echo "$stats" | jq -r '
    "  Overall: " + (.overall_violations | tostring) + " violations across "
             + (.audited | tostring) + " audited constraints\n"
    + "  Constraints: total=" + (.total_constraints | tostring)
    + "  violating=" + (.violating_constraints | tostring)
    + "  compliant="  + (.compliant_constraints | tostring)
    + "  unaudited=" + (.unaudited_constraints | tostring)
  '

  # Show top violating constraints
  echo -e "\n  ${BOLD}Top violators:${RESET}"
  echo "$json" | jq -r '
    .items
    | map(select((.status.totalViolations // 0) > 0))
    | sort_by(-(.status.totalViolations // 0))
    | .[0:10][]
    | [(.kind + "/" + .metadata.name), (.status.totalViolations // 0),
       (.status.violations // [] | length)] | @tsv
  ' | awk -F'\t' '{
      printf "    %-60s  total=%-4s  stale-cache=%s\n",$1,$2,$3
    }' | head -10

  # Show top violating objects (sample)
  echo -e "\n  ${BOLD}Sample of offending objects (first 10):${RESET}"
  echo "$json" | jq -r '
    [.items[] | . as $c
      | (.status.violations // [])[]
      | {
          constraint: ($c.kind + "/" + $c.metadata.name),
          kind:       .kind,
          namespace:  (.namespace // "cluster"),
          name:       .name,
          message:    .message
        }
    ]
    | .[0:10][]
    | [.constraint, .kind, .namespace, .name, (.message // "")[0:120]] | @tsv
  ' | awk -F'\t' '{
      printf "    %-55s  %-15s  ns=%-15s  name=%-30s\n      ↳ %s\n",
             $1,$2,$3,$4,$5
    }'
}

# ---------- 5. Recent audit events ----------
section_audit_events() {
  sect "5. Recent audit events (last $AUDIT_TAIL)"
  local json
  json=$(kjson get events -n "$NAMESPACE" \
    --field-selector reason=ConstraintViolated \
    --sort-by=.lastTimestamp "${@:--A}")
  if [[ -z "$json" ]]; then
    # fall back: list all events sorted by time
    json=$(kjson get events -n "$NAMESPACE" --sort-by=.lastTimestamp -A)
  fi
  if [[ -z "$json" ]]; then
    warn "No events in namespace '$NAMESPACE'"
    return
  fi

  echo "$json" | jq -r --argjson n "$AUDIT_TAIL" '
    .items
    | sort_by(.lastTimestamp // .metadata.creationTimestamp) | reverse
    | .[0:$n][]
    | [(.lastTimestamp // .metadata.creationTimestamp // "?"),
       .type,
       .reason,
       (.involvedObject.kind // "") + "/" + (.involvedObject.name // ""),
       (.message // "")[0:160]] | @tsv
  ' | awk -F'\t' '{
      printf "    %-25s  %-7s  %-22s  %-40s\n      ↳ %s\n",
             $1,$2,$3,$4,$5
    }'
}

# ---------- 6. Webhook health ----------
section_webhook() {
  sect "6. Audit / Validating webhook health"
  local mutweb valweb
  mutweb=$(kjson get mutatingwebhookconfigurations | jq -r '.items[] | select(.metadata.name | test("gatekeeper"; "i")) | .metadata.name' | head -5)
  valweb=$(kjson get validatingwebhookconfigurations | jq -r '.items[] | select(.metadata.name | test("gatekeeper"; "i")) | .metadata.name' | head -5)

  if [[ -z "$mutweb" && -z "$valweb" ]]; then
    warn "No Gatekeeper webhook configurations found"
  else
    [[ -n "$mutweb" ]] && ok "MutatingWebhookConfigurations: $mutweb"
    [[ -n "$valweb" ]] && ok "ValidatingWebhookConfigurations: $valweb"
  fi

  # Service reachability
  local svc
  svc=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E 'webhook|gatekeeper' | awk '{print $1}' | head -3)
  if [[ -n "$svc" ]]; then
    note "Webhook services:"
    echo "$svc" | sed 's/^/      /'
  fi
}

# ---------- 7. Exempted namespaces ----------
section_exempt() {
  sect "7. Exempted namespaces summary"
  local json; json=$(kjson get constraints -A)
  if [[ -z "$json" ]]; then
    return
  fi
  echo "$json" | jq -r '
    [ .items[] | (.spec.match.excludedNamespaces // [])[] ] | unique
    | .[] | "    - " + .
  ' | sort -u | head -30

  local cnt
  cnt=$(echo "$json" | jq '[.items[] | (.spec.match.excludedNamespaces // []) | length] | add')
  echo -e "  Total exemptions across all constraints: ${BOLD}${cnt:-0}${RESET}"
}

# ---------- main ----------
ctx_init
section_cluster_summary
section_templates
section_constraints
section_violations
section_audit_events
section_webhook
section_exempt

echo -e "\n${GREEN}${BOLD}✔ Report complete.${RESET}"

```

