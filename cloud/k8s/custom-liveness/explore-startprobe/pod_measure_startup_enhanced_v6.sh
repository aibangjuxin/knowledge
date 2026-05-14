#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Pod Startup Time Measurement Tool v6
# Enhanced version with live polling, testing, and TCP probe support
############################################

readonly GREEN=$'\033[0;32m'
readonly BLUE=$'\033[0;34m'
readonly YELLOW=$'\033[1;33m'
readonly RED=$'\033[0;31m'
readonly CYAN=$'\033[0;36m'
readonly MAGENTA=$'\033[0;35m'
readonly GRAY=$'\033[0;90m'
readonly NC=$'\033[0m'

############################################
# Global Defaults
############################################
readonly DEFAULT_MAX_PROBES=180
readonly DEFAULT_PROBE_INTERVAL=2
readonly DEFAULT_TIMEOUT=5
readonly RETRY_COUNT=3
readonly LOG_FILE="pod_startup_analysis_$(date +%Y%m%d_%H%M%S).log"

############################################
# Configuration (CLI can override)
############################################
MAX_PROBES=${DEFAULT_MAX_PROBES}
PROBE_INTERVAL=${DEFAULT_PROBE_INTERVAL}
TIMEOUT=${DEFAULT_TIMEOUT}
POLL_FOR_READY=false
EXPORT_FORMAT=""
EXPORT_FILE=""
SIMULATE_PROBES=false
VERBOSE=false
LIVE_TEST=false
CUSTOM_PORT=""
CUSTOM_PATH=""

# Result variables (initialized)
LIVE_TEST_RESULT=""
LIVE_TEST_CODE=""
LIVE_TEST_TIME=""
STARTUP_TIME_SECONDS=0
STARTUP_TIME_PRECISE="0"
CONTAINER_START=""
RAW_START=""
RAW_READY=""
PROBE_TYPE=""
PROBE_KIND=""
PROBE_PATH=""
PORT=""
SCHEME=""
PROBE_URL=""
CONTAINER_STARTED=false
CONTAINER_READY=false
POD_JSON=""
POD_STATUS=""
CONTAINER_NAME=""
IMAGE=""
NODE=""
POD_START=""
MAX_TIME=""

############################################
# Command Resolver (PATH-independent, cross-platform)
############################################
resolve_command() {
    local name="$1"; shift
    local path

    for path in "$@"; do
        if [[ -x "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done

    echo -e "${RED}ERROR:${NC} Required command not found: $name" >&2
    echo "Searched paths: $*" >&2
    exit 127
}

# Resolve required commands
CAT_CMD=$(resolve_command cat /bin/cat /usr/bin/cat)
JQ_CMD=$(resolve_command jq /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq)
AWK_CMD=$(resolve_command awk /usr/bin/awk /bin/awk)
SLEEP_CMD=$(resolve_command sleep /bin/sleep /usr/bin/sleep)
KUBECTL_CMD=$(resolve_command kubectl /opt/homebrew/bin/kubectl /usr/local/bin/kubectl /usr/bin/kubectl)
CURL_CMD=$(resolve_command curl /usr/bin/curl /opt/homebrew/bin/curl)
NC_CMD=$(resolve_command nc /usr/bin/nc /bin/nc)

# Date command detection (macOS vs Linux gdate vs BSD date)
if command -v gdate >/dev/null 2>&1; then
    DATE_CMD=$(resolve_command gdate /opt/homebrew/bin/gdate /usr/local/bin/gdate)
    DATE_IS_GNU=1
elif date --version 2>&1 | grep -q GNU; then
    DATE_CMD=$(resolve_command date /usr/bin/date /bin/date)
    DATE_IS_GNU=1
else
    DATE_CMD=$(resolve_command date /bin/date /usr/bin/date)
    DATE_IS_GNU=0
fi

# High precision timing command
if command -v gdate >/dev/null 2>&1; then
    TIME_CMD="$DATE_CMD"
    TIME_IS_GNU=1
elif "$DATE_CMD" -d '@0' +%s.%N 2>/dev/null | grep -q '\.'; then
    TIME_CMD="$DATE_CMD"
    TIME_IS_GNU=1
else
    TIME_CMD="$DATE_CMD"
    TIME_IS_GNU=0
fi

############################################
# Utility Functions
############################################
die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    log_message "ERROR: $*"
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $*" >&2
    log_message "WARNING: $*"
}

info() {
    echo -e "${CYAN}INFO:${NC} $*"
    log_message "INFO: $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
    log_message "SUCCESS: $*"
}

section() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_message "SECTION: $1"
}

tiny() {
    echo -e "${GRAY}$*${NC}"
    log_message "TINY: $*"
}

log_message() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(get_timestamp_precise)] $1" >> "$LOG_FILE"
    fi
}

############################################
# Timing Functions
############################################
get_timestamp_precise() {
    if [[ "$TIME_IS_GNU" -eq 1 ]]; then
        "$TIME_CMD" -u +%Y-%m-%dT%H:%M:%S.%N 2>/dev/null || "$TIME_CMD" -u +%Y-%m-%dT%H:%M:%S
    else
        "$TIME_CMD" -u +%Y-%m-%dT%H:%M:%S
    fi
}

get_epoch_precise() {
    if [[ "$TIME_IS_GNU" -eq 1 ]]; then
        "$TIME_CMD" -u +%s.%N 2>/dev/null || "$TIME_CMD" -u +%s
    else
        "$TIME_CMD" -u +%s
    fi
}

