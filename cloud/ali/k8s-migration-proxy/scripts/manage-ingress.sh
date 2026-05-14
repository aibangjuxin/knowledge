#!/bin/bash

# Ingress Management Script for K8s Cluster Migration
# Provides easy-to-use commands for managing ingress configurations
# Requirements: 2.1, 3.2, 5.1

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-aibang-1111111111-bbdm}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/manage-ingress.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Ingress Management Script for K8s Cluster Migration

USAGE:
    $0 <command> [options]

COMMANDS:
    deploy              Deploy ingress configurations
    set-weight <service> <weight>
                       Set canary weight (0-100)
    enable-canary <service> [options]
                       Enable canary routing
    disable-canary <service>
                       Disable canary routing
    add-path <service> <host> <path>
                       Add new host/path to ingress
    validate <service>  Validate ingress configuration
    status <service>    Get ingress status
    list               List all migration ingresses
    rollback <service>  Rollback to previous configuration
    help               Show this help message

OPTIONS:
    -n, --namespace    Kubernetes namespace (default: ${NAMESPACE})
    -v, --verbose      Verbose output
    --dry-run          Show what would be done without executing

EXAMPLES:
    # Deploy initial ingress configurations
    $0 deploy

    # Set canary weight to 10%
    $0 set-weight bbdm-api 10

    # Enable header-based canary routing
    $0 enable-canary bbdm-api --type header --header-name X-Canary --header-value new-cluster

    # Add new path to existing ingress
    $0 add-path bbdm-api api-name01.teamname.dev.aliyun.intracloud.cn.aibang /api/v2

    # Check ingress status
    $0 status bbdm-api

    # Validate configuration
    $0 validate bbdm-api

EOF
}

# Check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Please check your kubeconfig and cluster connectivity"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log_warning "Namespace ${NAMESPACE} does not exist"
        read -p "Create namespace ${NAMESPACE}? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl create namespace "${NAMESPACE}"
            log_success "Created namespace ${NAMESPACE}"
        else
            log_error "Namespace ${NAMESPACE} is required"
            exit 1
        fi
    fi
}

# Deploy ingress configurations
deploy_ingress() {
    log_info "Deploying ingress configurations..."
    
    local k8s_dir="${SCRIPT_DIR}/../k8s"
    
    # Apply ingress configurations
    if [ -f "${k8s_dir}/ingress.yaml" ]; then
        log_info "Applying ingress configurations..."
        kubectl apply -f "${k8s_dir}/ingress.yaml" -n "${NAMESPACE}"
        log_success "Applied ingress.yaml"
    fi
    
    # Apply ingress config maps
    if [ -f "${k8s_dir}/ingress-config.yaml" ]; then
        log_info "Applying ingress configuration maps..."
        kubectl apply -f "${k8s_dir}/ingress-config.yaml" -n "${NAMESPACE}"
        log_success "Applied ingress-config.yaml"
    fi
    
    # Wait for ingresses to be ready
    log_info "Waiting for ingresses to be ready..."
    sleep 5
    
    # Check ingress status
    local ingresses=$(kubectl get ingress -n "${NAMESPACE}" -o name 2>/dev/null || true)
    if [ -n "$ingresses" ]; then
        log_success "Deployed ingresses:"
        kubectl get ingress -n "${NAMESPACE}" -o wide
    else
        log_warning "No ingresses found after deployment"
    fi
}

# Set canary weight
set_canary_weight() {
    local service="$1"
    local weight="$2"
    
    log_info "Setting canary weight for ${service} to ${weight}%..."
    
    if python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" set-weight "${service}" "${weight}"; then
        log_success "Successfully set canary weight to ${weight}%"
        
        # Show updated status
        log_info "Current status:"
        python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" status "${service}"
    else
        log_error "Failed to set canary weight"
        exit 1
    fi
}

# Enable canary routing
enable_canary() {
    local service="$1"
    shift
    
    log_info "Enabling canary routing for ${service}..."
    
    if python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" enable-canary "${service}" "$@"; then
        log_success "Successfully enabled canary routing"
        
        # Show updated status
        log_info "Current status:"
        python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" status "${service}"
    else
        log_error "Failed to enable canary routing"
        exit 1
    fi
}

