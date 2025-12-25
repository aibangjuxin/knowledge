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
# Utility Functions
############################################
die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}

info() {
    echo -e "${CYAN}INFO:${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

############################################
# Command Detection
############################################
KUBECTL_CMD=""
JQ_CMD=""

detect_commands() {
    # Detect kubectl
    for path in /opt/homebrew/bin/kubectl /usr/local/bin/kubectl /usr/bin/kubectl; do
        if [[ -x "$path" ]]; then
            KUBECTL_CMD="$path"
            break
        fi
    done
    
    if [[ -z "$KUBECTL_CMD" ]] && command -v kubectl &>/dev/null; then
        KUBECTL_CMD="kubectl"
    fi
    
    if [[ -z "$KUBECTL_CMD" ]]; then
        die "kubectl command not found"
    fi

    # Detect jq
    for path in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do
        if [[ -x "$path" ]]; then
            JQ_CMD="$path"
            break
        fi
    done
    
    if [[ -z "$JQ_CMD" ]] && command -v jq &>/dev/null; then
        JQ_CMD="jq"
    fi
    
    if [[ -z "$JQ_CMD" ]]; then
        die "jq command not found"
    fi
}

############################################
# Usage
############################################
usage() {
    echo -e "${BLUE}Usage:${NC} $0 -n <namespace> <deployment-name>"
    echo
    echo -e "${BLUE}Description:${NC}"
    echo "  Extract health check URL from Kubernetes Deployment's probe configuration."
    echo
    echo -e "${BLUE}Options:${NC}"
    echo "  -n  Kubernetes namespace (required)"
    echo "  -c  Container index for multi-container pods (default: 0)"
    echo "  -p  Pod IP mode - if set, use a pod's IP instead of localhost (optional)"
    echo "  -o  Output format: url (default), openssl, curl, wget, all"
    echo "  -h  Show this help message"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo "  # Get health check URL from deployment"
    echo "  $0 -n default my-deployment"
    echo
    echo "  # Get health check URL with openssl command"
    echo "  $0 -n default -o openssl my-deployment"
    echo
    echo "  # Get all command variants"
    echo "  $0 -n default -o all my-deployment"
    echo
    echo "  # Use pod IP instead of localhost"
    echo "  $0 -n default -p my-deployment"
    exit 0
}

############################################
# Main Logic
############################################
NAMESPACE=""
DEPLOYMENT_NAME=""
CONTAINER_INDEX=0
USE_POD_IP=0
OUTPUT_FORMAT="url"

parse_args() {
    while getopts ":n:c:o:ph" opt; do
        case "$opt" in
            n) NAMESPACE="$OPTARG" ;;
            c) CONTAINER_INDEX="$OPTARG" ;;
            o) OUTPUT_FORMAT="$OPTARG" ;;
            p) USE_POD_IP=1 ;;
            h) usage ;;
            \?) die "Invalid option: -$OPTARG. Use -h for help." ;;
            :) die "Option -$OPTARG requires an argument." ;;
        esac
    done
    shift $((OPTIND - 1))

    DEPLOYMENT_NAME="${1:-}"
    
    if [[ -z "$NAMESPACE" || -z "$DEPLOYMENT_NAME" ]]; then
        usage
    fi
}