iso_to_epoch() {
    local timestamp="$1"

    if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
        die "Invalid timestamp: $timestamp"
    fi

    if [[ "$DATE_IS_GNU" -eq 1 ]]; then
        "$DATE_CMD" -d "$timestamp" +%s 2>/dev/null || die "Failed to parse timestamp: $timestamp"
    else
        # macOS BSD date - try multiple formats
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" 2>/dev/null || \
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%Z}" "+%s" 2>/dev/null || \
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%S.%NZ" "$timestamp" "+%s" 2>/dev/null || \
        die "Failed to parse timestamp: $timestamp"
    fi
}

iso_to_epoch_precise() {
    local timestamp="$1"

    if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
        echo "0"
        return
    fi

    # Extract seconds and nanoseconds/milliseconds if available
    if [[ "$timestamp" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?$ ]]; then
        local base="${BASH_REMATCH[1]}"
        local frac="${BASH_REMATCH[2]:-}"
        local tz="${BASH_REMATCH[3]:-Z}"

        local sec_epoch
        sec_epoch=$(iso_to_epoch "${base}${tz}")

        if [[ -n "$frac" && "$frac" != "." ]]; then
            # Remove leading dot
            frac="${frac#.}"
            # Convert to decimal fraction
            local len=${#frac}
            local divisor=$((10 ** len))
            echo "scale=9; $sec_epoch + $frac / $divisor" | bc 2>/dev/null || echo "$sec_epoch"
        else
            echo "$sec_epoch"
        fi
    else
        iso_to_epoch "$timestamp"
    fi
}

############################################
# JSON Utilities
############################################
json_get() {
    local json="$1"
    local path="$2"
    local default="${3:-null}"

    echo "$json" | "$JQ_CMD" -r "$path // \"$default\"" 2>/dev/null || echo "$default"
}

json_exists() {
    local json="$1"
    local path="$2"

    "$JQ_CMD" -e "$path" <<<"$json" >/dev/null 2>&1
}

validate_json_field() {
    local value="$1"
    local field_name="$2"

    if [[ -z "$value" || "$value" == "null" ]]; then
        die "Failed to extract required field: $field_name"
    fi
}

############################################
# Argument Parsing
############################################
usage() {
    cat <<EOF
${BLUE}Usage:${NC} $0 -n <namespace> [options] <pod-name>

${BLUE}Options:${NC}
  -n, --namespace    Kubernetes namespace (required)
  -c, --container    Container index for multi-container pods (default: 0)
  -p, --poll         Poll for pod readiness (wait until pod becomes Ready)
  --max-probes       Max polling attempts when using -p (default: ${DEFAULT_MAX_PROBES})
  --probe-interval   Polling interval in seconds (default: ${DEFAULT_PROBE_INTERVAL})
  --timeout          HTTP request timeout for live testing (default: ${DEFAULT_TIMEOUT}s)
  --simulate         Simulate probe checks at actual probe endpoints
  --live-test        Perform live HTTP/TCP tests against probe endpoints
  --port             Override probe port for live testing
  --path             Override probe path for live testing (HTTP only)
  --export-json      Export results to JSON file
  --export-csv       Export results to CSV file
  --export           Export to both JSON and CSV (auto-generated names)
  -v, --verbose      Enable verbose output
  -h, --help         Show this help message

${BLUE}Examples:${NC}
  # Basic usage
  $0 -n default my-app-pod

  # Poll for readiness and measure
  $0 -n production -p my-app-pod

  # Multi-container pod with live testing
  $0 -n staging -c 1 --live-test my-app-pod

  # Export results
  $0 -n default --export my-app-pod

  # Custom probe settings
  $0 -n default --simulate --port 8080 --path /health my-app-pod

${BLUE}Features in v6:${NC}
  ✓ Live polling for pod readiness
  ✓ Millisecond-precision timing
  ✓ Live HTTP/TCP probe testing
  ✓ Export to JSON/CSV
  ✓ Verbose logging with timestamps
  ✓ Smart probe endpoint detection
  ✓ Multi-container support
  ✓ Cross-platform (Linux/macOS)

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -c|--container)
                CONTAINER_INDEX="$2"
                shift 2
                ;;
            -p|--poll)
                POLL_FOR_READY=true
                shift
                ;;
            --max-probes)
                MAX_PROBES="$2"
                shift 2
                ;;
            --probe-interval)
                PROBE_INTERVAL="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --simulate)
                SIMULATE_PROBES=true
                shift
                ;;
            --live-test)
                LIVE_TEST=true
                shift
                ;;
            --port)
                CUSTOM_PORT="$2"
                shift 2
                ;;
            --path)
                CUSTOM_PATH="$2"
                shift 2
                ;;
            --export-json)
                EXPORT_FORMAT="json"
                EXPORT_FILE="${2:-${LOG_FILE%.log}.json}"
                shift 2
                ;;
            --export-csv)
                EXPORT_FORMAT="csv"
                EXPORT_FILE="${2:-${LOG_FILE%.log}.csv}"
                shift 2
                ;;
            --export)
                EXPORT_FORMAT="both"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                die "Unknown option: $1. Use -h for help."
                ;;
            *)
                POD_NAME="$1"
                shift
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
        usage
    fi

    # Set defaults for optional parameters
    CONTAINER_INDEX=${CONTAINER_INDEX:-0}

    # Validate numeric parameters
    if ! [[ "$CONTAINER_INDEX" =~ ^[0-9]+$ ]]; then
        die "Container index must be a non-negative integer, got: $CONTAINER_INDEX"
    fi
    if ! [[ "$MAX_PROBES" =~ ^[0-9]+$ ]]; then
        die "Max probes must be a positive integer"
    fi
    if ! [[ "$PROBE_INTERVAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        die "Probe interval must be a number"
    fi
    if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
        die "Timeout must be a positive integer"
    fi

    # Set default export filename if needed
    if [[ "$EXPORT_FORMAT" == "both" ]]; then
        EXPORT_FILE=""
    fi
}

############################################
# Output Header
############################################
print_header() {
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo -e "║  ${CYAN}Pod Startup Time Measurement & Probe Analysis Tool${NC}  ${MAGENTA}v6${NC}             ║"
    echo "╠═══════════════════════════════════════════════════════════════════════╣"
    printf "║  ${YELLOW}Pod:${NC} %-52s ║\n" "$POD_NAME"
    printf "║  ${YELLOW}Namespace:${NC} %-44s ║\n" "$NAMESPACE"
    printf "║  ${YELLOW}Container Index:${NC} %-38s ║\n" "$CONTAINER_INDEX"
    [[ -n "$EXPORT_FILE" ]] && printf "║  ${YELLOW}Export File:${NC} %-43s ║\n" "$EXPORT_FILE"
    [[ "$POLL_FOR_READY" == true ]] && printf "║  ${YELLOW}Mode:${NC} ${GREEN}Polling Enabled${NC} %-31s ║\n" ""
    [[ "$LIVE_TEST" == true || "$SIMULATE_PROBES" == true ]] && printf "║  ${YELLOW}Testing:${NC} ${MAGENTA}Active${NC} %-40s ║\n" ""
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo

    if [[ "$VERBOSE" == true ]]; then
        info "Verbose mode enabled - detailed logs will be written to: $LOG_FILE"
    fi
}

############################################
# Step 1: Get Pod Basic Info
############################################
step1_get_pod_basic_info() {
    section "📋 Step 1/7: Get Pod Basic Information"

    # Fetch pod JSON
    if ! POD_JSON=$( "$KUBECTL_CMD" get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>&1 ); then
        die "Failed to get pod information:\n$POD_JSON"
    fi

    if [[ -z "$POD_JSON" ]]; then
        die "Pod not found: $POD_NAME in namespace: $NAMESPACE"
    fi

    # Validate container index
    local container_count
    container_count=$(json_get "$POD_JSON" '.spec.containers | length' "0")
    if [[ "$CONTAINER_INDEX" -ge "$container_count" ]]; then
        die "Container index $CONTAINER_INDEX out of range (pod has $container_count container(s))"
    fi

    # Extract information
    POD_STATUS=$(json_get "$POD_JSON" '.status.phase' 'Unknown')
    CONTAINER_NAME=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].name" 'unknown')
    IMAGE=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].image" 'unknown')
    NODE=$(json_get "$POD_JSON" '.spec.nodeName' 'unknown')
    POD_START=$(json_get "$POD_JSON" '.status.startTime' 'null')

    echo -e "   ${CYAN}Pod Status:${NC} $POD_STATUS"
    echo -e "   ${CYAN}Container Name:${NC} $CONTAINER_NAME"
    echo -e "   ${CYAN}Container Image:${NC} $IMAGE"
    echo -e "   ${CYAN}Node:${NC} $NODE"
    echo -e "   ${CYAN}Pod Start Time:${NC} $POD_START"

    if [[ "$VERBOSE" == true ]]; then
        tiny "Pod JSON keys extracted successfully"
    fi
}

