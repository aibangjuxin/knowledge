#!/bin/bash
# k8s-ingress-migration-optimized.sh
# Optimized Kubernetes Ingress Migration Tool with enhanced error handling and performance

set -eEuo pipefail  # Enhanced error handling with pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default configuration
readonly DEFAULT_BACKUP_DIR="${SCRIPT_DIR}/backups"
readonly DEFAULT_LOG_DIR="${SCRIPT_DIR}/logs"
readonly DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/migration-config.yaml"
readonly DEFAULT_RECORDS_FILE="${SCRIPT_DIR}/migration-records.csv"
readonly DEFAULT_MAX_PARALLEL=5
readonly DEFAULT_RETRY_COUNT=3
readonly DEFAULT_RETRY_DELAY=5
readonly DEFAULT_HEALTH_CHECK_TIMEOUT=30

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
BACKUP_DIR="${DEFAULT_BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${DEFAULT_LOG_DIR}/migration_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
VERBOSE=false
FORCE=false
MAX_PARALLEL="${DEFAULT_MAX_PARALLEL}"
HEALTH_CHECK_ENABLED=true
JSON_OUTPUT=false
ROLLBACK_ON_ERROR=true

# Temporary files for cleanup
declare -a TEMP_FILES=()

# ==============================================================================
# ERROR HANDLING & CLEANUP
# ==============================================================================

# Trap handler for errors
error_handler() {
    local line_no=$1
    local exit_code=$2
    local command="${3:-}"
    
    log_error "Command failed with exit code ${exit_code} at line ${line_no}: ${command}"
    
    if [[ "${ROLLBACK_ON_ERROR}" == "true" ]] && [[ -n "${CURRENT_MIGRATION_HOST:-}" ]]; then
        log_warn "Attempting automatic rollback for ${CURRENT_MIGRATION_HOST}..."
        rollback_ingress "${CURRENT_MIGRATION_HOST}" || log_error "Rollback failed"
    fi
    
    cleanup
    exit "${exit_code}"
}

# Set up error trap
trap 'error_handler ${LINENO} $? "${BASH_COMMAND}"' ERR

# Cleanup function
cleanup() {
    local temp_file
    for temp_file in "${TEMP_FILES[@]}"; do
        [[ -f "${temp_file}" ]] && rm -f "${temp_file}"
    done
}

# Set up exit trap for cleanup
trap cleanup EXIT

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    exec 3>&1 4>&2  # Save stdout and stderr
    
    if [[ "${VERBOSE}" == "true" ]]; then
        exec 1> >(tee -a "${LOG_FILE}")
        exec 2> >(tee -a "${LOG_FILE}" >&2)
    else
        exec 1>>"${LOG_FILE}"
        exec 2>&1
    fi
}

# Logging functions with structured output
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
            "${timestamp}" "${level}" "${message}" | tee -a "${LOG_FILE}"
    else
        case "${level}" in
            ERROR)   echo -e "[${timestamp}] ${RED}[ERROR]${NC} ${message}" | tee -a "${LOG_FILE}" >&2 ;;
            WARN)    echo -e "[${timestamp}] ${YELLOW}[WARN]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
            SUCCESS) echo -e "[${timestamp}] ${GREEN}[SUCCESS]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
            INFO)    echo -e "[${timestamp}] ${BLUE}[INFO]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
            DEBUG)   [[ "${VERBOSE}" == "true" ]] && echo -e "[${timestamp}] ${CYAN}[DEBUG]${NC} ${message}" | tee -a "${LOG_FILE}" ;;
            *)       echo -e "[${timestamp}] ${message}" | tee -a "${LOG_FILE}" ;;
        esac
    fi
}

