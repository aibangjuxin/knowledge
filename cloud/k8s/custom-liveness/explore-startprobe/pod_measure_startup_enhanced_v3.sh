#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Color & Style
############################################
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# Command Resolver (PATH-independent)
# ============================================================================

require_cmd() {
    local name="$1"; shift
    local p

    for p in "$@"; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done

    printf 'ERROR: required command not found: %s\n' "$name" >&2
    exit 127
}

CAT_CMD=$(require_cmd cat /bin/cat /usr/bin/cat)
JQ_CMD=$(require_cmd jq /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq)
DATE_CMD=$(require_cmd date /opt/homebrew/bin/gdate /usr/bin/date)
AWK_CMD=$(require_cmd awk /usr/bin/awk /bin/awk)
SLEEP_CMD=$(require_cmd sleep /bin/sleep /usr/bin/sleep)
KUBECTL_CMD=$(require_cmd kubectl \
    /opt/homebrew/bin/kubectl \
    /usr/local/bin/kubectl \
    /usr/bin/kubectl)

############################################
# Global Defaults
############################################
MAX_PROBES=180
PROBE_INTERVAL=2

############################################
# Utils
############################################
die() {
  echo -e "${RED}ERROR:${NC} $*" >&2
  exit 1
}

section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

iso_to_epoch() {
  #"$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
  # testing at macOS with Homebrew the command /opt/homebrew/bin/gdate no -j option
  /bin/date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
}

############################################
# Argument Parsing
############################################
parse_args() {
  while getopts ":n:" opt; do
    case "$opt" in
    n) NAMESPACE="$OPTARG" ;;
    *) die "Usage: $0 -n <namespace> <pod-name>" ;;
    esac
  done
  shift $((OPTIND - 1))

  POD_NAME="${1:-}"
  if [[ -z "${NAMESPACE:-}" || -z "${POD_NAME:-}" ]]; then
    usage
  fi

}

############################################
# Header
############################################
print_header() {
  cat <<EOF
╔════════════════════════════════════════════════════════════════╗
║  Pod Startup Time Measurement and Probe Configuration Tool     ║
╠════════════════════════════════════════════════════════════════╣
║  Pod: ${POD_NAME}
║  Namespace: ${NAMESPACE}
╚════════════════════════════════════════════════════════════════╝
EOF
}

############################################
# Step 1: Pod Basic Info
############################################
step1_get_pod_basic_info() {
  section "📋 Step 1/6: Get Pod Basic Information"

  POD_JSON=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o json)

  POD_STATUS=$(jq -r '.status.phase' <<<"$POD_JSON")
  CONTAINER_NAME=$(jq -r '.spec.containers[0].name' <<<"$POD_JSON")
  IMAGE=$(jq -r '.spec.containers[0].image' <<<"$POD_JSON")
  NODE=$(jq -r '.spec.nodeName' <<<"$POD_JSON")
  POD_START=$(jq -r '.status.startTime' <<<"$POD_JSON")
  CONTAINER_START=$(jq -r '.status.containerStatuses[0].state.running.startedAt' <<<"$POD_JSON")

  echo "   Pod Status: $POD_STATUS"
  echo "   Container Name: $CONTAINER_NAME"
  echo "   Container Image: $IMAGE"
  echo "   Running Node: $NODE"
  echo "   Pod Creation Time: $POD_START"
  echo "   Container Start Time: $CONTAINER_START"
}

