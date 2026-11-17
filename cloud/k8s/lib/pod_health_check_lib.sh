#!/bin/bash
# pod_health_check_lib.sh - Kubernetes Pod Health Check Function Library
# Version: 1.0.3
# Usage: source this file in your scripts
#
# Example:
#   source /path/to/pod_health_check_lib.sh
#   STATUS=$(check_pod_health "my-pod" "production" "HTTPS" "8443" "/health")

# ============================================================================
# Command Definitions - Direct paths for cross-platform compatibility
# ============================================================================
# macOS with Homebrew (Apple Silicon)
if [ -f "/opt/homebrew/bin/gdate" ]; then
    DATE_CMD="/opt/homebrew/bin/gdate"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
    jq="/opt/homebrew/bin/jq"
# macOS with Homebrew (Intel)
elif [ -f "/usr/local/bin/gdate" ]; then
    DATE_CMD="/usr/local/bin/gdate"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
# Standard macOS or Linux
else
    DATE_CMD="/bin/date"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
fi

# Fallback: try to find commands in PATH if hardcoded paths don't exist
[ ! -x "$DATE_CMD" ] && DATE_CMD="date"
[ ! -x "$AWK_CMD" ] && AWK_CMD="awk"
[ ! -x "$SLEEP_CMD" ] && SLEEP_CMD="sleep"

# ============================================================================
# Color Definitions
# ============================================================================
export HC_GREEN='\033[0;32m'
export HC_BLUE='\033[0;34m'
export HC_YELLOW='\033[1;33m'
export HC_RED='\033[0;31m'
export HC_CYAN='\033[0;36m'
export HC_MAGENTA='\033[0;35m'
export HC_NC='\033[0m'

# ============================================================================
# Core Function: check_pod_health
# Description: Check health endpoint inside a Pod
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
#   $3 - Protocol (HTTP/HTTPS)
#   $4 - Port
#   $5 - Path
#   $6 - Timeout in seconds (optional, default: 2)
# Returns:
#   0 - Health check passed (HTTP 200)
#   1 - Health check failed
# Output:
#   HTTP status code (e.g., "200", "404", "000" for connection failure)
# ============================================================================
check_pod_health() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local timeout="${6:-2}"
    
    # Parameter validation
    if [ -z "$pod_name" ] || [ -z "$namespace" ] || [ -z "$port" ] || [ -z "$path" ]; then
        echo "000"
        return 1
    fi
    
    local http_status_line
    local http_code
    
    # Select detection method based on protocol
    if [[ "$scheme" == "HTTPS" ]]; then
        http_status_line=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${path}" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- sh -c \
            "openssl s_client -connect localhost:${port} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
    else
        # HTTP Strategy: curl -> wget -> nc
        # execute a single compound command inside the pod to find an available tool
        local cmd="
        if command -v curl >/dev/null 2>&1; then
            # Option 1: curl (preferred)
            curl -m ${timeout} -s -I 'http://localhost:${port}${path}' 2>/dev/null | head -n 1
        elif command -v wget >/dev/null 2>&1; then
            # Option 2: wget
            wget -T ${timeout} -q --spider --server-response 'http://localhost:${port}${path}' 2>&1 | grep '^  HTTP' | head -n 1
        else
            # Option 3: nc (fallback)
            printf 'GET ${path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' | timeout ${timeout} nc localhost ${port} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1
        fi"
        
        http_status_line=$(kubectl exec -i "${pod_name}" -n "${namespace}" -- sh -c "$cmd" 2>/dev/null || echo "")
    fi
    http_code=$(echo "$http_status_line" | $AWK_CMD '{print $2}')
    if [ -z "$http_code" ]; then
        http_code="000"
    fi

    echo "$http_code"
    
    # Return 0 for success (200), 1 for failure
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Advanced Function: check_pod_health_with_retry
# Description: Health check with retry mechanism
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
#   $3 - Protocol (HTTP/HTTPS)
#   $4 - Port
#   $5 - Path
#   $6 - Max retries (optional, default: 3)
#   $7 - Retry interval in seconds (optional, default: 2)
# Returns:
#   0 - Health check passed
#   1 - All retries failed
# ============================================================================
check_pod_health_with_retry() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local max_retries="${6:-3}"
    local retry_interval="${7:-2}"
    
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        local status_code
        status_code=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            echo "$status_code"
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            $SLEEP_CMD "$retry_interval"
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "000"
    return 1
}