############################################
# Step 2: Check Container Status
############################################
step2_check_container_status() {
    section "🔍 Step 2/7: Check Container Status"

    local container_ready=false
    local container_started=false

    # Check if container is ready
    if json_exists "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].ready"; then
        local ready
        ready=$(json_get "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].ready" "false")
        if [[ "$ready" == "true" ]]; then
            container_ready=true
            echo -e "   ${GREEN}✓${NC} Container is READY"
        else
            echo -e "   ${RED}✗${NC} Container is NOT ready"
        fi
    fi

    # Check if container has started
    if json_exists "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].state.running.startedAt"; then
        CONTAINER_START=$(json_get "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].state.running.startedAt" "null")
        echo -e "   ${CYAN}Container Started At:${NC} $CONTAINER_START"
        container_started=true
    else
        warn "Container has not started yet"
        if [[ "$container_ready" == true ]]; then
            info "Container is ready but we don't have startedAt timestamp"
            info "Using pod conditions instead"
        fi
    fi

    # Show all container statuses if verbose
    if [[ "$VERBOSE" == true ]]; then
        echo
        tiny "All container statuses:"
        "$JQ_CMD" -r ".status.containerStatuses[] | \"  - \\(.name): ready=\\(.ready), started=\\(.state?.running != null)\"" <<< "$POD_JSON" 2>/dev/null || true
    fi

    CONTAINER_STARTED=$container_started
    CONTAINER_READY=$container_ready

    # If container not started and polling not enabled, we can't proceed
    if [[ "$container_started" == false && "$POLL_FOR_READY" == false ]]; then
        warn "Container hasn't started yet. Consider using '--poll' option"
    fi
}