log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_info() { log "INFO" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Create temporary file
create_temp_file() {
    local temp_file
    temp_file=$(mktemp "${TMPDIR:-/tmp}/migrate.XXXXXX")
    TEMP_FILES+=("${temp_file}")
    echo "${temp_file}"
}

# Validate hostname format
validate_hostname() {
    local hostname="$1"
    local hostname_regex='^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$'
    
    if [[ ! "${hostname}" =~ ${hostname_regex} ]]; then
        log_error "Invalid hostname format: ${hostname}"
        return 1
    fi
    return 0
}

# Validate Kubernetes name
validate_k8s_name() {
    local name="$1"
    local k8s_name_regex='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
    
    if [[ ! "${name}" =~ ${k8s_name_regex} ]]; then
        log_error "Invalid Kubernetes name format: ${name}"
        return 1
    fi
    return 0
}

# Execute command with retry
execute_with_retry() {
    local max_attempts="${DEFAULT_RETRY_COUNT}"
    local delay="${DEFAULT_RETRY_DELAY}"
    local attempt=1
    local command="$*"
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_debug "Executing (attempt ${attempt}/${max_attempts}): ${command}"
        
        if eval "${command}"; then
            return 0
        fi
        
        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_warn "Command failed, retrying in ${delay} seconds..."
            sleep "${delay}"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after ${max_attempts} attempts: ${command}"
    return 1
}

# Check if kubectl is available and configured
check_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl command not found. Please install kubectl."
        exit 1
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    local kubectl_version
    kubectl_version=$(kubectl version --client -o json | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4)
    log_info "Using kubectl version: ${kubectl_version}"
}

# Check required tools
check_dependencies() {
    local deps=("kubectl" "curl" "jq")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing_deps+=("${dep}")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again."
        exit 1
    fi
}

# ==============================================================================
# KUBERNETES OPERATIONS
# ==============================================================================

# Safe kubectl wrapper with error handling
kubectl_safe() {
    local kubectl_args=("$@")
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        # Add dry-run flag for supported operations
        case "${kubectl_args[0]}" in
            apply|create|delete|patch)
                kubectl_args+=("--dry-run=client" "-o" "yaml")
                log_info "[DRY-RUN] kubectl ${kubectl_args[*]}"
                ;;
        esac
    fi
    
    execute_with_retry kubectl "${kubectl_args[@]}"
}

# Find Ingress by hostname with caching
find_ingress_by_host() {
    local host="$1"
    local cache_file
    cache_file=$(create_temp_file)
    
    log_debug "Searching for Ingress with host: ${host}"
    
    # Get all ingresses once and cache
    kubectl get ingress --all-namespaces -o json > "${cache_file}"
    
    # Parse with jq for better performance
    local result
    result=$(jq -r --arg host "${host}" '
        .items[] | 
        select(.spec.rules[]?.host == $host) | 
        "\(.metadata.namespace) \(.metadata.name)"
    ' "${cache_file}" | head -n1)
    
    if [[ -z "${result}" ]]; then
        log_error "No Ingress found with host: ${host}"
        return 1
    fi
    
    echo "${result}"
}

# Get Ingress details in JSON format
get_ingress_json() {
    local namespace="$1"
    local name="$2"
    
    kubectl get ingress "${name}" -n "${namespace}" -o json
}

# Backup Ingress configuration with verification
backup_ingress() {
    local namespace="$1"
    local ingress_name="$2"
    
    mkdir -p "${BACKUP_DIR}"
    
    local backup_file="${BACKUP_DIR}/${namespace}_${ingress_name}_$(date +%H%M%S).yaml"
    local checksum_file="${backup_file}.sha256"
    
    log_info "Creating backup: ${backup_file}"
    
    # Save the ingress configuration
    kubectl get ingress "${ingress_name}" -n "${namespace}" -o yaml > "${backup_file}"
    
    # Generate checksum for integrity
    sha256sum "${backup_file}" > "${checksum_file}"
    
    # Verify backup
    if [[ ! -s "${backup_file}" ]]; then
        log_error "Backup file is empty: ${backup_file}"
        return 1
    fi
    
    # Record backup in CSV
    echo "$(date -Iseconds),${namespace},${ingress_name},${backup_file}" >> "${DEFAULT_RECORDS_FILE}"
    
    log_success "Backup created successfully: ${backup_file}"
    echo "${backup_file}"
}

# Create ExternalName Service with validation
create_external_service() {
    local namespace="$1"
    local service_name="$2"
    local external_host="$3"
    
    validate_k8s_name "${service_name}" || return 1
    validate_hostname "${external_host}" || return 1
    
    local service_yaml
    service_yaml=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${service_name}
  namespace: ${namespace}
  labels:
    migration: "true"
    migration-tool: "${SCRIPT_NAME}"
    migration-version: "${SCRIPT_VERSION}"
    original-host: "${external_host}"
  annotations:
    migration/timestamp: "$(date -Iseconds)"
spec:
  type: ExternalName
  externalName: ${external_host}
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      protocol: TCP
EOF
)
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create ExternalName Service: ${namespace}/${service_name}"
        echo "${service_yaml}"
        return 0
    fi
    
    echo "${service_yaml}" | kubectl_safe apply -f -
    
    # Verify service creation
    if kubectl get service "${service_name}" -n "${namespace}" &>/dev/null; then
        log_success "ExternalName Service created: ${namespace}/${service_name}"
        return 0
    else
        log_error "Failed to create ExternalName Service: ${namespace}/${service_name}"
        return 1
    fi
}

