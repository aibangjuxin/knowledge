# Shell Scripts Collection

Generated on: 2025-12-05 09:17:08
Directory: /Users/lex/git/knowledge/k8s/k8s-scale

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