############################################
# Polling Functions
############################################
poll_for_ready() {
    section "⏱️  Polling for Pod Readiness (max ${MAX_PROBES} attempts @ ${PROBE_INTERVAL}s intervals)"

    local attempt=0
    local pod_ready=false
    local container_started=false
    local start_time
    start_time=$(get_epoch_precise)

    info "Starting polling at $(get_timestamp_precise)"

    while [[ $attempt -lt $MAX_PROBES ]]; do
        attempt=$((attempt + 1))

        # Fetch updated pod status
        if ! POD_JSON=$( "$KUBECTL_CMD" get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>&1 ); then
            warn "Failed to fetch pod status (attempt $attempt)"
            sleep "$PROBE_INTERVAL"
            continue
        fi

        # Check container status
        local container_ready=$(json_get "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].ready" "false")
        local container_state=$(json_get "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].state.running.startedAt" "null")
        local pod_phase=$(json_get "$POD_JSON" ".status.phase" "Unknown")

        # Banner
        printf "   [Attempt %d/%d] Phase: %s | Ready: %s | Time: %ds\r" \
            "$attempt" "$MAX_PROBES" "$pod_phase" "$container_ready" $((attempt * PROBE_INTERVAL))

        # Check if container started
        if [[ "$container_state" != "null" && "$container_started" == false ]]; then
            CONTAINER_START="$container_state"
            container_started=true
            echo
            echo
            success "Container started at: $CONTAINER_START"
        fi

        # Check if ready
        if [[ "$container_ready" == "true" ]]; then
            pod_ready=true
            break
        fi

        # Sleep before next attempt
        sleep "$PROBE_INTERVAL"
    done

    echo
    echo

    if [[ "$pod_ready" == true ]]; then
        success "Pod became READY after $((attempt * PROBE_INTERVAL)) seconds"

        # Get final Ready time
        READY_TIME=$(json_get "$POD_JSON" '.status.conditions[] | select(.type=="Ready" and .status=="True") | .lastTransitionTime' 'null')

        if [[ "$READY_TIME" != "null" ]]; then
            info "Ready transition at: $READY_TIME"
        fi
    else
        die "Pod did not become Ready within ${MAX_PROBES} attempts ($((MAX_PROBES * PROBE_INTERVAL))s max)"
    fi
}

############################################
# Step 3: Analyze Probe Configuration
############################################
step3_analyze_probe_configuration() {
    section "🔍 Step 3/7: Analyze Probe Configuration"

    local probe_found=0
    declare -A probe_details

    for probe in startupProbe readinessProbe livenessProbe; do
        if json_exists "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe"; then
            echo -e "   ${GREEN}✓${NC} ${probe}: Configured"

            local initial_delay period_seconds failure_threshold timeout_seconds

            initial_delay=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.initialDelaySeconds" "0")
            period_seconds=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.periodSeconds" "10")
            failure_threshold=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.failureThreshold" "3")
            timeout_seconds=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.timeoutSeconds" "1")

            echo "     - initialDelaySeconds: ${initial_delay}s"
            echo "     - periodSeconds: ${period_seconds}s"
            echo "     - failureThreshold: ${failure_threshold}"
            echo "     - timeoutSeconds: ${timeout_seconds}s"

            if [[ "$probe" == "startupProbe" ]]; then
                local max_time=$((period_seconds * failure_threshold))
                echo -e "     ${YELLOW}→${NC} Maximum allowed startup time: ${max_time}s"
                probe_details["startup_max_time"]="$max_time"
                MAX_TIME="$max_time"
            fi

            probe_details["${probe}_period"]="$period_seconds"
            probe_details["${probe}_threshold"]="$failure_threshold"

            probe_found=1
        else
            echo -e "   ${RED}✗${NC} ${probe}: Not configured"
        fi
    done

    if [[ "$probe_found" -eq 0 ]]; then
        warn "No probes configured for this container"
    fi

    PROBE_FOUND=$probe_found
}

############################################
# Step 4: Extract Probe Endpoint
############################################
step4_extract_probe_endpoint() {
    section "🔍 Step 4/7: Extract Probe Detection Parameters"

    # Try to find the most appropriate probe (startup -> readiness -> liveness)
    local probe_type=""
    local probe_kind=""
    for pt in startupProbe readinessProbe livenessProbe; do
        if json_exists "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$pt.httpGet"; then
            probe_type="$pt"
            probe_kind="http"
            break
        elif json_exists "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$pt.tcpSocket"; then
            probe_type="$pt"
            probe_kind="tcp"
            break
        elif json_exists "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$pt.exec"; then
            probe_type="$pt"
            probe_kind="exec"
            break
        fi
    done

    if [[ -z "$probe_type" ]]; then
        warn "No probe found, using defaults or custom values"
        PROBE_PATH="${CUSTOM_PATH:-/}"
        PORT="${CUSTOM_PORT:-80}"
        SCHEME="HTTP"
        PROBE_TYPE="None"
        PROBE_KIND="http"  # Default to http
    else
        PROBE_TYPE="$probe_type"
        PROBE_KIND="$probe_kind"

        if [[ "$probe_kind" == "http" ]]; then
            # Use custom values if provided, otherwise extract from probe
            if [[ -n "$CUSTOM_PATH" ]]; then
                PROBE_PATH="$CUSTOM_PATH"
            else
                PROBE_PATH=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.path" "/")
            fi

            if [[ -n "$CUSTOM_PORT" ]]; then
                PORT="$CUSTOM_PORT"
            else
                PORT=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.port" "80")
            fi

            SCHEME=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.scheme" "HTTP")

            # Try to extract host header if present
            HOST_HEADER=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.httpHeaders[] | select(.name==\"Host\") | .value" "")
        elif [[ "$probe_kind" == "tcp" ]]; then
            if [[ -n "$CUSTOM_PORT" ]]; then
                PORT="$CUSTOM_PORT"
            else
                PORT=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.tcpSocket.port" "80")
            fi
            PROBE_PATH=""
            SCHEME=""
        elif [[ "$probe_kind" == "exec" ]]; then
            # For exec, we can't easily test live, but extract command
            EXEC_COMMAND=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.exec.command | join(\" \")" "")
            PORT=""
            PROBE_PATH=""
            SCHEME=""
        fi
    fi

    echo -e "   ${CYAN}Detection Endpoint Information:${NC}"
    echo "   - Source Probe Type: ${PROBE_TYPE}"
    echo "   - Probe Kind: $PROBE_KIND"
    if [[ "$probe_kind" == "http" ]]; then
        echo "   - Scheme: $SCHEME"
        echo "   - Port: $PORT"
        echo "   - Path: $PROBE_PATH"
        [[ -n "$HOST_HEADER" ]] && echo "   - Host Header: $HOST_HEADER"
    elif [[ "$probe_kind" == "tcp" ]]; then
        echo "   - Port: $PORT"
    elif [[ "$probe_kind" == "exec" ]]; then
        echo "   - Command: $EXEC_COMMAND"
    fi

    # Build full URL or description
    if [[ "$probe_kind" == "http" ]]; then
        if [[ "$SCHEME" == "HTTP" || "$SCHEME" == "http" ]]; then
            FULL_URL="http://localhost:$PORT$PROBE_PATH"
        else
            FULL_URL="https://localhost:$PORT$PROBE_PATH"
        fi
        echo -e "   ${YELLOW}→${NC} Full URL: $FULL_URL"
        PROBE_URL="$FULL_URL"
    elif [[ "$probe_kind" == "tcp" ]]; then
        echo -e "   ${YELLOW}→${NC} TCP Port: $PORT"
        PROBE_URL="tcp://localhost:$PORT"
    elif [[ "$probe_kind" == "exec" ]]; then
        echo -e "   ${YELLOW}→${NC} Exec Command: $EXEC_COMMAND"
        PROBE_URL="$EXEC_COMMAND"
    fi
}

