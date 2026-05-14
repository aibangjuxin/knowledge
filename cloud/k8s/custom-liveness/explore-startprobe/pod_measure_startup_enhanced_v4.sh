#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Color & Style
############################################
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

############################################
# Global Defaults
############################################
readonly MAX_PROBES=180
readonly PROBE_INTERVAL=2
NAMESPACE=""
POD_NAME=""
CONTAINER_INDEX=0

############################################
# Command Resolver (PATH-independent)
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
KUBECTL_CMD=$(resolve_command kubectl \
    /opt/homebrew/bin/kubectl \
    /usr/local/bin/kubectl \
    /usr/bin/kubectl)

# Date command detection (macOS vs Linux)
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

############################################
# Utility Functions
############################################
die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $*" >&2
}

info() {
    echo -e "${CYAN}INFO:${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

section() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ISO8601 timestamp to epoch conversion (cross-platform)
iso_to_epoch() {
    local timestamp="$1"
    
    if [[ "$DATE_IS_GNU" -eq 1 ]]; then
        "$DATE_CMD" -d "$timestamp" +%s 2>/dev/null || die "Failed to parse timestamp: $timestamp"
    else
        # macOS BSD date
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" 2>/dev/null || \
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%Z}" "+%s" 2>/dev/null || \
        die "Failed to parse timestamp: $timestamp"
    fi
}

# Safe JSON extraction with default value
json_get() {
    local json="$1"
    local path="$2"
    local default="${3:-null}"
    
    echo "$json" | "$JQ_CMD" -r "$path // \"$default\"" 2>/dev/null || echo "$default"
}

# Validate JSON field is not null/empty
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
    echo -e "${BLUE}Usage:${NC} $0 -n <namespace> [-c <container-index>] <pod-name>"
    echo
    echo -e "${BLUE}Options:${NC}"
    echo "  -n  Kubernetes namespace (required)"
    echo "  -c  Container index for multi-container pods (default: 0)"
    echo "  -h  Show this help message"
    echo
    echo -e "${BLUE}Example:${NC}"
    echo "  $0 -n default my-app-pod"
    echo "  $0 -n production -c 1 my-multi-container-pod"
    exit 0
}

parse_args() {
    while getopts ":n:c:h" opt; do
        case "$opt" in
            n) NAMESPACE="$OPTARG" ;;
            c) CONTAINER_INDEX="$OPTARG" ;;
            h) usage ;;
            \?) die "Invalid option: -$OPTARG. Use -h for help." ;;
            :) die "Option -$OPTARG requires an argument." ;;
        esac
    done
    shift $((OPTIND - 1))

    POD_NAME="${1:-}"
    
    if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
        usage
    fi
    
    # Validate container index is numeric
    if ! [[ "$CONTAINER_INDEX" =~ ^[0-9]+$ ]]; then
        die "Container index must be a non-negative integer, got: $CONTAINER_INDEX"
    fi
}

############################################
# Header
############################################
print_header() {
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo -e "║  ${CYAN}Pod Startup Time Measurement and Probe Configuration Tool${NC}     ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo -e "║  ${YELLOW}Pod:${NC} ${POD_NAME}"
    echo -e "║  ${YELLOW}Namespace:${NC} ${NAMESPACE}"
    echo -e "║  ${YELLOW}Container Index:${NC} ${CONTAINER_INDEX}"
    echo "╚═══════════════════════════════════════════════════════════════╝"
}

############################################
# Step 1: Pod Basic Info
############################################
step1_get_pod_basic_info() {
    section "📋 Step 1/6: Get Pod Basic Information"

    # Fetch pod JSON with error handling
    if ! POD_JSON=$("$KUBECTL_CMD" get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>&1); then
        die "Failed to get pod information:\n$POD_JSON"
    fi

    # Validate pod exists
    if [[ -z "$POD_JSON" ]]; then
        die "Pod not found: $POD_NAME in namespace: $NAMESPACE"
    fi

    # Check if container index exists
    local container_count
    container_count=$(json_get "$POD_JSON" '.spec.containers | length' "0")
    if [[ "$CONTAINER_INDEX" -ge "$container_count" ]]; then
        die "Container index $CONTAINER_INDEX out of range (pod has $container_count container(s))"
    fi

    # Extract basic information
    POD_STATUS=$(json_get "$POD_JSON" '.status.phase' 'Unknown')
    CONTAINER_NAME=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].name" 'unknown')
    IMAGE=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].image" 'unknown')
    NODE=$(json_get "$POD_JSON" '.spec.nodeName' 'unknown')
    POD_START=$(json_get "$POD_JSON" '.status.startTime' 'null')
    CONTAINER_START=$(json_get "$POD_JSON" ".status.containerStatuses[$CONTAINER_INDEX].state.running.startedAt" 'null')

    # Validate critical fields
    validate_json_field "$POD_STATUS" "Pod Status"
    validate_json_field "$CONTAINER_NAME" "Container Name"
    validate_json_field "$POD_START" "Pod Start Time"

    echo -e "   ${CYAN}Pod Status:${NC} $POD_STATUS"
    echo -e "   ${CYAN}Container Name:${NC} $CONTAINER_NAME"
    echo -e "   ${CYAN}Container Image:${NC} $IMAGE"
    echo -e "   ${CYAN}Running Node:${NC} $NODE"
    echo -e "   ${CYAN}Pod Creation Time:${NC} $POD_START"
    
    if [[ "$CONTAINER_START" != "null" ]]; then
        echo -e "   ${CYAN}Container Start Time:${NC} $CONTAINER_START"
    else
        warn "Container has not started yet"
    fi
}