# Update Ingress to proxy mode with enhanced annotations
update_ingress_to_proxy() {
    local namespace="$1"
    local ingress_name="$2"
    local old_host="$3"
    local new_host="$4"
    local proxy_service_name="$5"
    
    log_info "Updating Ingress ${namespace}/${ingress_name} to proxy mode"
    
    # Create patch JSON with proper escaping
    local patch_json
    patch_json=$(cat <<EOF
{
  "metadata": {
    "annotations": {
      "nginx.ingress.kubernetes.io/upstream-vhost": "${new_host}",
      "nginx.ingress.kubernetes.io/backend-protocol": "HTTP",
      "nginx.ingress.kubernetes.io/proxy-body-size": "0",
      "nginx.ingress.kubernetes.io/proxy-connect-timeout": "60",
      "nginx.ingress.kubernetes.io/proxy-send-timeout": "60",
      "nginx.ingress.kubernetes.io/proxy-read-timeout": "60",
      "nginx.ingress.kubernetes.io/proxy-set-headers": "Host ${new_host}\\nX-Real-IP \$remote_addr\\nX-Forwarded-For \$proxy_add_x_forwarded_for\\nX-Forwarded-Proto \$scheme\\nX-Original-Host \$host\\nX-Migration-Source ${old_host}",
      "migration/status": "migrated",
      "migration/source-host": "${old_host}",
      "migration/target-host": "${new_host}",
      "migration/timestamp": "$(date -Iseconds)",
      "migration/tool": "${SCRIPT_NAME}",
      "migration/version": "${SCRIPT_VERSION}"
    }
  }
}
EOF
)
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would patch Ingress: ${namespace}/${ingress_name}"
        echo "${patch_json}" | jq .
        return 0
    fi
    
    # Apply the patch
    if echo "${patch_json}" | kubectl_safe patch ingress "${ingress_name}" \
        -n "${namespace}" \
        --type=merge \
        -p "$(cat)"; then
        
        # Update backend service
        local backend_patch
        backend_patch=$(cat <<EOF
{
  "spec": {
    "rules": [{
      "host": "${old_host}",
      "http": {
        "paths": [{
          "path": "/",
          "pathType": "ImplementationSpecific",
          "backend": {
            "service": {
              "name": "${proxy_service_name}",
              "port": {
                "number": 80
              }
            }
          }
        }]
      }
    }]
  }
}
EOF
)
        
        echo "${backend_patch}" | kubectl_safe patch ingress "${ingress_name}" \
            -n "${namespace}" \
            --type=strategic \
            -p "$(cat)"
        
        log_success "Ingress updated to proxy mode: ${namespace}/${ingress_name}"
        return 0
    else
        log_error "Failed to update Ingress: ${namespace}/${ingress_name}"
        return 1
    fi
}

# ==============================================================================
# HEALTH CHECKS & VERIFICATION
# ==============================================================================