############################################
# Step 5: Live Probe Testing (Enhanced with TCP)
############################################
step5_live_probe_testing() {
    section "🧪 Step 5/7: Live Probe Testing"

    if [[ "$SIMULATE_PROBES" != true && "$LIVE_TEST" != true ]]; then
        info "Skipping live probe testing (use --simulate or --live-test to enable)"
        return
    fi

    if [[ "$PROBE_KIND" == "exec" ]]; then
        warn "Live testing not supported for exec probes"
        return
    fi

    # Use port-forward to test the probe endpoint
    local port_fwd_pid=""

    # Start port forwarding in background
    info "Setting up port forwarding to container..."

    # Find the actual container port to forward
    local container_port
    container_port=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].ports[0].containerPort" "$PORT")

    if [[ "$container_port" != "$PORT" ]]; then
        info "Note: Probe port ($PORT) differs from container port ($container_port)"
    fi

    # Select port to forward
    local target_port="${CUSTOM_PORT:-$container_port}"

    # Find available local port
    local local_port=0
    for p in $(seq 10000 10100); do
        if ! lsof -Pi ":$p" -sTCP:LISTEN -t >/dev/null 2>&1; then
            local_port="$p"
            break
        fi
    done

    if [[ "$local_port" -eq 0 ]]; then
        warn "Could not find available local port, skipping live testing"
        return
    fi

    if [[ "$SIMULATE_PROBES" == true ]]; then
        echo -e "   ${MAGENTA}SIMULATION MODE${NC}"
        echo "   Would test: $PROBE_URL"
        echo "   Using port: $target_port"
        echo "   With timeout: ${TIMEOUT}s"
        echo
        echo "   Simulated probe results:"
        echo "   - TCP connection: ${GREEN}✓ Success${NC}"
        if [[ "$PROBE_KIND" == "http" ]]; then
            echo "   - HTTP response: ${GREEN}200 OK${NC}"
        fi
        echo "   - Response time: ${YELLOW}0-5ms${NC}"
        return
    fi

    info "Forwarding pod port $target_port -> localhost:$local_port"

    # Start port-forward
    "$KUBECTL_CMD" port-forward "pod/$POD_NAME" "$local_port:$target_port" -n "$NAMESPACE" > /dev/null 2>&1 &
    port_fwd_pid=$!

    # Give it a moment to establish
    sleep 1

    # Check if port-forward is working
    if ! lsof -Pi ":$local_port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        warn "Port forwarding failed, skipping live test"
        kill "$port_fwd_pid" 2>/dev/null || true
        return
    fi

    # Perform actual test
    info "Testing endpoint: $PROBE_URL"

    local test_result=""
    local test_code=0
    local test_time=0

    # Try multiple attempts
    for attempt in $(seq 1 $RETRY_COUNT); do
        echo "   Attempt $attempt/$RETRY_COUNT..."

        local start_t
        start_t=$(get_epoch_precise)

        if [[ "$PROBE_KIND" == "http" ]]; then
            if response=$(curl -s -w "\n%{http_code} %{time_total}" \
                --connect-timeout "$TIMEOUT" \
                --max-time "$TIMEOUT" \
                -H "${HOST_HEADER:+Host: $HOST_HEADER}" \
                "http://localhost:$local_port$PROBE_PATH" 2>&1); then

                local end_t
                end_t=$(get_epoch_precise)

                # Parse response
                local http_code
                local response_body
                local total_time

                http_code=$(echo "$response" | tail -1 | awk '{print $1}')
                total_time=$(echo "$response" | tail -1 | awk '{print $2}')
                response_body=$(echo "$response" | head -1)

                test_code="$http_code"
                test_time=$(echo "scale=3; $total_time * 1000" | bc 2>/dev/null || echo "$total_time")

                if [[ "$http_code" =~ ^(200|204|301|302)$ ]]; then
                    echo -e "   ${GREEN}✓${NC} HTTP $http_code | ${test_time}ms"
                    test_result="SUCCESS"

                    if [[ "$VERBOSE" == true && -n "$response_body" ]]; then
                        echo "   Response (first 100 chars): ${response_body:0:100}..."
                    fi
                    break
                else
                    echo -e "   ${RED}✗${NC} HTTP $http_code | ${test_time}ms"
                    test_result="FAILED"
                fi
            else
                echo -e "   ${RED}✗${NC} Connection failed"
                test_result="ERROR"
            fi
        elif [[ "$PROBE_KIND" == "tcp" ]]; then
            if "$NC_CMD" -z -w "$TIMEOUT" localhost "$local_port" 2>/dev/null; then
                local end_t
                end_t=$(get_epoch_precise)
                test_time=$(echo "scale=3; ($end_t - $start_t) * 1000" | bc 2>/dev/null || echo "0")
                echo -e "   ${GREEN}✓${NC} TCP Connection Successful | ${test_time}ms"
                test_result="SUCCESS"
                test_code="TCP_OK"
                break
            else
                echo -e "   ${RED}✗${NC} TCP Connection Failed"
                test_result="FAILED"
                test_code="TCP_FAIL"
            fi
        fi

        [[ "$attempt" -lt "$RETRY_COUNT" ]] && sleep 1
    done

    # Cleanup
    kill "$port_fwd_pid" 2>/dev/null
    wait "$port_fwd_pid" 2>/dev/null || true

    # Store results
    LIVE_TEST_RESULT="$test_result"
    LIVE_TEST_CODE="$test_code"
    LIVE_TEST_TIME="$test_time"

    echo
    echo -e "   ${CYAN}Live Test Summary:${NC}"
    echo "   - Result: $test_result"
    echo "   - Code: $test_code"
    echo "   - Response Time: ${test_time}ms"
}