############################################
# Step 2: Probe Configuration
############################################
step2_analyze_probe_configuration() {
    section "🔍 Step 2/6: Analyze Probe Configuration"
    echo -e "${CYAN}📌 Current Probe Configuration Overview:${NC}"
    echo

    local probe_found=0

    for probe in startupProbe readinessProbe livenessProbe; do
        if "$JQ_CMD" -e ".spec.containers[$CONTAINER_INDEX].$probe" <<<"$POD_JSON" >/dev/null 2>&1; then
            echo -e "   ${GREEN}✓${NC} $probe: Configured"
            
            local initial_delay period_seconds failure_threshold
            initial_delay=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.initialDelaySeconds" "0")
            period_seconds=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.periodSeconds" "10")
            failure_threshold=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe.failureThreshold" "3")
            
            echo "     - initialDelaySeconds: ${initial_delay}s"
            echo "     - periodSeconds: ${period_seconds}s"
            echo "     - failureThreshold: ${failure_threshold}"

            if [[ "$probe" == "startupProbe" ]]; then
                MAX_TIME=$((period_seconds * failure_threshold))
                echo -e "     ${YELLOW}→${NC} Maximum allowed startup time: ${MAX_TIME}s"
            fi
            
            probe_found=1
        else
            echo -e "   ${RED}✗${NC} $probe: Not Configured"
        fi
        echo
    done

    if [[ "$probe_found" -eq 0 ]]; then
        warn "No probes configured for this container"
    fi
}

############################################
# Step 3: Probe Endpoint
############################################
step3_extract_probe_endpoint() {
    section "🔍 Step 3/6: Extract Probe Detection Parameters"

    # Try readinessProbe first, then startupProbe, then livenessProbe
    local probe_type=""
    for pt in readinessProbe startupProbe livenessProbe; do
        if "$JQ_CMD" -e ".spec.containers[$CONTAINER_INDEX].$pt.httpGet" <<<"$POD_JSON" >/dev/null 2>&1; then
            probe_type="$pt"
            break
        fi
    done

    if [[ -z "$probe_type" ]]; then
        warn "No HTTP probe configured, using default values"
        PROBE_PATH="/"
        PORT="80"
        SCHEME="HTTP"
    else
        PROBE_PATH=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.path" "/")
        PORT=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.port" "80")
        SCHEME=$(json_get "$POD_JSON" ".spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.scheme" "HTTP")
    fi

    echo -e "   ${CYAN}Detection Endpoint Information:${NC}"
    echo "   - Probe Type: ${probe_type:-None}"
    echo "   - Scheme: $SCHEME"
    echo "   - Port: $PORT"
    echo "   - Path: $PROBE_PATH"
    echo -e "   ${YELLOW}→${NC} Full URL: $SCHEME://localhost:$PORT$PROBE_PATH"
}

