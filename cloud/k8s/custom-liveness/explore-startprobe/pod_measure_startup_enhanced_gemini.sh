#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# 🎨 Color & Style Definitions
############################################
# Standard Colors (using ANSI-C quoting for proper escape sequences)
readonly RESET=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly UNDERLINE=$'\033[4m'

# Foreground Colors
readonly BLACK=$'\033[30m'
readonly RED=$'\033[31m'
readonly GREEN=$'\033[32m'
readonly YELLOW=$'\033[33m'
readonly BLUE=$'\033[34m'
readonly MAGENTA=$'\033[35m'
readonly CYAN=$'\033[36m'
readonly WHITE=$'\033[37m'

# Bright/Bold Colors
readonly BRIGHT_RED=$'\033[1;31m'
readonly BRIGHT_GREEN=$'\033[1;32m'
readonly BRIGHT_YELLOW=$'\033[1;33m'
readonly BRIGHT_BLUE=$'\033[1;34m'
readonly BRIGHT_CYAN=$'\033[1;36m'

# Status Icons
readonly ICON_SUCCESS="✅"
readonly ICON_WARN="⚠️ "
readonly ICON_ERROR="❌"
readonly ICON_INFO="ℹ️ "
readonly ICON_TIME="⏱️ "
readonly ICON_SEARCH="🔍"
readonly ICON_ROCKET="🚀"
readonly ICON_DOC="📄"
readonly ICON_NETWORK="🌐"

############################################
# ⚙️  Global Configuration
############################################
readonly MAX_RETRIES=3
NAMESPACE=""
POD_NAME=""
CONTAINER_INDEX=0
VERBOSE=false

############################################
# 🛠️  Command Resolver & Dependency Check
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
    return 1
}

# Essential commands
KUBECTL_CMD=$(resolve_command kubectl /usr/local/bin/kubectl /usr/bin/kubectl /opt/homebrew/bin/kubectl) || { echo "Error: kubectl not found"; exit 1; }
JQ_CMD=$(resolve_command jq /usr/local/bin/jq /usr/bin/jq /opt/homebrew/bin/jq) || { echo "Error: jq not found. Please install jq."; exit 1; }
AWK_CMD=$(resolve_command awk /usr/bin/awk /bin/awk) || { echo "Error: awk not found"; exit 1; }

# Cross-platform Date Handling
if command -v gdate >/dev/null 2>&1; then
    DATE_CMD="gdate"
    DATE_IS_GNU=1
elif date --version 2>&1 | grep -q GNU; then
    DATE_CMD="date"
    DATE_IS_GNU=1
else
    DATE_CMD="date"
    DATE_IS_GNU=0
fi

############################################
# 🧰 Utility Functions
############################################
log_header() {
    echo
    echo "${BRIGHT_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${BOLD}${BRIGHT_BLUE} $1 ${RESET}"
    echo "${BRIGHT_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

log_info() { echo "  ${ICON_INFO} ${CYAN}$1${RESET}"; }
log_success() { echo "  ${ICON_SUCCESS} ${GREEN}$1${RESET}"; }
log_warn() { echo "  ${ICON_WARN} ${YELLOW}$1${RESET}"; }
log_error() { echo "  ${ICON_ERROR} ${BRIGHT_RED}$1${RESET}" >&2; }

# Fixed alignment and color handling
log_key_val() { 
    printf "  ${DIM}%-25s${RESET} ${BOLD}%s${RESET}\n" "$1:" "$2"
}

die() {
    log_error "$1"
    exit 1
}

# ISO8601 to Epoch
iso_to_epoch() {
    local timestamp="$1"
    if [[ "$timestamp" == "null" || -z "$timestamp" ]]; then
        echo "0"
        return
    fi
    
    if [[ "$DATE_IS_GNU" -eq 1 ]]; then
        "$DATE_CMD" -d "$timestamp" +%s 2>/dev/null
    else
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" 2>/dev/null || \
        "$DATE_CMD" -u -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%Z}" "+%s" 2>/dev/null
    fi
}

format_duration() {
    local seconds=$1
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    else
        echo "$((seconds / 60))m $((seconds % 60))s"
    fi
}

# Safe JSON extraction
json_get() {
    local json="$1"
    local path="$2"
    local default="${3:-null}"
    echo "$json" | "$JQ_CMD" -r "$path // \"$default\"" 2>/dev/null || echo "$default"
}

############################################
# 📥 Argument Parsing
############################################
usage() {
    echo "${BOLD}Usage:${RESET} $0 -n <namespace> [-c <container-index>] <pod-name>"
    echo
    echo "${BOLD}Options:${RESET}"
    echo "  ${YELLOW}-n${RESET}  Kubernetes namespace (required)"
    echo "  ${YELLOW}-c${RESET}  Container index (default: 0)"
    echo "  ${YELLOW}-v${RESET}  Verbose output"
    echo "  ${YELLOW}-h${RESET}  Show this help message"
    exit 0
}

while getopts ":n:c:vh" opt; do
    case "$opt" in
        n) NAMESPACE="$OPTARG" ;; 
        c) CONTAINER_INDEX="$OPTARG" ;; 
        v) VERBOSE=true ;; 
        h) usage ;; 
        \?) die "Invalid option: -$OPTARG" ;; 
        :) die "Option -$OPTARG requires an argument" ;; 
    esac