############################################
# Step 6: Measure Startup Time
############################################
step6_measure_startup_time() {
    section "⏱️  Step 6/7: Measure Actual Startup Time"

    # Get Ready status transition time
    READY_TIME=$(json_get "$POD_JSON" \
        '.status.conditions[] | select(.type=="Ready" and .status=="True") | .lastTransitionTime' \
        'null')

    if [[ -n "$READY_TIME" && "$READY_TIME" != "null" ]]; then
        success "Pod is in Ready status"
        echo -e "   ${CYAN}Ready Time:${NC} $READY_TIME"

        # Get precise epoch times
        if [[ -n "$CONTAINER_START" && "$CONTAINER_START" != "null" ]]; then
            CONTAINER_START_EPOCH=$(iso_to_epoch_precise "$CONTAINER_START")
            READY_TIME_EPOCH=$(iso_to_epoch_precise "$READY_TIME")

            # Calculate startup time with precision
            STARTUP_TIME_PRECISE=$(echo "scale=3; $READY_TIME_EPOCH - $CONTAINER_START_EPOCH" | bc 2>/dev/null || echo "0")

            echo -e "   ${CYAN}Precise Startup Time:${NC} ${STARTUP_TIME_PRECISE}s"

            # Store raw times
            RAW_START="$CONTAINER_START"
            RAW_READY="$READY_TIME"
            STARTUP_TIME_SECONDS=$(echo "$STARTUP_TIME_PRECISE" | cut -d'.' -f1)
        else
            warn "Container start time not available, cannot calculate precise startup time"
            STARTUP_TIME_SECONDS=0
            STARTUP_TIME_PRECISE="0"
        fi
    else
        if [[ "$POLL_FOR_READY" == true ]]; then
            warn "Pod still not ready after polling - using latest status"
            info "Current conditions:"
            "$JQ_CMD" -r '.status.conditions[] | "   - \(.type): \(.status) (\(.reason // "N/A"))"' <<< "$POD_JSON" 2>/dev/null || true
            STARTUP_TIME_SECONDS=0
            STARTUP_TIME_PRECISE="0"
        else
            die "Pod is not in Ready status. Use --poll to wait for readiness."
        fi
    fi
}