# Perform health check on migrated service
health_check() {
    local host="$1"
    local new_host="$2"
    local namespace="$3"
    local ingress_name="$4"
    
    if [[ "${HEALTH_CHECK_ENABLED}" != "true" ]]; then
        log_debug "Health checks disabled, skipping..."
        return 0
    fi
    
    log_info "Performing health checks for ${host} -> ${new_host}"
    
    # Wait for configuration to propagate
    log_debug "Waiting for configuration to propagate..."
    sleep 10
    
    # Check Ingress status
    local ingress_ip
    ingress_ip=$(kubectl get ingress "${ingress_name}" -n "${namespace}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -z "${ingress_ip}" ]]; then
        log_warn "Ingress does not have an assigned IP address yet"
    else
        log_info "Ingress IP: ${ingress_ip}"
    fi
    
    # Test HTTP connectivity (if ingress has IP)
    if [[ -n "${ingress_ip}" ]]; then
        local health_endpoint="/health"
        local response_code
        
        response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Host: ${host}" \
            --connect-timeout "${DEFAULT_HEALTH_CHECK_TIMEOUT}" \
            "http://${ingress_ip}${health_endpoint}" 2>/dev/null || echo "000")
        
        if [[ "${response_code}" == "200" ]] || [[ "${response_code}" == "204" ]]; then
            log_success "Health check passed (HTTP ${response_code})"
            return 0
        elif [[ "${response_code}" == "000" ]]; then
            log_warn "Health check timed out or connection failed"
            return 1
        else
            log_warn "Health check returned HTTP ${response_code}"
            return 1
        fi
    fi
    
    # Check nginx configuration reload
    local nginx_pod
    nginx_pod=$(kubectl get pods -n kube-system -l app=nginx-ingress -o name 2>/dev/null | head -n1)
    
    if [[ -n "${nginx_pod}" ]]; then
        log_debug "Checking nginx configuration..."
        if kubectl exec -n kube-system "${nginx_pod}" -- nginx -t &>/dev/null; then
            log_success "Nginx configuration is valid"
        else
            log_warn "Nginx configuration validation failed"
        fi
    fi
    
    return 0
}

# Verify migration status
verify_migration() {
    local host="$1"
    local new_host="$2"
    local namespace="$3"
    local ingress_name="$4"
    
    log_info "Verifying migration for ${host}"
    
    # Check annotations
    local migration_status
    migration_status=$(kubectl get ingress "${ingress_name}" -n "${namespace}" \
        -o jsonpath='{.metadata.annotations.migration/status}' 2>/dev/null || echo "")
    
    if [[ "${migration_status}" != "migrated" ]]; then
        log_error "Migration status not set correctly: ${migration_status}"
        return 1
    fi
    
    # Perform health check
    if health_check "${host}" "${new_host}" "${namespace}" "${ingress_name}"; then
        log_success "Migration verified successfully"
        return 0
    else
        log_warn "Migration completed but health checks failed"
        return 1
    fi
}

# ==============================================================================
# MAIN MIGRATION FUNCTIONS
# ==============================================================================

# Switch single Ingress
switch_ingress() {
    local old_host="$1"
    local new_host="$2"
    
    # Set current migration host for error handler
    CURRENT_MIGRATION_HOST="${old_host}"
    
    log_info "Starting migration: ${old_host} -> ${new_host}"
    
    # Validate inputs
    validate_hostname "${old_host}" || return 1
    validate_hostname "${new_host}" || return 1
    
    # Find the Ingress
    local ingress_info
    ingress_info=$(find_ingress_by_host "${old_host}") || return 1
    
    local namespace
    namespace=$(echo "${ingress_info}" | awk '{print $1}')
    local ingress_name
    ingress_name=$(echo "${ingress_info}" | awk '{print $2}')
    
    log_info "Found Ingress: ${namespace}/${ingress_name}"
    
    # Check if already migrated
    local current_status
    current_status=$(kubectl get ingress "${ingress_name}" -n "${namespace}" \
        -o jsonpath='{.metadata.annotations.migration/status}' 2>/dev/null || echo "")
    
    if [[ "${current_status}" == "migrated" ]] && [[ "${FORCE}" != "true" ]]; then
        log_warn "Ingress already migrated. Use --force to re-migrate."
        local current_target
        current_target=$(kubectl get ingress "${ingress_name}" -n "${namespace}" \
            -o jsonpath='{.metadata.annotations.migration/target-host}')
        log_info "Current target: ${current_target}"
        return 0
    fi
    
    # Create backup
    local backup_file
    if [[ "${DRY_RUN}" != "true" ]]; then
        backup_file=$(backup_ingress "${namespace}" "${ingress_name}") || return 1
    fi
    
    # Generate proxy service name
    local proxy_service_name="proxy-${old_host//[^a-zA-Z0-9]/-}"
    proxy_service_name="${proxy_service_name:0:63}"  # Kubernetes name length limit
    
    # Create ExternalName service
    create_external_service "${namespace}" "${proxy_service_name}" "${new_host}" || return 1
    
    # Update Ingress
    update_ingress_to_proxy "${namespace}" "${ingress_name}" "${old_host}" "${new_host}" "${proxy_service_name}" || return 1
    
    # Verify migration
    if [[ "${DRY_RUN}" != "true" ]]; then
        if verify_migration "${old_host}" "${new_host}" "${namespace}" "${ingress_name}"; then
            log_success "Migration completed successfully: ${old_host} -> ${new_host}"
            
            # Record successful migration
            echo "$(date -Iseconds),${namespace},${ingress_name},${old_host},${new_host},${backup_file:-N/A},migrated" \
                >> "${DEFAULT_RECORDS_FILE}"
        else
            log_warn "Migration completed with warnings: ${old_host} -> ${new_host}"
        fi
    fi
    
    # Clear current migration host
    unset CURRENT_MIGRATION_HOST
    
    return 0
}

# Rollback Ingress migration
rollback_ingress() {
    local host="$1"
    
    log_info "Starting rollback for ${host}"
    
    # Find the Ingress
    local ingress_info
    ingress_info=$(find_ingress_by_host "${host}") || return 1
    
    local namespace
    namespace=$(echo "${ingress_info}" | awk '{print $1}')
    local ingress_name
    ingress_name=$(echo "${ingress_info}" | awk '{print $2}')
    
    # Find the latest backup
    local backup_file
    backup_file=$(grep "${namespace},${ingress_name}" "${DEFAULT_RECORDS_FILE}" 2>/dev/null | \
        tail -1 | cut -d',' -f6)
    
    if [[ -z "${backup_file}" ]] || [[ ! -f "${backup_file}" ]]; then
        log_error "No backup found for ${namespace}/${ingress_name}"
        return 1
    fi
    
    # Verify backup integrity
    if [[ -f "${backup_file}.sha256" ]]; then
        if ! sha256sum -c "${backup_file}.sha256" &>/dev/null; then
            log_error "Backup file integrity check failed"
            return 1
        fi
    fi
    
    log_info "Restoring from backup: ${backup_file}"
    
    # Restore the Ingress
    if kubectl_safe apply -f "${backup_file}"; then
        log_success "Ingress restored from backup"
        
        # Clean up proxy service
        local proxy_service_name="proxy-${host//[^a-zA-Z0-9]/-}"
        proxy_service_name="${proxy_service_name:0:63}"
        
        kubectl_safe delete service "${proxy_service_name}" -n "${namespace}" 2>/dev/null || true
        
        # Update records
        echo "$(date -Iseconds),${namespace},${ingress_name},${host},rollback,${backup_file},rolled-back" \
            >> "${DEFAULT_RECORDS_FILE}"
        
        log_success "Rollback completed for ${host}"
        return 0
    else
        log_error "Failed to restore from backup"
        return 1
    fi
}

# Batch migration with parallel processing
batch_switch() {
    local config_file="$1"
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi
    
    log_info "Starting batch migration from ${config_file}"
    
    # Create temporary file for parallel processing
    local jobs_file
    jobs_file=$(create_temp_file)
    
    # Parse configuration file
    local line_num=0
    while IFS=',' read -r old_host new_host || [[ -n "${old_host}" ]]; do
        line_num=$((line_num + 1))
        
        # Skip comments and empty lines
        [[ "${old_host}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${old_host}" ]] && continue
        
        # Validate entries
        if [[ -z "${new_host}" ]]; then
            log_warn "Line ${line_num}: Missing new_host for ${old_host}, skipping"
            continue
        fi
        
        echo "${old_host},${new_host}" >> "${jobs_file}"
    done < "${config_file}"
    
    local total_jobs
    total_jobs=$(wc -l < "${jobs_file}")
    
    if [[ ${total_jobs} -eq 0 ]]; then
        log_warn "No valid migration entries found in ${config_file}"
        return 0
    fi
    
    log_info "Found ${total_jobs} migrations to process (max parallel: ${MAX_PARALLEL})"
    
    # Process migrations with controlled parallelism
    local completed=0
    local failed=0
    
    if command -v parallel &>/dev/null; then
        # Use GNU parallel if available
        export -f switch_ingress log log_info log_error log_warn log_success log_debug
        export -f validate_hostname validate_k8s_name execute_with_retry kubectl_safe
        export -f find_ingress_by_host backup_ingress create_external_service
        export -f update_ingress_to_proxy verify_migration health_check
        
        cat "${jobs_file}" | parallel -j "${MAX_PARALLEL}" --colsep ',' \
            "${SCRIPT_DIR}/${SCRIPT_NAME} switch {1} {2}"
    else
        # Fallback to xargs
        while IFS=',' read -r old_host new_host; do
            if switch_ingress "${old_host}" "${new_host}"; then
                completed=$((completed + 1))
            else
                failed=$((failed + 1))
            fi
            
            # Simple parallelism control
            while [[ $(jobs -r | wc -l) -ge ${MAX_PARALLEL} ]]; do
                sleep 1
            done
        done < "${jobs_file}"
        
        # Wait for remaining jobs
        wait
    fi
    
    log_info "Batch migration completed: ${completed} successful, ${failed} failed"
    
    return 0
}

# Check migration status
check_status() {
    local host="$1"
    
    # Find the Ingress
    local ingress_info
    ingress_info=$(find_ingress_by_host "${host}")
    
    if [[ -z "${ingress_info}" ]]; then
        log_error "No Ingress found for host: ${host}"
        return 1
    fi
    
    local namespace
    namespace=$(echo "${ingress_info}" | awk '{print $1}')
    local ingress_name
    ingress_name=$(echo "${ingress_info}" | awk '{print $2}')
    
    # Get detailed status
    local ingress_json
    ingress_json=$(get_ingress_json "${namespace}" "${ingress_name}")
    
    # Extract migration metadata
    local status target timestamp
    status=$(echo "${ingress_json}" | jq -r '.metadata.annotations."migration/status" // "not-migrated"')
    target=$(echo "${ingress_json}" | jq -r '.metadata.annotations."migration/target-host" // "N/A"')
    timestamp=$(echo "${ingress_json}" | jq -r '.metadata.annotations."migration/timestamp" // "N/A"')
    
    # Display status
    cat <<EOF
================================================================================
Migration Status Report
================================================================================
Host:            ${host}
Namespace:       ${namespace}
Ingress:         ${ingress_name}
Migration Status: ${status}
Target Host:     ${target}
Migration Time:  ${timestamp}

Ingress Details:
$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o wide)

Service Backend:
$(kubectl get service -n "${namespace}" -l migration=true 2>/dev/null || echo "No migration services found")
================================================================================
EOF
    
    return 0
}