done
shift $((OPTIND - 1))
POD_NAME="${1:-}"

if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
    usage
fi

############################################
# 🚀 Main Logic
############################################

# --- Step 1: Pod Info & Health Check ---
log_header "Step 1: Pod & Container Diagnostics"

if ! POD_JSON=$("$KUBECTL_CMD" get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>&1); then
    die "Failed to get pod '$POD_NAME' in namespace '$NAMESPACE'.\nDetails: $POD_JSON"
fi

POD_UID=$(json_get "$POD_JSON" '.metadata.uid')
POD_PHASE=$(json_get "$POD_JSON" '.status.phase')
NODE_NAME=$(json_get "$POD_JSON" '.spec.nodeName')
START_TIME=$(json_get "$POD_JSON" '.status.startTime')

# Container Specifics
CTR_BASE=".spec.containers[$CONTAINER_INDEX]"
# Correctly quoting string for JQ select
CTR_NAME_QUERY=$(json_get "$POD_JSON" "$CTR_BASE.name")
CTR_STATUS_BASE=".status.containerStatuses[] | select(.name == \"$CTR_NAME_QUERY\")"

CTR_NAME=$(json_get "$POD_JSON" "$CTR_BASE.name")
CTR_IMAGE=$(json_get "$POD_JSON" "$CTR_BASE.image")
CTR_READY=$(json_get "$POD_JSON" "$CTR_STATUS_BASE.ready" "false")
CTR_RESTARTS=$(json_get "$POD_JSON" "$CTR_STATUS_BASE.restartCount" "0")
CTR_STATE=$(json_get "$POD_JSON" "$CTR_STATUS_BASE.state | keys[0]")
CTR_STARTED_AT=$(json_get "$POD_JSON" "$CTR_STATUS_BASE.state.running.startedAt")

log_key_val "Pod Name" "$POD_NAME"
log_key_val "Namespace" "$NAMESPACE"
log_key_val "Node" "$NODE_NAME"
log_key_val "Phase" "$POD_PHASE"
log_key_val "Container" "$CTR_NAME"
log_key_val "Image" "$CTR_IMAGE"
log_key_val "Restarts" "$CTR_RESTARTS"

if [[ "$CTR_RESTARTS" -gt 0 ]]; then
    log_warn "Container has restarted $CTR_RESTARTS times!"
    
    LAST_STATE_REASON=$(json_get "$POD_JSON" "$CTR_STATUS_BASE.lastState.terminated.reason" "Unknown")
    LAST_STATE_EXIT=$(json_get "$POD_JSON" "$CTR_STATUS_BASE.lastState.terminated.exitCode" "Unknown")
    log_key_val "Last Failure" "$LAST_STATE_REASON (Exit Code: $LAST_STATE_EXIT)"
fi

# --- Step 2: Configuration Analysis ---
log_header "Step 2: Probe Configuration Analysis"