############################################
# Step 7: Analysis & Recommendations
############################################
step7_analyze_and_recommend() {
    section "📊 Step 7/7: Analysis & Recommendations"

    if [[ "$STARTUP_TIME_SECONDS" -eq 0 ]]; then
        warn "Cannot perform detailed analysis without startup time"
        return
    fi

    echo -e "   ${GREEN}✓${NC} Actual Application Startup Time: ${STARTUP_TIME_PRECISE}s"
    echo -e "   ${CYAN}📝 Measurement Source:${NC} Kubernetes Ready Status + Precise Timing"
    echo

    # Timeline visualization
    echo -e "   ${CYAN}⏱️  Startup Timeline:${NC}"
    echo "   ┌─────────────────────────────────────────────────────────────────┐"
    echo "   │ 0s                                                 ${STARTUP_TIME_SECONDS}s │"
    echo "   │ ├───────────────────────────────────────────────────────────────┤"
    echo "   │ Container Start                                       Application Ready │"
    echo "   └─────────────────────────────────────────────────────────────────┘"
    echo

    # Configuration comparison
    if [[ -n "${MAX_TIME:-}" ]]; then
        local buffer=$((MAX_TIME - STARTUP_TIME_SECONDS))
        echo -e "   ${CYAN}📊 Configuration Analysis:${NC}"
        echo "   - Maximum Allowed Startup Time: ${MAX_TIME}s"
        echo "   - Actual Startup Time: ${STARTUP_TIME_PRECISE}s"

        if [[ "$buffer" -gt 10 ]]; then
            echo -e "   ${GREEN}✓${NC} Excellent buffer: ${buffer}s (over-Provisioned but safe)"
        elif [[ "$buffer" -gt 0 ]]; then
            echo -e "   ${GREEN}✓${NC} Good buffer: ${buffer}s"
        elif [[ "$buffer" -eq 0 ]]; then
            echo -e "   ${YELLOW}⚠${NC} Tight configuration - at limit"
        else
            echo -e "   ${RED}✗${NC} Configuration too tight: exceeds by $((buffer * -1))s"
        fi
        echo
    fi

    # Performance assessment
    echo -e "   ${CYAN}🚀 Startup Performance Assessment:${NC}"
    if [[ "$STARTUP_TIME_SECONDS" -lt 5 ]]; then
        echo -e "   ${GREEN}Excellent${NC} - Instant startup (<5s), ideal for edge cases"
    elif [[ "$STARTUP_TIME_SECONDS" -lt 15 ]]; then
        echo -e "   ${GREEN}Very Good${NC} - Fast startup (5-15s), production-ready"
    elif [[ "$STARTUP_TIME_SECONDS" -lt 30 ]]; then
        echo -e "   ${GREEN}Good${NC} - Normal startup (15-30s), healthy"
    elif [[ "$STARTUP_TIME_SECONDS" -lt 60 ]]; then
        echo -e "   ${YELLOW}Moderate${NC} - Slow startup (30-60s), consider optimization"
    elif [[ "$STARTUP_TIME_SECONDS" -lt 120 ]]; then
        echo -e "   ${YELLOW}Slow${NC} - Long startup (60-120s), optimization recommended"
    else
        echo -e "   ${RED}Very Slow${NC} - Extreme startup (>120s), serious optimization needed"
    fi
    echo

    # Live test results
    if [[ -n "$LIVE_TEST_RESULT" ]]; then
        echo -e "   ${CYAN}🧪 Live Test Results:${NC}"
        echo "   - Test Result: $LIVE_TEST_RESULT"
        echo "   - Response Code: $LIVE_TEST_CODE"
        echo "   - Response Time: ${LIVE_TEST_TIME}ms"

        if [[ "$LIVE_TEST_RESULT" == "SUCCESS" ]]; then
            echo -e "   ${GREEN}✓${NC} Probe endpoint is responsive and healthy"
        else
            echo -e "   ${RED}✗${NC} Probe endpoint has issues - check application health"
        fi
        echo
    fi

    # Configuration recommendations
    section "📌 Configuration Recommendations"

    # Calculate recommended values based on actual startup time
    local rec_failure_threshold=$(( (STARTUP_TIME_SECONDS / 10) + 2 ))
    [[ "$rec_failure_threshold" -lt 3 ]] && rec_failure_threshold=3

    local rec_period=10
    local max_startup_time=$((rec_period * rec_failure_threshold))

    local ready_period=5
    local ready_threshold=3

    local live_delay=$((STARTUP_TIME_SECONDS + 5))
    local live_period=10
    local live_threshold=3

    echo -e "${GREEN}Approach 1: StartupProbe + ReadinessProbe (Recommended for most cases)${NC}"
    echo
    if [[ "$PROBE_KIND" == "http" ]]; then
        echo "startupProbe:"
        echo "  httpGet:"
        echo "    path: $PROBE_PATH"
        echo "    port: $PORT"
        echo "    scheme: $SCHEME"
        echo "  periodSeconds: $rec_period"
        echo "  failureThreshold: $rec_failure_threshold"
        echo "  # Allows up to ${max_startup_time}s for application startup"
        echo
        echo "readinessProbe:"
        echo "  httpGet:"
        echo "    path: $PROBE_PATH"
        echo "    port: $PORT"
        echo "    scheme: $SCHEME"
        echo "  periodSeconds: $ready_period"
        echo "  failureThreshold: $ready_threshold"
        echo "  # Fast detection for ready/not ready (15s window)"
        echo
        echo "livenessProbe:"
        echo "  httpGet:"
        echo "    path: $PROBE_PATH"
        echo "    port: $PORT"
        echo "    scheme: $SCHEME"
        echo "  initialDelaySeconds: $live_delay"
        echo "  periodSeconds: $live_period"
        echo "  failureThreshold: $live_threshold"
        echo "  # Start monitoring after application is stable"
        echo
    elif [[ "$PROBE_KIND" == "tcp" ]]; then
        echo "startupProbe:"
        echo "  tcpSocket:"
        echo "    port: $PORT"
        echo "  periodSeconds: $rec_period"
        echo "  failureThreshold: $rec_failure_threshold"
        echo "  # Allows up to ${max_startup_time}s for application startup"
        echo
        echo "readinessProbe:"
        echo "  tcpSocket:"
        echo "    port: $PORT"
        echo "  periodSeconds: $ready_period"
        echo "  failureThreshold: $ready_threshold"
        echo "  # Fast detection for ready/not ready (15s window)"
        echo
        echo "livenessProbe:"
        echo "  tcpSocket:"
        echo "    port: $PORT"
        echo "  initialDelaySeconds: $live_delay"
        echo "  periodSeconds: $live_period"
        echo "  failureThreshold: $live_threshold"
        echo "  # Start monitoring after application is stable"
        echo
    fi

    # Alternative for slow startups
    if [[ "$STARTUP_TIME_SECONDS" -ge 60 ]]; then
        echo -e "${YELLOW}Approach 2: Optimized for Slow Startup (>60s)${NC}"
        echo
        local slow_period=15
        local slow_failure=$(( (STARTUP_TIME_SECONDS / slow_period) + 2 ))

        echo "startupProbe:"
        if [[ "$PROBE_KIND" == "http" ]]; then
            echo "  httpGet:"
            echo "    path: $PROBE_PATH"
            echo "    port: $PORT"
            echo "    scheme: $SCHEME"
        elif [[ "$PROBE_KIND" == "tcp" ]]; then
            echo "  tcpSocket:"
            echo "    port: $PORT"
        fi
        echo "  periodSeconds: $slow_period"
        echo "  failureThreshold: $slow_failure"
        echo "  timeoutSeconds: 5"
        echo "  # Allows up to $((slow_period * slow_failure))s for slow startup"
        echo
    fi

    # For very fast startups
    if [[ "$STARTUP_TIME_SECONDS" -lt 10 ]]; then
        echo -e "${CYAN}Approach 3: Minimal Configuration (Fast Startup)${NC}"
        echo
        echo "# Can skip startupProbe entirely"
        echo "readinessProbe:"
        if [[ "$PROBE_KIND" == "http" ]]; then
            echo "  httpGet:"
            echo "    path: $PROBE_PATH"
            echo "    port: $PORT"
            echo "    scheme: $SCHEME"
        elif [[ "$PROBE_KIND" == "tcp" ]]; then
            echo "  tcpSocket:"
            echo "    port: $PORT"
        fi
        echo "  periodSeconds: 2"
        echo "  failureThreshold: 3"
        echo "  # 6s window - good for fast startups"
        echo
    fi

    echo -e "${GRAY}Note: For database-based apps, consider tcpSocket probes on port 5432/3306${NC}"
}

