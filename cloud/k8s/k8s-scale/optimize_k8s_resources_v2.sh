#!/bin/bash

# Kubernetes Resource Optimization Script
# Purpose: Analyze and optimize resource usage by scaling down unhealthy deployments
# and generating ResourceQuota based on healthy workloads

set -euo pipefail

# Default values
NAMESPACE=""
DRY_RUN=false
APPLY=false
RESTORE=false
BUFFER_PERCENT=10
OUTPUT_DIR="./k8s-optimization-reports"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 --namespace <namespace> [OPTIONS]

Required:
  --namespace <name>        Kubernetes namespace to analyze

Options:
  --dry-run                 Show what would be done without making changes
  --apply                   Apply changes (scale down unhealthy deployments)
  --restore                 Restore previously scaled down deployments
  --buffer <percent>        Buffer percentage for quota (default: 10)
  --output-dir <path>       Directory for reports (default: ./k8s-optimization-reports)
  --help                    Show this help message

Examples:
  # Analyze namespace
  $0 --namespace my-app

  # Apply changes with dry-run first
  $0 --namespace my-app --dry-run
  $0 --namespace my-app --apply

  # Restore scaled down deployments
  $0 --namespace my-app --restore

EOF
    exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --apply) APPLY=true ;;
        --restore) RESTORE=true ;;
        --buffer) BUFFER_PERCENT="$2"; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift ;;
        --help) usage ;;
        *) error "Unknown parameter: $1. Use --help for usage." ;;
    esac
    shift
done

# Validate inputs
[[ -z "$NAMESPACE" ]] && error "--namespace is required. Use --help for usage."

# Check kubectl
command -v kubectl >/dev/null 2>&1 || error "kubectl is not installed"
command -v jq >/dev/null 2>&1 || error "jq is not installed"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Timestamp for reports
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$OUTPUT_DIR/${NAMESPACE}_report_${TIMESTAMP}.txt"

# Function to run kubectl with dry-run support
run_kubectl() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY-RUN]${NC} kubectl $*"
    else
        kubectl "$@"
    fi
}