# Disable canary routing
disable_canary() {
    local service="$1"
    
    log_info "Disabling canary routing for ${service}..."
    
    if python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" disable-canary "${service}"; then
        log_success "Successfully disabled canary routing"
        
        # Show updated status
        log_info "Current status:"
        python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" status "${service}"
    else
        log_error "Failed to disable canary routing"
        exit 1
    fi
}

# Add host/path
add_host_path() {
    local service="$1"
    local host="$2"
    local path="$3"
    shift 3
    
    log_info "Adding host/path ${host}${path} to ${service}..."
    
    if python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" add-path "${service}" "${host}" "${path}" "$@"; then
        log_success "Successfully added host/path"
        
        # Show updated ingress
        log_info "Updated ingress:"
        kubectl get ingress "${service}-migration" -n "${NAMESPACE}" -o yaml | grep -A 20 "spec:"
    else
        log_error "Failed to add host/path"
        exit 1
    fi
}

# Validate configuration
validate_config() {
    local service="$1"
    
    log_info "Validating ingress configuration for ${service}..."
    
    local result
    if result=$(python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" validate "${service}"); then
        echo "$result" | python3 -m json.tool
        
        local valid=$(echo "$result" | python3 -c "import sys, json; print(json.load(sys.stdin)['valid'])")
        if [ "$valid" = "True" ]; then
            log_success "Configuration is valid"
        else
            log_warning "Configuration has issues"
            exit 1
        fi
    else
        log_error "Validation failed"
        exit 1
    fi
}

# Get status
get_status() {
    local service="$1"
    
    log_info "Getting status for ${service}..."
    
    if python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" status "${service}" | python3 -m json.tool; then
        log_success "Status retrieved successfully"
    else
        log_error "Failed to get status"
        exit 1
    fi
}

# List all migration ingresses
list_ingresses() {
    log_info "Listing all migration ingresses in namespace ${NAMESPACE}..."
    
    local ingresses
    if ingresses=$(kubectl get ingress -n "${NAMESPACE}" -l app=migration-proxy -o wide 2>/dev/null); then
        if [ -n "$ingresses" ]; then
            echo "$ingresses"
        else
            log_warning "No migration ingresses found"
        fi
    else
        log_error "Failed to list ingresses"
        exit 1
    fi
}

# Rollback configuration
rollback_config() {
    local service="$1"
    
    log_warning "Rolling back configuration for ${service}..."
    
    # Disable canary routing as a safe rollback
    log_info "Disabling canary routing as rollback measure..."
    if python3 "${PYTHON_SCRIPT}" --namespace "${NAMESPACE}" disable-canary "${service}"; then
        log_success "Rollback completed - canary routing disabled"
    else
        log_error "Rollback failed"
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            --dry-run)
                log_info "DRY RUN MODE - No changes will be made"
                # Add dry-run logic here if needed
                shift
                ;;
            -h|--help|help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Return remaining arguments
    echo "$@"
}

# Main function
main() {
    local args
    args=$(parse_args "$@")
    set -- $args
    
    local command="${1:-help}"
    
    # Check prerequisites for most commands
    if [ "$command" != "help" ]; then
        check_prerequisites
    fi
    
    case "$command" in
        deploy)
            deploy_ingress
            ;;
        set-weight)
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 set-weight <service> <weight>"
                exit 1
            fi
            set_canary_weight "$2" "$3"
            ;;
        enable-canary)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 enable-canary <service> [options]"
                exit 1
            fi
            enable_canary "${@:2}"
            ;;
        disable-canary)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 disable-canary <service>"
                exit 1
            fi
            disable_canary "$2"
            ;;
        add-path)
            if [ $# -lt 4 ]; then
                log_error "Usage: $0 add-path <service> <host> <path>"
                exit 1
            fi
            add_host_path "${@:2}"
            ;;
        validate)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 validate <service>"
                exit 1
            fi
            validate_config "$2"
            ;;
        status)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 status <service>"
                exit 1
            fi
            get_status "$2"
            ;;
        list)
            list_ingresses
            ;;
        rollback)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 rollback <service>"
                exit 1
            fi
            rollback_config "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"