############################################
# Export Functions
############################################
export_results() {
    if [[ -z "$EXPORT_FORMAT" ]]; then
        return
    fi

    section "💾 Exporting Results"

    local base_name="${LOG_FILE%.log}"

    if [[ "$EXPORT_FORMAT" == "json" || "$EXPORT_FORMAT" == "both" ]]; then
        local json_file="${EXPORT_FILE:-${base_name}.json}"

        cat > "$json_file" <<EOF
{
  "timestamp": "$(get_timestamp_precise)",
  "pod": {
    "name": "$POD_NAME",
    "namespace": "$NAMESPACE",
    "containerIndex": $CONTAINER_INDEX,
    "containerName": "$CONTAINER_NAME",
    "image": "$IMAGE",
    "node": "$NODE"
  },
  "measurements": {
    "containerStart": "$RAW_START",
    "readyTime": "$RAW_READY",
    "startupTimeSeconds": $STARTUP_TIME_SECONDS,
    "startupTimePrecise": "$STARTUP_TIME_PRECISE"
  },
  "probes": {
    "type": "$PROBE_TYPE",
    "kind": "$PROBE_KIND",
    "scheme": "$SCHEME",
    "port": "$PORT",
    "path": "$PROBE_PATH",
    "fullUrl": "$PROBE_URL"
  },
EOF

        if [[ -n "$LIVE_TEST_RESULT" ]]; then
            cat >> "$json_file" <<EOF
  "liveTest": {
    "result": "$LIVE_TEST_RESULT",
    "httpCode": $LIVE_TEST_CODE,
    "responseTimeMs": $LIVE_TEST_TIME
  },
EOF
        fi

        # Add probe configuration if exists
        if json_exists "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].startupProbe"; then
            cat >> "$json_file" <<EOF
  "currentConfig": {
EOF
            for probe in startupProbe readinessProbe livenessProbe; do
                if json_exists "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe"; then
                    echo "    \"$probe\": {" >> "$json_file"
                    echo "      \"initialDelaySeconds\": $(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.initialDelaySeconds" 0)," >> "$json_file"
                    echo "      \"periodSeconds\": $(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.periodSeconds" 10)," >> "$json_file"
                    echo "      \"failureThreshold\": $(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.failureThreshold" 3)," >> "$json_file"
                    echo "      \"timeoutSeconds\": $(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.timeoutSeconds" 1)" >> "$json_file"
                    echo "    }," >> "$json_file"
                fi
            done
            sed -i '' '$ s/,$//' "$json_file" 2>/dev/null || sed -i '$ s/,$//' "$json_file"
            echo "  }" >> "$json_file"
        fi

        echo "}" >> "$json_file"

        success "JSON export saved to: $json_file"
    fi

    if [[ "$EXPORT_FORMAT" == "csv" || "$EXPORT_FORMAT" == "both" ]]; then
        local csv_file="${EXPORT_FILE:-${base_name}.csv}"

        # Write header if file doesn't exist or is empty
        if [[ ! -s "$csv_file" ]]; then
            echo "timestamp,pod(namespace),container,image,node,starttime,readytime,startup_time_s,probe_type,probe_kind,scheme,port,path" > "$csv_file"
        fi

        # Write data row
        echo "$(get_timestamp_precise),${POD_NAME}(${NAMESPACE}),${CONTAINER_NAME},${IMAGE},${NODE},${RAW_START},${RAW_READY},${STARTUP_TIME_SECONDS},${PROBE_TYPE},${PROBE_KIND},${SCHEME},${PORT},${PROBE_PATH}" >> "$csv_file"

        success "CSV export saved to: $csv_file"
    fi
}

############################################
# Main Execution
############################################
main() {
    parse_args "$@"
    print_header

    # Step 1: Basic info
    step1_get_pod_basic_info

    # Step 2: Container status
    step2_check_container_status

    # Poll if requested and not already ready
    if [[ "$POLL_FOR_READY" == true && "$CONTAINER_READY" != "true" ]]; then
        poll_for_ready
    fi

    # Step 3: Analyze probes
    step3_analyze_probe_configuration

    # Step 4: Extract endpoint
    step4_extract_probe_endpoint

    # Step 5: Live testing
    step5_live_probe_testing

    # Step 6: Measure startup
    step6_measure_startup_time

    # Step 7: Analysis and recommendations
    step7_analyze_and_recommend

    # Export results
    export_results

    echo
    success "Analysis completed successfully!"

    if [[ -f "$LOG_FILE" && "$VERBOSE" == true ]]; then
        echo "   Detailed log: $LOG_FILE"
    fi

    # Show export file locations if exported
    if [[ -n "$EXPORT_FORMAT" ]]; then
        echo "   Export files created in current directory"
    fi
}

# Execute main
main "$@"