# ============================================================================
# RESTORE MODE
# ============================================================================
if [[ "$RESTORE" == "true" ]]; then
    log "Restoring deployments in namespace: $NAMESPACE"
    
    DEPLOYMENTS=$(kubectl get deploy -n "$NAMESPACE" \
        -o json | jq -r '.items[] | 
        select(.metadata.annotations["k8s-optimizer/original-replicas"] != null) | 
        "\(.metadata.name) \(.metadata.annotations["k8s-optimizer/original-replicas"])"')
    
    if [[ -z "$DEPLOYMENTS" ]]; then
        log "No deployments found with restoration annotation"
        exit 0
    fi
    
    echo "$DEPLOYMENTS" | while read -r name replicas; do
        log "Restoring $name to $replicas replicas"
        run_kubectl scale deploy "$name" -n "$NAMESPACE" --replicas="$replicas"
        run_kubectl annotate deploy "$name" -n "$NAMESPACE" k8s-optimizer/original-replicas-
    done
    
    log "Restore completed"
    exit 0
fi

# ============================================================================
# ANALYSIS MODE
# ============================================================================

log "Analyzing namespace: $NAMESPACE"

# Fetch all deployments in one call
DEPLOYMENTS_JSON=$(kubectl get deploy -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')

# Check if namespace has deployments
DEPLOY_COUNT=$(echo "$DEPLOYMENTS_JSON" | jq '.items | length')
if [[ "$DEPLOY_COUNT" -eq 0 ]]; then
    warn "No deployments found in namespace: $NAMESPACE"
    exit 0
fi

log "Found $DEPLOY_COUNT deployments"

# Process all deployments with a single jq call for efficiency
ANALYSIS=$(echo "$DEPLOYMENTS_JSON" | jq -r '
.items[] | 
{
    name: .metadata.name,
    replicas: (.spec.replicas // 0),
    ready: (.status.readyReplicas // 0),
    available: (.status.availableReplicas // 0),
    containers: [
        .spec.template.spec.containers[] | {
            name: .name,
            cpu_limit: (.resources.limits.cpu // .resources.requests.cpu // "0"),
            mem_limit: (.resources.limits.memory // .resources.requests.memory // "0")
        }
    ]
} | 
"\(.name)|\(.replicas)|\(.ready)|\(.available)|\(.containers | @json)"
')

# Initialize counters
TOTAL_CPU_MILLI=0
TOTAL_MEM_MI=0
HEALTHY_CPU_MILLI=0
HEALTHY_MEM_MI=0
UNHEALTHY_DEPLOYS=()
HEALTHY_DEPLOYS=()

# Helper function to convert CPU to millicores
cpu_to_milli() {
    local val="$1"
    if [[ "$val" =~ ^([0-9.]+)m$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1)}'
    elif [[ "$val" =~ ^([0-9.]+)$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1 * 1000)}'
    else
        echo "0"
    fi
}

# Helper function to convert memory to MiB
mem_to_mi() {
    local val="$1"
    if [[ "$val" =~ ^([0-9.]+)Ki$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1 / 1024)}'
    elif [[ "$val" =~ ^([0-9.]+)Mi$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1)}'
    elif [[ "$val" =~ ^([0-9.]+)Gi$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1 * 1024)}'
    elif [[ "$val" =~ ^([0-9.]+)Ti$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1 * 1024 * 1024)}'
    elif [[ "$val" =~ ^([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{print int($1 / 1024 / 1024)}'
    else
        echo "0"
    fi
}

# Format CPU from millicores
format_cpu() {
    local milli=$1
    if (( milli >= 1000 && milli % 1000 == 0 )); then
        echo "$((milli / 1000))"
    else
        echo "${milli}m"
    fi
}

# Format memory from MiB
format_mem() {
    local mi=$1
    if (( mi >= 1024 && mi % 1024 == 0 )); then
        echo "$((mi / 1024))Gi"
    else
        echo "${mi}Mi"
    fi
}

# Process each deployment
while IFS='|' read -r name replicas ready available containers_json; do
    # Calculate per-pod resources
    pod_cpu_milli=0
    pod_mem_mi=0
    
    while read -r container; do
        cpu_limit=$(echo "$container" | jq -r '.cpu_limit')
        mem_limit=$(echo "$container" | jq -r '.mem_limit')
        
        cpu_milli=$(cpu_to_milli "$cpu_limit")
        mem_mi=$(mem_to_mi "$mem_limit")
        
        pod_cpu_milli=$((pod_cpu_milli + cpu_milli))
        pod_mem_mi=$((pod_mem_mi + mem_mi))
    done < <(echo "$containers_json" | jq -c '.[]')
    
    # Calculate total for this deployment
    deploy_cpu_milli=$((pod_cpu_milli * replicas))
    deploy_mem_mi=$((pod_mem_mi * replicas))
    
    TOTAL_CPU_MILLI=$((TOTAL_CPU_MILLI + deploy_cpu_milli))
    TOTAL_MEM_MI=$((TOTAL_MEM_MI + deploy_mem_mi))
    
    # Determine health status
    # Unhealthy: has replicas but none are ready
    if [[ "$replicas" -gt 0 && "$ready" -eq 0 ]]; then
        UNHEALTHY_DEPLOYS+=("$name|$replicas|$deploy_cpu_milli|$deploy_mem_mi")
    else
        HEALTHY_CPU_MILLI=$((HEALTHY_CPU_MILLI + deploy_cpu_milli))
        HEALTHY_MEM_MI=$((HEALTHY_MEM_MI + deploy_mem_mi))
        HEALTHY_DEPLOYS+=("$name|$replicas|$ready|$deploy_cpu_milli|$deploy_mem_mi")
    fi
done <<< "$ANALYSIS"

# Calculate savings
SAVING_CPU_MILLI=$((TOTAL_CPU_MILLI - HEALTHY_CPU_MILLI))
SAVING_MEM_MI=$((TOTAL_MEM_MI - HEALTHY_MEM_MI))

# Calculate recommended quota with buffer
QUOTA_CPU_MILLI=$(awk -v val="$HEALTHY_CPU_MILLI" -v buf="$BUFFER_PERCENT" 'BEGIN {print int(val * (1 + buf/100))}')
QUOTA_MEM_MI=$(awk -v val="$HEALTHY_MEM_MI" -v buf="$BUFFER_PERCENT" 'BEGIN {print int(val * (1 + buf/100))}')

# ============================================================================
# GENERATE REPORT
# ============================================================================

{
    echo "========================================================================"
    echo "Kubernetes Resource Optimization Report"
    echo "========================================================================"
    echo "Namespace:       $NAMESPACE"
    echo "Timestamp:       $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Total Deploys:   $DEPLOY_COUNT"
    echo "Healthy Deploys: ${#HEALTHY_DEPLOYS[@]}"
    echo "Unhealthy:       ${#UNHEALTHY_DEPLOYS[@]}"
    echo ""
    echo "========================================================================"
    echo "Resource Summary"
    echo "========================================================================"
    printf "%-25s | %15s | %15s\n" "Metric" "CPU" "Memory"
    echo "------------------------------------------------------------------------"
    printf "%-25s | %15s | %15s\n" "Total Requested" "$(format_cpu $TOTAL_CPU_MILLI)" "$(format_mem $TOTAL_MEM_MI)"
    printf "%-25s | %15s | %15s\n" "Healthy (Running)" "$(format_cpu $HEALTHY_CPU_MILLI)" "$(format_mem $HEALTHY_MEM_MI)"
    printf "%-25s | %15s | %15s\n" "Potential Savings" "$(format_cpu $SAVING_CPU_MILLI)" "$(format_mem $SAVING_MEM_MI)"
    printf "%-25s | %15s | %15s\n" "Recommended Quota (+${BUFFER_PERCENT}%)" "$(format_cpu $QUOTA_CPU_MILLI)" "$(format_mem $QUOTA_MEM_MI)"
    echo ""
    
    if [[ ${#UNHEALTHY_DEPLOYS[@]} -gt 0 ]]; then
        echo "========================================================================"
        echo "Unhealthy Deployments (Scale Down Candidates)"
        echo "========================================================================"
        printf "%-40s | %8s | %15s | %15s\n" "Deployment" "Replicas" "CPU" "Memory"
        echo "------------------------------------------------------------------------"
        for deploy in "${UNHEALTHY_DEPLOYS[@]}"; do
            IFS='|' read -r name replicas cpu mem <<< "$deploy"
            printf "%-40s | %8s | %15s | %15s\n" "$name" "$replicas" "$(format_cpu $cpu)" "$(format_mem $mem)"
        done
        echo ""
    else
        echo "✓ No unhealthy deployments found"
        echo ""
    fi
    
    if [[ ${#HEALTHY_DEPLOYS[@]} -gt 0 ]]; then
        echo "========================================================================"
        echo "Healthy Deployments"
        echo "========================================================================"
        printf "%-40s | %8s | %8s | %15s | %15s\n" "Deployment" "Replicas" "Ready" "CPU" "Memory"
        echo "------------------------------------------------------------------------"
        for deploy in "${HEALTHY_DEPLOYS[@]}"; do
            IFS='|' read -r name replicas ready cpu mem <<< "$deploy"
            printf "%-40s | %8s | %8s | %15s | %15s\n" "$name" "$replicas" "$ready" "$(format_cpu $cpu)" "$(format_mem $mem)"
        done
        echo ""
    fi
    
} | tee "$REPORT_FILE"

log "Report saved to: $REPORT_FILE"

# ============================================================================
# APPLY CHANGES
# ============================================================================

if [[ "$APPLY" == "true" && ${#UNHEALTHY_DEPLOYS[@]} -gt 0 ]]; then
    echo ""
    echo "========================================================================"
    echo "Scaling Down Unhealthy Deployments"
    echo "========================================================================"
    
    for deploy in "${UNHEALTHY_DEPLOYS[@]}"; do
        IFS='|' read -r name replicas cpu mem <<< "$deploy"
        log "Scaling down: $name (was $replicas replicas)"
        run_kubectl annotate deploy "$name" -n "$NAMESPACE" \
            "k8s-optimizer/original-replicas=$replicas" \
            "k8s-optimizer/scaled-down-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --overwrite
        run_kubectl scale deploy "$name" -n "$NAMESPACE" --replicas=0
    done
    
    log "Scale down completed"
fi

# ============================================================================
# GENERATE RESOURCEQUOTA YAML
# ============================================================================

QUOTA_FILE="$OUTPUT_DIR/${NAMESPACE}_quota_${TIMESTAMP}.yaml"

cat > "$QUOTA_FILE" <<EOF
# Generated ResourceQuota for namespace: $NAMESPACE
# Based on healthy deployments with ${BUFFER_PERCENT}% buffer
# Generated at: $(date '+%Y-%m-%d %H:%M:%S')
#
# Healthy CPU:    $(format_cpu $HEALTHY_CPU_MILLI)
# Healthy Memory: $(format_mem $HEALTHY_MEM_MI)
# Buffer:         ${BUFFER_PERCENT}%
#
# Apply with: kubectl apply -f $QUOTA_FILE

apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${NAMESPACE}-resource-quota
  namespace: ${NAMESPACE}
  labels:
    managed-by: k8s-optimizer
    created-at: "${TIMESTAMP}"
spec:
  hard:
    requests.cpu: "$(format_cpu $QUOTA_CPU_MILLI)"
    requests.memory: "$(format_mem $QUOTA_MEM_MI)"
    limits.cpu: "$(format_cpu $QUOTA_CPU_MILLI)"
    limits.memory: "$(format_mem $QUOTA_MEM_MI)"
EOF

echo ""
echo "========================================================================"
echo "ResourceQuota Generated"
echo "========================================================================"
cat "$QUOTA_FILE"
echo ""
log "ResourceQuota saved to: $QUOTA_FILE"
echo ""

if [[ "$APPLY" == "true" ]]; then
    log "To apply the quota, run:"
    echo "  kubectl apply -f $QUOTA_FILE"
elif [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY-RUN mode: No changes were made"
    log "To apply changes, run:"
    echo "  $0 --namespace $NAMESPACE --apply"
else
    log "Analysis complete. To apply changes, run:"
    echo "  $0 --namespace $NAMESPACE --apply"
fi

echo ""
log "To restore scaled down deployments later, run:"
echo "  $0 --namespace $NAMESPACE --restore"