check_probe() {
    local type=$1
    local json=$2
    if "$JQ_CMD" -e "$CTR_BASE.$type" <<<"$json" >/dev/null 2>&1; then
        local delay=$(json_get "$json" "$CTR_BASE.$type.initialDelaySeconds" "0")
        local period=$(json_get "$json" "$CTR_BASE.$type.periodSeconds" "10")
        local thresh=$(json_get "$json" "$CTR_BASE.$type.failureThreshold" "3")
        local timeout=$(json_get "$json" "$CTR_BASE.$type.timeoutSeconds" "1")
        
        echo "  ${ICON_SUCCESS} ${BOLD}$type${RESET}: ${GREEN}Configured${RESET}"
        echo "     ${DIM}├─${RESET} Delay: ${delay}s"
        echo "     ${DIM}├─${RESET} Period: ${period}s"
        echo "     ${DIM}├─${RESET} Threshold: ${thresh}"
        echo "     ${DIM}└─${RESET} Timeout: ${timeout}s"
        
        if [[ "$type" == "startupProbe" ]]; then
             MAX_STARTUP_WINDOW=$((period * thresh))
             echo "     ${ICON_TIME} ${CYAN}Max Startup Window: ${MAX_STARTUP_WINDOW}s${RESET}"
        fi
        return 0
    else
        echo "  ${ICON_ERROR} ${BOLD}$type${RESET}: ${DIM}Not Configured${RESET}"
        return 1
    fi
}

HAS_STARTUP=0
check_probe "startupProbe" "$POD_JSON" && HAS_STARTUP=1
check_probe "readinessProbe" "$POD_JSON"
check_probe "livenessProbe" "$POD_JSON"

# --- Step 3: Timeline & Performance ---
log_header "Step 3: Startup Performance Measurement"

# Get Critical Timestamps
TS_POD_START=$(iso_to_epoch "$START_TIME")
TS_CTR_START=$(iso_to_epoch "$CTR_STARTED_AT")

# Find when the pod actually became Ready
# We look at the Condition "Ready" lastTransitionTime
READY_CONDITION_TIME=$(json_get "$POD_JSON" '.status.conditions[] | select(.type=="Ready" and .status=="True") | .lastTransitionTime')
TS_READY=$(iso_to_epoch "$READY_CONDITION_TIME")

if [[ "$TS_CTR_START" == "0" ]]; then
    die "Container is not in 'Running' state. Cannot measure startup time."
fi

if [[ "$TS_READY" == "0" ]]; then
    log_warn "Pod is NOT YET READY. Measuring current uptime..."
    NOW_EPOCH=$(date +%s)
    CURRENT_RUN_TIME=$((NOW_EPOCH - TS_CTR_START))
    log_key_val "Current Uptime" "$(format_duration $CURRENT_RUN_TIME)"
    log_info "Waiting for readiness..."
    exit 0
fi

# Calculate Durations
INIT_DURATION=$((TS_CTR_START - TS_POD_START))
STARTUP_DURATION=$((TS_READY - TS_CTR_START))
TOTAL_DURATION=$((TS_READY - TS_POD_START))

# Sanity Check
if [[ $INIT_DURATION -lt 0 ]]; then INIT_DURATION=0; fi
if [[ $STARTUP_DURATION -lt 0 ]]; then STARTUP_DURATION=0; fi

log_key_val "Pod Scheduled" "$START_TIME"
log_key_val "Container Started" "$CTR_STARTED_AT"
log_key_val "Pod Ready" "$READY_CONDITION_TIME"
echo
echo "  ${BOLD}⏱️  Timeline Breakdown:${RESET}"
printf "  %-20s %s\n" "Initialization:" "$(format_duration $INIT_DURATION) (Pulling image, mounting vols, etc)"
printf "  %-20s ${BRIGHT_GREEN}%s${RESET}\n" "App Startup:" "$(format_duration $STARTUP_DURATION) (Actual app initialization)"
printf "  %-20s %s\n" "Total Time:" "$(format_duration $TOTAL_DURATION)"

# Visual Timeline
echo
bar_width=40
total_sec=$TOTAL_DURATION
if [[ $total_sec -eq 0 ]]; then total_sec=1; fi
init_share=$(echo "scale=2; $INIT_DURATION / $total_sec * $bar_width" | bc 2>/dev/null | cut -d. -f1 || echo "0")
app_share=$(echo "scale=2; $STARTUP_DURATION / $total_sec * $bar_width" | bc 2>/dev/null | cut -d. -f1 || echo "0")

