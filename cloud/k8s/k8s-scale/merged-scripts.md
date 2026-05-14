# Shell Scripts Collection

Generated on: 2025-12-05 09:35:06
Directory: /Users/lex/git/knowledge/k8s/k8s-scale

## `optimize_k8s_resources_v2.sh`

```bash
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

```

## `optimize_k8s_resources.sh`

```bash
#!/bin/bash

# Default values
NAMESPACE=""
DRY_RUN=false
APPLY=false
RESTORE=false
MOCK_FILE=""

# Helper function for logging
log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --apply) APPLY=true ;;
        --restore) RESTORE=true ;;
        --mock-file) MOCK_FILE="$2"; shift ;;
        *) error "Unknown parameter passed: $1" ;;
    esac
    shift
done

if [[ -z "$NAMESPACE" ]]; then
    error "--namespace is required"
fi

# Function to run kubectl
run_kubectl() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] kubectl $@"
    else
        kubectl "$@"
    fi
}

# Function to convert CPU to millicores using awk
convert_cpu() {
    local val=$1
    if [[ -z "$val" || "$val" == "null" ]]; then echo 0; return; fi
    
    echo "$val" | awk '{
        if ($0 ~ /m$/) {
            sub(/m/, "", $0);
            print int($0)
        } else {
            print int($0 * 1000)
        }
    }'
}

# Function to convert Memory to MiB using awk
convert_mem() {
    local val=$1
    if [[ -z "$val" || "$val" == "null" ]]; then echo 0; return; fi
    
    echo "$val" | awk '{
        if ($0 ~ /Ki$/) { sub(/Ki/, "", $0); print int($0 / 1024) }
        else if ($0 ~ /Mi$/) { sub(/Mi/, "", $0); print int($0) }
        else if ($0 ~ /Gi$/) { sub(/Gi/, "", $0); print int($0 * 1024) }
        else if ($0 ~ /Ti$/) { sub(/Ti/, "", $0); print int($0 * 1024 * 1024) }
        else if ($0 ~ /^[0-9]+$/) { print int($0 / 1024 / 1024) } # Bytes
        else { print 0 } # Fallback/Unknown
    }'
}

# Function to format CPU back to string
format_cpu() {
    local val=$1
    awk -v val="$val" 'BEGIN {
        if (val >= 1000 && val % 1000 == 0) {
            print (val / 1000)
        } else {
            print val "m"
        }
    }'
}

# Function to format Memory back to string
format_mem() {
    local val=$1
    awk -v val="$val" 'BEGIN {
        if (val >= 1024 && val % 1024 == 0) {
            print (val / 1024) "Gi"
        } else {
            print val "Mi"
        }
    }'
}

# --- RESTORE MODE ---
if [[ "$RESTORE" == "true" ]]; then
    log "Restoring deployments in namespace $NAMESPACE..."
    
    # Get deployments with the annotation
    # We need to fetch all and filter because label selectors don't work on annotations easily in one go without complex jsonpath
    if [[ -n "$MOCK_FILE" ]]; then
        JSON_INPUT=$(cat "$MOCK_FILE")
    else
        JSON_INPUT=$(kubectl get deploy -n "$NAMESPACE" -o json)
    fi

    echo "$JSON_INPUT" | jq -r '.items[] | select(.metadata.annotations["x-optimization/original-replicas"] != null) | .metadata.name + " " + .metadata.annotations["x-optimization/original-replicas"]' | while read -r name original_replicas; do
        log "Restoring $name to $original_replicas replicas..."
        run_kubectl scale deploy "$name" -n "$NAMESPACE" --replicas="$original_replicas"
        run_kubectl annotate deploy "$name" -n "$NAMESPACE" x-optimization/original-replicas-
    done
    exit 0
fi

# --- ANALYSIS MODE ---

log "Fetching deployments..."
if [[ -n "$MOCK_FILE" ]]; then
    JSON_INPUT=$(cat "$MOCK_FILE")
else
    JSON_INPUT=$(kubectl get deploy -n "$NAMESPACE" -o json)
fi

# Initialize totals
STATS_FILE=$(mktemp)
echo "0 0 0 0" > "$STATS_FILE"

# Temporary file for unhealthy deployments
UNHEALTHY_FILE=$(mktemp)

# Process each deployment
# We use jq to output a flat list of objects, then read them line by line
# Note: jq -c produces one JSON object per line
echo "$JSON_INPUT" | jq -c '.items[]' | while read -r deploy; do
    NAME=$(echo "$deploy" | jq -r '.metadata.name')
    REPLICAS=$(echo "$deploy" | jq -r '.spec.replicas // 0')
    READY=$(echo "$deploy" | jq -r '.status.readyReplicas // 0')
    
    POD_CPU=0
    POD_MEM=0
    
    RESOURCES=$(echo "$deploy" | jq -c '.spec.template.spec.containers[].resources')
    while read -r res; do
        L_CPU=$(echo "$res" | jq -r '.limits.cpu // empty')
        R_CPU=$(echo "$res" | jq -r '.requests.cpu // empty')
        L_MEM=$(echo "$res" | jq -r '.limits.memory // empty')
        R_MEM=$(echo "$res" | jq -r '.requests.memory // empty')
        
        CPU_STR="${L_CPU:-$R_CPU}"
        MEM_STR="${L_MEM:-$R_MEM}"
        
        C_CPU=$(convert_cpu "$CPU_STR")
        C_MEM=$(convert_mem "$MEM_STR")
        
        POD_CPU=$((POD_CPU + C_CPU))
        POD_MEM=$((POD_MEM + C_MEM))
    done <<< "$(echo "$RESOURCES")"
    
    DEPLOY_TOTAL_CPU=$((POD_CPU * REPLICAS))
    DEPLOY_TOTAL_MEM=$((POD_MEM * REPLICAS))
    
    # Read current stats
    read T_CPU T_MEM R_CPU R_MEM < "$STATS_FILE"
    
    T_CPU=$((T_CPU + DEPLOY_TOTAL_CPU))
    T_MEM=$((T_MEM + DEPLOY_TOTAL_MEM))
    
    if [[ "$REPLICAS" -gt 0 && "$READY" -eq 0 ]]; then
        echo "$NAME $REPLICAS $DEPLOY_TOTAL_CPU $DEPLOY_TOTAL_MEM" >> "$UNHEALTHY_FILE"
    else
        R_CPU=$((R_CPU + DEPLOY_TOTAL_CPU))
        R_MEM=$((R_MEM + DEPLOY_TOTAL_MEM))
    fi
    
    echo "$T_CPU $T_MEM $R_CPU $R_MEM" > "$STATS_FILE"
done

read TOTAL_CPU TOTAL_MEM RUNNING_CPU RUNNING_MEM < "$STATS_FILE"
rm "$STATS_FILE"

# --- REPORT ---

SAVING_CPU=$((TOTAL_CPU - RUNNING_CPU))
SAVING_MEM=$((TOTAL_MEM - RUNNING_MEM))

echo ""
echo "========================================"
echo "Resource Optimization Report for Namespace: $NAMESPACE"
echo "========================================"
printf "%-20s | %-10s | %-10s\n" "Metric" "CPU" "Memory"
echo "----------------------------------------------"
printf "%-20s | %-10s | %-10s\n" "Total Requested" "$(format_cpu $TOTAL_CPU)" "$(format_mem $TOTAL_MEM)"
printf "%-20s | %-10s | %-10s\n" "Running (Healthy)" "$(format_cpu $RUNNING_CPU)" "$(format_mem $RUNNING_MEM)"
printf "%-20s | %-10s | %-10s\n" "Potential Savings" "$(format_cpu $SAVING_CPU)" "$(format_mem $SAVING_MEM)"

echo ""
echo "Unhealthy Deployments (Candidates for Scale Down):"
if [[ ! -s "$UNHEALTHY_FILE" ]]; then
    echo "  None found."
else
    while read -r name replicas cpu mem; do
        echo "  - $name: $replicas replicas (Saving: $(format_cpu $cpu) CPU, $(format_mem $mem) Mem)"
    done < "$UNHEALTHY_FILE"
fi

# --- APPLY ---

if [[ "$APPLY" == "true" && -s "$UNHEALTHY_FILE" ]]; then
    echo ""
    echo "--- Scaling Down Unhealthy Deployments ---"
    while read -r name replicas cpu mem; do
        log "Scaling down $name (was $replicas replicas)..."
        run_kubectl annotate deploy "$name" -n "$NAMESPACE" "x-optimization/original-replicas=$replicas" --overwrite
        run_kubectl scale deploy "$name" -n "$NAMESPACE" --replicas=0
    done < "$UNHEALTHY_FILE"
elif [[ "$APPLY" == "true" ]]; then
    echo ""
    echo "No unhealthy deployments to scale down."
fi

# --- QUOTA ---

if [[ "$APPLY" == "true" ]]; then
    # Calculate buffer (10%)
    LIMIT_CPU=$(awk -v val="$RUNNING_CPU" 'BEGIN { print int(val * 1.1) }')
    LIMIT_MEM=$(awk -v val="$RUNNING_MEM" 'BEGIN { print int(val * 1.1) }')
    
    F_CPU=$(format_cpu $LIMIT_CPU)
    F_MEM=$(format_mem $LIMIT_MEM)
    
    echo ""
    echo "--- Recommended ResourceQuota ---"
    cat <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${NAMESPACE}-optimization-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "$F_CPU"
    requests.memory: "$F_MEM"
    limits.cpu: "$F_CPU"
    limits.memory: "$F_MEM"
EOF
    echo ""
    echo "(Save this to a file and apply with 'kubectl apply -f ...')"
else
    echo ""
    echo "[INFO] Run with --apply to scale down unhealthy deployments and generate quota."
fi

rm "$UNHEALTHY_FILE"

```