# List all migrations
list_migrations() {
    if [[ ! -f "${DEFAULT_RECORDS_FILE}" ]]; then
        log_info "No migration records found"
        return 0
    fi
    
    echo "================================================================================
Migration Records
================================================================================"
    
    # Format and display records
    echo "Timestamp,Namespace,Ingress,Source,Target,Backup,Status"
    column -t -s',' "${DEFAULT_RECORDS_FILE}"
    
    echo ""
    echo "Total migrations: $(wc -l < "${DEFAULT_RECORDS_FILE}")"
    echo "================================================================================"
    
    return 0
}

# ==============================================================================
# USAGE & HELP
# ==============================================================================

usage() {
    cat <<EOF
${GREEN}Kubernetes Ingress Migration Tool v${SCRIPT_VERSION}${NC}

${CYAN}USAGE:${NC}
    ${SCRIPT_NAME} [OPTIONS] COMMAND [ARGUMENTS]

${CYAN}COMMANDS:${NC}
    switch <old-host> <new-host>    Migrate single host
    batch <config-file>             Batch migration from CSV file
    rollback <host>                 Rollback migration for host
    status <host>                   Check migration status
    list                           List all migration records
    help                           Show this help message

${CYAN}OPTIONS:${NC}
    -d, --dry-run          Preview changes without applying
    -v, --verbose          Enable verbose output
    -f, --force            Force migration even if already migrated
    -p, --parallel <N>     Max parallel operations (default: ${DEFAULT_MAX_PARALLEL})
    --no-health-check      Skip health checks after migration
    --no-rollback          Disable automatic rollback on error
    --json                 Output logs in JSON format
    -h, --help            Show this help message

${CYAN}EXAMPLES:${NC}
    # Single host migration
    ${SCRIPT_NAME} switch api.old.example.com api.new.example.com

    # Batch migration with dry-run
    ${SCRIPT_NAME} --dry-run batch migration-list.csv

    # Check status
    ${SCRIPT_NAME} status api.old.example.com

    # Rollback migration
    ${SCRIPT_NAME} rollback api.old.example.com

${CYAN}CSV FORMAT:${NC}
    old_host,new_host
    api1.old.example.com,api1.new.example.com
    api2.old.example.com,api2.new.example.com

${CYAN}ENVIRONMENT VARIABLES:${NC}
    KUBECONFIG          Path to kubeconfig file
    MIGRATION_LOG_DIR   Override default log directory
    MIGRATION_BACKUP_DIR Override default backup directory

For more information, see: https://github.com/your-org/k8s-migration-tool
EOF
}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -p|--parallel)
                MAX_PARALLEL="$2"
                shift 2
                ;;
            --no-health-check)
                HEALTH_CHECK_ENABLED=false
                shift
                ;;
            --no-rollback)
                ROLLBACK_ON_ERROR=false
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help|help)
                usage
                exit 0
                ;;
            switch|rollback|status|batch|list)
                break
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check command
    if [[ $# -eq 0 ]]; then
        log_error "No command specified"
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Initialize
    mkdir -p "${DEFAULT_LOG_DIR}" "${DEFAULT_BACKUP_DIR}"
    touch "${DEFAULT_RECORDS_FILE}"
    init_logging
    
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    [[ "${DRY_RUN}" == "true" ]] && log_warn "DRY-RUN MODE ENABLED - No changes will be applied"
    
    # Check dependencies
    check_dependencies
    check_kubectl
    
    # Execute command
    case "${command}" in
        switch)
            if [[ $# -ne 2 ]]; then
                log_error "Invalid arguments for 'switch' command"
                usage
                exit 1
            fi
            switch_ingress "$1" "$2"
            ;;
        batch)
            if [[ $# -ne 1 ]]; then
                log_error "Invalid arguments for 'batch' command"
                usage
                exit 1
            fi
            batch_switch "$1"
            ;;
        rollback)
            if [[ $# -ne 1 ]]; then
                log_error "Invalid arguments for 'rollback' command"
                usage
                exit 1
            fi
            rollback_ingress "$1"
            ;;
        status)
            if [[ $# -ne 1 ]]; then
                log_error "Invalid arguments for 'status' command"
                usage
                exit 1
            fi
            check_status "$1"
            ;;
        list)
            list_migrations
            ;;
        *)
            log_error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
    
    local exit_code=$?
    
    if [[ ${exit_code} -eq 0 ]]; then
        log_success "Operation completed successfully"
    else
        log_error "Operation failed with exit code: ${exit_code}"
    fi
    
    exit ${exit_code}
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