############################################
# Step 4: Measure Startup Time
############################################
step4_measure_startup_time() {
    section "⏱️  Step 4/6: Measure Actual Startup Time"

    READY_TIME=$(json_get "$POD_JSON" '
        .status.conditions[]
        | select(.type=="Ready" and .status=="True")
        | .lastTransitionTime
    ' 'null')

    if [[ -n "$READY_TIME" && "$READY_TIME" != "null" ]]; then
        success "Pod is already in Ready status"
        echo -e "   ${CYAN}Ready Time:${NC} $READY_TIME"
    else
        warn "Pod is not in Ready status yet"
        info "Current pod phase: $POD_STATUS"
        
        # Show current conditions
        echo
        echo -e "   ${CYAN}Current Pod Conditions:${NC}"
        "$JQ_CMD" -r '.status.conditions[] | "   - \(.type): \(.status) (\(.reason // "N/A"))"' <<<"$POD_JSON" 2>/dev/null || echo "   No conditions available"
        
        die "Cannot calculate startup time for non-ready pod"
    fi
}

############################################
# Step 5: Analysis
############################################
step5_analyze_startup_time() {
    section "📊 Step 5/6: Startup Time Analysis"

    # Validate timestamps
    if [[ "$CONTAINER_START" == "null" ]]; then
        die "Container has not started yet, cannot calculate startup time"
    fi

    START_EPOCH=$(iso_to_epoch "$CONTAINER_START")
    READY_EPOCH=$(iso_to_epoch "$READY_TIME")
    STARTUP_TIME=$((READY_EPOCH - START_EPOCH))

    # Handle negative startup time (clock skew or other issues)
    if [[ "$STARTUP_TIME" -lt 0 ]]; then
        warn "Calculated negative startup time, possible clock skew"
        STARTUP_TIME=0
    fi

    success "Actual Application Startup Time: ${STARTUP_TIME} seconds"
    echo -e "   ${CYAN}📝 Measurement Data Source:${NC} Kubernetes Ready Status"
    echo
    echo -e "   ${CYAN}⏱️  Startup Timeline:${NC}"
    echo "   ┌────────────────────────────────────────────────────────┐"
    echo "   │ 0s                                          ${STARTUP_TIME}s │"
    echo "   │ ├──────────────────────────────────────────┤           │"
    echo "   │ Container Start                      Application Ready   │"
    echo "   └────────────────────────────────────────────────────────┘"

    # Compare with configured maximum time
    if [[ -n "${MAX_TIME:-}" ]]; then
        echo
        echo -e "   ${CYAN}📊 Configuration Comparison Analysis:${NC}"
        echo "   Configuration Type: StartupProbe"
        echo "   Maximum Allowed Startup Time: ${MAX_TIME}s"
        echo "   Actual Startup Time: ${STARTUP_TIME}s"
        
        local buffer=$((MAX_TIME - STARTUP_TIME))
        if [[ "$buffer" -gt 0 ]]; then
            success "Configuration is reasonable, buffer time: ${buffer}s"
        elif [[ "$buffer" -eq 0 ]]; then
            warn "Configuration is at the limit, consider increasing buffer"
        else
            echo -e "   ${RED}⚠${NC}  Configuration is too tight, startup time exceeds limit by $((buffer * -1))s"
        fi
    fi
    
    # Provide startup time assessment
    echo
    echo -e "   ${CYAN}Startup Performance Assessment:${NC}"
    if [[ "$STARTUP_TIME" -lt 10 ]]; then
        echo -e "   ${GREEN}Excellent${NC} - Very fast startup (<10s)"
    elif [[ "$STARTUP_TIME" -lt 30 ]]; then
        echo -e "   ${GREEN}Good${NC} - Normal startup time (10-30s)"
    elif [[ "$STARTUP_TIME" -lt 60 ]]; then
        echo -e "   ${YELLOW}Moderate${NC} - Slower startup (30-60s)"
    else
        echo -e "   ${RED}Slow${NC} - Long startup time (>60s), consider optimization"
    fi
}

############################################
# Step 6: Recommendation
############################################
step6_print_recommendations() {
    section "💡 Step 6/6: Configuration Optimization Recommendations"

    # Calculate recommended values based on actual startup time
    local recommended_failure_threshold=$(( (STARTUP_TIME / 10) + 2 ))
    local recommended_period=10

    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo -e "║  ${GREEN}Option 1: Using StartupProbe + ReadinessProbe (Recommended)${NC}  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo
    echo -e "${CYAN}Advantages:${NC}"
    echo "  • Separates startup and runtime phases"
    echo "  • Prevents slow-start false failures"
    echo "  • Faster runtime detection"
    echo
    echo -e "${CYAN}Recommended Configuration (based on measured ${STARTUP_TIME}s startup):${NC}"
    echo
    echo "  startupProbe:"
    echo "    httpGet:"
    echo "      path: $PROBE_PATH"
    echo "      port: $PORT"
    echo "      scheme: $SCHEME"
    echo "    periodSeconds: $recommended_period"
    echo "    failureThreshold: $recommended_failure_threshold"
    echo "    # Allows up to $((recommended_period * recommended_failure_threshold))s for startup"
    echo
    echo "  readinessProbe:"
    echo "    httpGet:"
    echo "      path: $PROBE_PATH"
    echo "      port: $PORT"
    echo "      scheme: $SCHEME"
    echo "    periodSeconds: 5"
    echo "    failureThreshold: 3"
    echo "    # Quick detection after startup (15s max)"
    echo
    echo "  livenessProbe:"
    echo "    httpGet:"
    echo "      path: $PROBE_PATH"
    echo "      port: $PORT"
    echo "      scheme: $SCHEME"
    echo "    periodSeconds: 10"
    echo "    failureThreshold: 3"
    echo "    initialDelaySeconds: $((STARTUP_TIME + 10))"
    echo "    # Only starts after startup is complete"
    echo
    echo -e "${YELLOW}Note:${NC} Adjust values based on your application's specific needs"
}

############################################
# Main Entry Point
############################################
main() {
    parse_args "$@"
    print_header

    step1_get_pod_basic_info
    step2_analyze_probe_configuration
    step3_extract_probe_endpoint
    step4_measure_startup_time
    step5_analyze_startup_time
    step6_print_recommendations

    echo
    success "Analysis completed successfully!"
}

# Execute main function
main "$@"