############################################
# Step 2: Probe Configuration
############################################
step2_analyze_probe_configuration() {
  section "📋 Step 2/6: Analyze Probe Configuration"
  echo "📌 Current Probe Configuration Overview:"
  echo

  for probe in startupProbe readinessProbe livenessProbe; do
    if jq -e ".spec.containers[0].$probe" <<<"$POD_JSON" >/dev/null; then
      echo "   ✓ $probe: Configured"
      jq -r ".spec.containers[0].$probe |
        \"     - initialDelaySeconds: \(.initialDelaySeconds // 0)s
         - periodSeconds: \(.periodSeconds // 10)s
         - failureThreshold: \(.failureThreshold // 3)\"" <<<"$POD_JSON"

      if [[ "$probe" == "startupProbe" ]]; then
        MAX_TIME=$(jq -r '
          (.spec.containers[0].startupProbe.periodSeconds // 10) *
          (.spec.containers[0].startupProbe.failureThreshold // 30)
        ' <<<"$POD_JSON")
        echo "     → Maximum allowed startup time: ${MAX_TIME}s"
      fi
    else
      echo "   ✗ $probe: Not Configured"
    fi
    echo
  done
}

############################################
# Step 3: Probe Endpoint
############################################
step3_extract_probe_endpoint() {
  section "📋 Step 3/6: Extract Probe Detection Parameters"

  PROBE_PATH=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.path // "/"' <<<"$POD_JSON")
  PORT=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.port // 80' <<<"$POD_JSON")
  SCHEME=$("$JQ_CMD" -r '.spec.containers[0].readinessProbe.httpGet.scheme // "HTTP"' <<<"$POD_JSON")

  echo "   Detection Endpoint Information:"
  echo "   - Scheme: $SCHEME"
  echo "   - Port: $PORT"
  echo "   - Path: $PROBE_PATH"
  echo "   → Full URL: $SCHEME://localhost:$PORT$PROBE_PATH"
}

############################################
# Step 4: Measure Startup Time
############################################
step4_measure_startup_time() {
  section "⏱️  Step 4/6: Measure Actual Startup Time"

  READY_TIME=$("$JQ_CMD" -r '
    .status.conditions[]
    | select(.type=="Ready" and .status=="True")
    | .lastTransitionTime
  ' <<<"$POD_JSON")

  if [[ -n "$READY_TIME" && "$READY_TIME" != "null" ]]; then
    echo "   ✓ Pod is already in Ready status"
    echo "   Ready Time: $READY_TIME"
  else
    die "Pod is not Ready yet (polling logic omitted for equivalence)"
  fi
}

############################################
# Step 5: Analysis
############################################
step5_analyze_startup_time() {
  section "📊 Step 5/6: Startup Time Analysis"

  START_EPOCH=$(iso_to_epoch "$CONTAINER_START")
  READY_EPOCH=$(iso_to_epoch "$READY_TIME")
  STARTUP_TIME=$((READY_EPOCH - START_EPOCH))

  echo "   ✅ Actual Application Startup Time: ${STARTUP_TIME} seconds"
  echo "   📍 Measurement Data Source: Kubernetes Ready Status"
  echo
  echo "   ⏱️  Startup Timeline:"
  cat <<EOF
   ┌─────────────────────────────────────────────────────────┐
   │ 0s                                          ${STARTUP_TIME}s │
   │ ├───────────────────────────────────────────┤           │
   │ Container Start                      Application Ready   │
   └─────────────────────────────────────────────────────────┘
EOF

  if [[ -n "${MAX_TIME:-}" ]]; then
    BUFFER=$((MAX_TIME - STARTUP_TIME))
    echo
    echo "   📊 Configuration Comparison Analysis:"
    echo "   Current Configuration Type: StartupProbe"
    echo "   Maximum Allowed Startup Time: ${MAX_TIME}s"
    echo "   Actual Startup Time: ${STARTUP_TIME}s"
    echo "   ✓ Configuration is reasonable, buffer time: ${BUFFER}s"
  fi
}

############################################
# Step 6: Recommendation
############################################
step6_print_recommendations() {
  section "💡 Step 6/6: Configuration Optimization Recommendations"

  cat <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║  Option 1: Using StartupProbe + ReadinessProbe (Recommended)  ║
╚════════════════════════════════════════════════════════════════╝

Advantages:
  • Separates startup and runtime phases
  • Prevents slow-start false failures
  • Faster runtime detection

Configuration Example:

  startupProbe:
    httpGet:
      path: /
      port: 80
      scheme: HTTP
    periodSeconds: 10
    failureThreshold: 2

  readinessProbe:
    httpGet:
      path: /
      port: 80
    periodSeconds: 5
    failureThreshold: 3
EOF
}

############################################
# Main
############################################
main() {
  require_cmd kubectl
  require_cmd jq

  parse_args "$@"
  print_header

  step1_get_pod_basic_info
  step2_analyze_probe_configuration
  step3_extract_probe_endpoint
  step4_measure_startup_time
  step5_analyze_startup_time
  step6_print_recommendations
}

main "$@"