# ============================================================================
# Utility Function: wait_for_pod_ready
# Description: Wait for Pod to become Ready
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
#   $3 - Protocol (HTTP/HTTPS)
#   $4 - Port
#   $5 - Path
#   $6 - Max attempts (optional, default: 60)
#   $7 - Check interval in seconds (optional, default: 2)
#   $8 - Show progress (optional, yes/no, default: yes)
# Returns:
#   0 - Pod is ready
#   1 - Timeout
# Output:
#   Actual wait time in seconds
# ============================================================================
wait_for_pod_ready() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local max_attempts="${6:-60}"
    local check_interval="${7:-2}"
    local show_progress="${8:-yes}"
    
    local attempt=1
    local start_time=$($DATE_CMD +%s)
    
    while [ $attempt -le $max_attempts ]; do
        local status_code
        status_code=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            local end_time=$($DATE_CMD +%s)
            local elapsed=$((end_time - start_time))
            echo "$elapsed"
            return 0
        fi
        
        if [[ "$show_progress" == "yes" ]]; then
            local progress_percent=$((attempt * 100 / max_attempts))
            echo -ne "\r   [${attempt}/${max_attempts}] Waiting for Pod ready... ${progress_percent}% (Status: ${status_code})"
        fi
        
        $SLEEP_CMD "$check_interval"
        attempt=$((attempt + 1))
    done
    
    echo ""
    echo "-1"
    return 1
}

# ============================================================================
# Utility Function: get_probe_config
# Description: Extract probe configuration from Pod
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
#   $3 - Probe type (startupProbe/readinessProbe/livenessProbe)
# Output:
#   JSON format probe configuration
# ============================================================================
get_probe_config() {
    local pod_name="$1"
    local namespace="$2"
    local probe_type="$3"
    
    kubectl get pod "${pod_name}" -n "${namespace}" \
        -o jsonpath="{.spec.containers[0].${probe_type}}" 2>/dev/null
}

# ============================================================================
# Utility Function: extract_probe_endpoint
# Description: Extract endpoint information from probe configuration
# Parameters:
#   $1 - Probe configuration (JSON)
# Output:
#   Format: "SCHEME PORT PATH"
# ============================================================================
extract_probe_endpoint() {
    local probe_config="$1"
    
    if [ -z "$probe_config" ] || [ "$probe_config" == "null" ]; then
        echo ""
        return 1
    fi
    
    local scheme=$(echo "$probe_config" | jq -r '.httpGet.scheme // "HTTP"')
    local port=$(echo "$probe_config" | jq -r '.httpGet.port // 8080')
    local path=$(echo "$probe_config" | jq -r '.httpGet.path // "/health"')
    
    echo "${scheme} ${port} ${path}"
    return 0
}

# ============================================================================
# Utility Function: calculate_max_startup_time
# Description: Calculate maximum startup time allowed by probe configuration
# Parameters:
#   $1 - Probe configuration (JSON)
# Output:
#   Maximum startup time in seconds
# ============================================================================
calculate_max_startup_time() {
    local probe_config="$1"
    
    if [ -z "$probe_config" ] || [ "$probe_config" == "null" ]; then
        echo "0"
        return 1
    fi
    
    local initial_delay=$(echo "$probe_config" | jq -r '.initialDelaySeconds // 0')
    local period=$(echo "$probe_config" | jq -r '.periodSeconds // 10')
    local failure_threshold=$(echo "$probe_config" | jq -r '.failureThreshold // 3')
    
    local max_time=$((initial_delay + period * failure_threshold))
    echo "$max_time"
    return 0
}