# Ensure at least 1 char if duration > 0
[[ $INIT_DURATION -gt 0 && $init_share -eq 0 ]] && init_share=1
[[ $STARTUP_DURATION -gt 0 && $app_share -eq 0 ]] && app_share=1

printf "  ${DIM}[${RESET}"
for ((i=0; i<init_share; i++)); do printf "${BLUE}█${RESET}"; done
for ((i=0; i<app_share; i++)); do printf "${GREEN}█${RESET}"; done
# Fill remaining space
remaining=$((bar_width - init_share - app_share))
if [[ $remaining -lt 0 ]]; then remaining=0; fi
for ((i=0; i<remaining; i++)); do printf " "; done
printf "${DIM}]${RESET}\n"
echo "   ${BLUE}■ Init${RESET}  ${GREEN}■ App Startup${RESET}"


# --- Step 4: Event Logs ---
log_header "Step 4: Recent Events"
EVENTS=$("$KUBECTL_CMD" get events -n "$NAMESPACE" --field-selector involvedObject.name="$POD_NAME" --sort-by='.lastTimestamp' | tail -n 5)
if [[ -z "$EVENTS" ]]; then
    log_info "No recent events found."
else
    # IFS read loop to preserve lines
    echo "$EVENTS" | while IFS= read -r line; do
        if echo "$line" | grep -q "Warning"; then
            echo "${RED}$line${RESET}"
        else
            echo "${DIM}$line${RESET}"
        fi
    done
fi

# --- Step 5: Recommendations ---
log_header "Step 5: Analysis & Recommendations"

# Evaluation
if [[ $STARTUP_DURATION -lt 5 ]]; then
    log_success "Startup Speed: EXCELLENT (<5s)"
elif [[ $STARTUP_DURATION -lt 30 ]]; then
    log_success "Startup Speed: GOOD (<30s)"
elif [[ $STARTUP_DURATION -lt 60 ]]; then
    log_warn "Startup Speed: MODERATE (30-60s)"
else
    log_error "Startup Speed: SLOW (>60s)"
fi

# Probe Logic Check
if [[ $HAS_STARTUP -eq 1 ]]; then
    if [[ $STARTUP_DURATION -gt $MAX_STARTUP_WINDOW ]]; then
        log_error "CRITICAL: Actual startup ($STARTUP_DURATION s) EXCEEDS configured startupProbe window ($MAX_STARTUP_WINDOW s)!"
        echo "  ${ICON_ROCKET} ${BOLD}Action:${RESET} Increase 'failureThreshold' or 'periodSeconds' in startupProbe."
    else
        BUFFER=$((MAX_STARTUP_WINDOW - STARTUP_DURATION))
        log_success "Configuration Safe. Buffer: ${BUFFER}s"
    fi
else
    log_info "No startupProbe configured."
    if [[ $STARTUP_DURATION -gt 30 ]]; then
         echo "  ${ICON_ROCKET} ${BOLD}Recommendation:${RESET} Since app takes ${STARTUP_DURATION}s to start, add a ${CYAN}startupProbe${RESET}."
         echo "     This prevents the livenessProbe from killing the container prematurely."
    fi
fi

# Liveness Delay Check
LIVENESS_DELAY=$(json_get "$POD_JSON" "$CTR_BASE.livenessProbe.initialDelaySeconds" "0")
if [[ $HAS_STARTUP -eq 0 && $LIVENESS_DELAY -lt $STARTUP_DURATION ]]; then
    log_warn "Risk: livenessProbe initialDelaySeconds ($LIVENESS_DELAY s) < Startup Time ($STARTUP_DURATION s)"
    echo "  ${ICON_ROCKET} ${BOLD}Fix:${RESET} Increase initialDelaySeconds to at least $((STARTUP_DURATION + 10))s OR use a startupProbe."
fi

# Final Footer
echo
echo "${DIM}Generated by Gemini Enhanced Tool • $(date)${RESET}"
echo