get_health_url_from_deployment() {
    local deploy_json
    local container_count
    local probe_type=""
    local probe_path="/"
    local port="80"
    local scheme="HTTP"
    local host="localhost"

    # Fetch deployment JSON
    local kubectl_exit_code=0
    deploy_json=$("$KUBECTL_CMD" get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o json 2>&1) || kubectl_exit_code=$?
    
    if [[ "$kubectl_exit_code" -ne 0 ]]; then
        die "Failed to get deployment '$DEPLOYMENT_NAME' in namespace '$NAMESPACE': $deploy_json"
    fi

    # Check container count
    container_count=$(echo "$deploy_json" | "$JQ_CMD" -r '.spec.template.spec.containers | length')
    if [[ "$CONTAINER_INDEX" -ge "$container_count" ]]; then
        die "Container index $CONTAINER_INDEX out of range (deployment has $container_count container(s))"
    fi

    # Extract probe configuration - priority order: readinessProbe > startupProbe > livenessProbe
    for pt in readinessProbe startupProbe livenessProbe; do
        if echo "$deploy_json" | "$JQ_CMD" -e ".spec.template.spec.containers[$CONTAINER_INDEX].$pt.httpGet" >/dev/null 2>&1; then
            probe_type="$pt"
            break
        fi
    done

    if [[ -z "$probe_type" ]]; then
        # Check for TCP socket probe
        for pt in readinessProbe startupProbe livenessProbe; do
            if echo "$deploy_json" | "$JQ_CMD" -e ".spec.template.spec.containers[$CONTAINER_INDEX].$pt.tcpSocket" >/dev/null 2>&1; then
                port=$(echo "$deploy_json" | "$JQ_CMD" -r ".spec.template.spec.containers[$CONTAINER_INDEX].$pt.tcpSocket.port // 80")
                echo -e "${YELLOW}Note:${NC} Only TCP probe found (no HTTP probe), showing TCP endpoint"
                echo
                echo -e "${CYAN}TCP Endpoint:${NC} $host:$port"
                return 0
            fi
        done
        die "No HTTP or TCP probe configured in deployment $DEPLOYMENT_NAME"
    fi

    # Extract probe details
    probe_path=$(echo "$deploy_json" | "$JQ_CMD" -r ".spec.template.spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.path // \"/\"")
    port=$(echo "$deploy_json" | "$JQ_CMD" -r ".spec.template.spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.port // 80")
    scheme=$(echo "$deploy_json" | "$JQ_CMD" -r ".spec.template.spec.containers[$CONTAINER_INDEX].$probe_type.httpGet.scheme // \"HTTP\"")

    # Convert scheme to lowercase for URL
    local url_scheme
    url_scheme=$(echo "$scheme" | tr '[:upper:]' '[:lower:]')

    # Get pod IP if requested
    if [[ "$USE_POD_IP" -eq 1 ]]; then
        local selector
        selector=$(echo "$deploy_json" | "$JQ_CMD" -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')
        
        if [[ -n "$selector" ]]; then
            local pod_ip
            pod_ip=$("$KUBECTL_CMD" get pods -n "$NAMESPACE" -l "$selector" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")
            
            if [[ -n "$pod_ip" && "$pod_ip" != "null" ]]; then
                host="$pod_ip"
                info "Using pod IP: $pod_ip"
            else
                echo -e "${YELLOW}WARNING:${NC} Could not get pod IP, falling back to localhost"
            fi
        fi
    fi

    # Build URL
    local full_url="${url_scheme}://${host}:${port}${probe_path}"

    # Output based on format
    case "$OUTPUT_FORMAT" in
        url)
            echo -e "${CYAN}Probe Type:${NC} $probe_type"
            echo -e "${CYAN}Scheme:${NC} $scheme"
            echo -e "${CYAN}Port:${NC} $port"
            echo -e "${CYAN}Path:${NC} $probe_path"
            echo
            echo -e "${GREEN}Health Check URL:${NC}"
            echo "$full_url"
            ;;
        openssl)
            print_openssl_command "$host" "$port" "$probe_path" "$scheme"
            ;;
        curl)
            print_curl_command "$host" "$port" "$probe_path" "$scheme" "$full_url"
            ;;
        wget)
            print_wget_command "$full_url" "$scheme"
            ;;
        all)
            echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
            echo -e "${BLUE}Health Check URL from Deployment: $DEPLOYMENT_NAME${NC}"
            echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
            echo
            echo -e "${CYAN}Probe Type:${NC} $probe_type"
            echo -e "${CYAN}Scheme:${NC} $scheme"
            echo -e "${CYAN}Port:${NC} $port"
            echo -e "${CYAN}Path:${NC} $probe_path"
            echo -e "${CYAN}Full URL:${NC} $full_url"
            echo
            echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
            echo -e "${YELLOW}Command Examples:${NC}"
            echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
            echo
            print_curl_command "$host" "$port" "$probe_path" "$scheme" "$full_url"
            echo
            print_wget_command "$full_url" "$scheme"
            echo
            print_openssl_command "$host" "$port" "$probe_path" "$scheme"
            ;;
        *)
            die "Invalid output format: $OUTPUT_FORMAT. Use: url, openssl, curl, wget, all"
            ;;
    esac
}

print_openssl_command() {
    local host="$1"
    local port="$2"
    local path="$3"
    local scheme="$4"

    echo -e "${MAGENTA}# OpenSSL Command:${NC}"
    if [[ "$scheme" == "HTTPS" ]]; then
        echo "printf \"GET ${path} HTTP/1.1\\r\\nHost: ${host}\\r\\nConnection: close\\r\\n\\r\\n\" | openssl s_client -connect ${host}:${port} -quiet 2>/dev/null"
        echo
        echo -e "${MAGENTA}# With status code extraction:${NC}"
        cat <<'EOF'
RESPONSE=$(printf "GET PATH HTTP/1.1\r\nHost: HOST\r\nConnection: close\r\n\r\n" | openssl s_client -connect HOST:PORT -quiet 2>/dev/null)
CODE=$(echo "$RESPONSE" | grep "HTTP/" | awk '{print $2}')
echo "HTTP Status Code: $CODE"
EOF
        # Replace placeholders
        echo
        echo -e "${CYAN}# Actual command:${NC}"
        echo "RESPONSE=\$(printf \"GET ${path} HTTP/1.1\\r\\nHost: ${host}\\r\\nConnection: close\\r\\n\\r\\n\" | openssl s_client -connect ${host}:${port} -quiet 2>/dev/null)"
        echo "CODE=\$(echo \"\$RESPONSE\" | grep \"HTTP/\" | awk '{print \$2}')"
        echo "echo \"HTTP Status Code: \$CODE\""
    else
        echo -e "${YELLOW}Note:${NC} HTTP endpoints don't need openssl, use curl/wget instead"
    fi
}

print_curl_command() {
    local host="$1"
    local port="$2"
    local path="$3"
    local scheme="$4"
    local url="$5"

    echo -e "${MAGENTA}# Curl Command:${NC}"
    if [[ "$scheme" == "HTTPS" ]]; then
        echo "curl -sk -o /dev/null -w '%{http_code}' \"$url\""
        echo
        echo -e "${CYAN}# With response details:${NC}"
        echo "curl -sk \"$url\""
    else
        echo "curl -s -o /dev/null -w '%{http_code}' \"$url\""
        echo
        echo -e "${CYAN}# With response details:${NC}"
        echo "curl -s \"$url\""
    fi
}

print_wget_command() {
    local url="$1"
    local scheme="$2"

    echo -e "${MAGENTA}# Wget Command:${NC}"
    if [[ "$scheme" == "HTTPS" ]]; then
        echo "wget --no-check-certificate -qO- \"$url\""
    else
        echo "wget -qO- \"$url\""
    fi
}

############################################
# Main
############################################
main() {
    detect_commands
    parse_args "$@"
    get_health_url_from_deployment
}

main "$@"