# ============================================================================
# Advanced Function: monitor_pod_health
# Description: Continuously monitor Pod health (Ctrl+C to stop)
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
#   $3 - Protocol (HTTP/HTTPS)
#   $4 - Port
#   $5 - Path
#   $6 - Check interval in seconds (optional, default: 5)
# ============================================================================
monitor_pod_health() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local interval="${6:-5}"
    
    echo -e "${HC_CYAN}Starting health monitoring for Pod: ${pod_name}${HC_NC}"
    echo -e "${HC_CYAN}Press Ctrl+C to stop${HC_NC}"
    echo ""
    
    while true; do
        local timestamp=$($DATE_CMD '+%Y-%m-%d %H:%M:%S')
        local status=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            echo -e "${timestamp} ${HC_GREEN}✓${HC_NC} Status: ${status}"
        else
            echo -e "${timestamp} ${HC_RED}✗${HC_NC} Status: ${status}"
        fi
        
        $SLEEP_CMD "$interval"
    done
}

# ============================================================================
# Utility Function: check_pod_exists
# Description: Check if Pod exists in namespace
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
# Returns:
#   0 - Pod exists
#   1 - Pod does not exist
# ============================================================================
check_pod_exists() {
    local pod_name="$1"
    local namespace="$2"
    
    kubectl get pod "${pod_name}" -n "${namespace}" &>/dev/null
    return $?
}

# ============================================================================
# Utility Function: get_pod_status
# Description: Get Pod phase status
# Parameters:
#   $1 - Pod name
#   $2 - Namespace
# Output:
#   Pod phase (Running, Pending, Failed, etc.)
# ============================================================================
get_pod_status() {
    local pod_name="$1"
    local namespace="$2"
    
    kubectl get pod "${pod_name}" -n "${namespace}" \
        -o jsonpath='{.status.phase}' 2>/dev/null
}

# ============================================================================
# Version Information
# ============================================================================
pod_health_check_lib_version() {
    echo "Pod Health Check Library v1.0.0"
}

# ============================================================================
# Help Function
# ============================================================================
pod_health_check_lib_help() {
    cat << 'EOF'
Pod Health Check Library v1.0.0
================================

Available Functions:

1. check_pod_health <pod> <namespace> <scheme> <port> <path> [timeout]
   - Basic health check, returns HTTP status code

2. check_pod_health_with_retry <pod> <namespace> <scheme> <port> <path> [retries] [interval]
   - Health check with retry mechanism

3. wait_for_pod_ready <pod> <namespace> <scheme> <port> <path> [max_attempts] [interval] [show_progress]
   - Wait for Pod to become ready, returns elapsed time

4. get_probe_config <pod> <namespace> <probe_type>
   - Extract probe configuration (startupProbe/readinessProbe/livenessProbe)

5. extract_probe_endpoint <probe_config_json>
   - Extract endpoint info from probe config, returns "SCHEME PORT PATH"

6. calculate_max_startup_time <probe_config_json>
   - Calculate maximum startup time from probe config

7. monitor_pod_health <pod> <namespace> <scheme> <port> <path> [interval]
   - Continuously monitor Pod health (Ctrl+C to stop)

8. check_pod_exists <pod> <namespace>
   - Check if Pod exists

9. get_pod_status <pod> <namespace>
   - Get Pod phase status

Usage Example:
  source pod_health_check_lib.sh
  STATUS=$(check_pod_health "my-pod" "production" "HTTPS" "8443" "/health")
  if [ $? -eq 0 ]; then
      echo "Health check passed: $STATUS"
  fi

For detailed documentation, see: openssl-verify-health.md
EOF
}
