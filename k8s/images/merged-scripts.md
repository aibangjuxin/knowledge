```bash
#!/usr/bin/env bash
# k8s-image-replace.sh
# Replace images in Kubernetes deployments
# Usage: ./k8s-image-replace.sh -i <search-keyword> [-n namespace]
# Note: -i parameter is used to search matching images, actual replacement will prompt for complete target image name

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Show help
show_help() {
    cat << EOF
Usage: $0 -i <search-keyword> [-n namespace] [-h]

Parameters:
  -i, --image      Search keyword (required) e.g.: myapp or myapp:v1.2
  -n, --namespace  Specify namespace (optional, default search all namespaces)
  -h, --help       Show help information

Description:
  -i parameter is used to search matching image names, supports partial matching
  During actual replacement, you will be prompted to enter complete target image name (with tag)

Examples:
  $0 -i myapp                    # Search images containing myapp
  $0 -i myapp:v1.2 -n production # Search in production namespace
EOF
}

# Parse arguments
IMAGE=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check required parameters
if [[ -z "$IMAGE" ]]; then
    error "Search keyword parameter is required"
    show_help
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found, please ensure it's installed and in PATH"
    exit 1
fi

# Check kubectl connection
if ! kubectl cluster-info &> /dev/null; then
    error "Unable to connect to Kubernetes cluster"
    exit 1
fi

# Extract image name (without tag)
IMAGE_NAME="${IMAGE%:*}"
IMAGE_TAG="${IMAGE##*:}"

log "Search keyword: $IMAGE"
log "Image name part: $IMAGE_NAME"
if [[ "$IMAGE" == *:* ]]; then
    log "Tag part: $IMAGE_TAG"
fi

# Build kubectl command arguments
if [[ -n "$NAMESPACE" ]]; then
    NS_ARG="-n $NAMESPACE"
    log "Search namespace: $NAMESPACE"
else
    NS_ARG="-A"
    log "Search all namespaces"
fi

echo
log "Searching for matching deployments..."

# Get all deployments and their image information
DEPLOYMENTS=$(kubectl get deployments $NS_ARG -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"="}{.image}{";"}{end}{"\n"}{end}' 2>/dev/null)

if [[ -z "$DEPLOYMENTS" ]]; then
    warn "No deployments found"
    exit 0
fi

# Find matching deployments
MATCHED_NS=()
MATCHED_DEPLOY=()
MATCHED_CONTAINER=()
MATCHED_IMAGE=()

while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    
    # Parse line: namespace|deployment|container1=image1;container2=image2;
    ns="${line%%|*}"
    rest="${line#*|}"
    deploy="${rest%%|*}"
    containers="${rest#*|}"
    
    # Parse containers and images
    IFS=';' read -ra container_pairs <<< "$containers"
    for pair in "${container_pairs[@]}"; do
        if [[ -z "$pair" ]]; then continue; fi
        
        container="${pair%%=*}"
        image="${pair#*=}"
        current_image_name="${image%:*}"
        
        # Check if image name matches (supports partial matching)
        if [[ "$current_image_name" == *"$IMAGE_NAME"* ]] || [[ "$IMAGE_NAME" == *"$current_image_name"* ]]; then
            MATCHED_NS+=("$ns")
            MATCHED_DEPLOY+=("$deploy")
            MATCHED_CONTAINER+=("$container")
            MATCHED_IMAGE+=("$image")
        fi
    done
done <<< "$DEPLOYMENTS"

# Display matching results
if [[ ${#MATCHED_NS[@]} -eq 0 ]]; then
    warn "No matching deployments found"
    exit 0
fi

echo
success "Found ${#MATCHED_NS[@]} matching deployment(s):"
echo
printf "%-4s %-20s %-30s %-20s %-40s\n" "No." "Namespace" "Deployment" "Container" "Current Image"
printf "%-4s %-20s %-30s %-20s %-40s\n" "----" "---------" "----------" "---------" "-------------"

for i in "${!MATCHED_NS[@]}"; do
    printf "%-4d %-20s %-30s %-20s %-40s\n" $((i+1)) "${MATCHED_NS[i]}" "${MATCHED_DEPLOY[i]}" "${MATCHED_CONTAINER[i]}" "${MATCHED_IMAGE[i]}"
done

echo
echo "Please select deployments to update:"
echo "  Enter numbers (e.g.: 1,3,5 or 1-3)"
echo "  Enter 'all' to select all"
echo "  Enter 'q' to quit"
echo

read -p "Please select: " selection

case "$selection" in
    q|Q)
        log "User cancelled operation"
        exit 0
        ;;
    all|ALL)
        SELECTED_INDICES=($(seq 0 $((${#MATCHED_NS[@]} - 1))))
        ;;
    *)
        # Parse user input numbers
        SELECTED_INDICES=()
        IFS=',' read -ra selections <<< "$selection"
        for sel in "${selections[@]}"; do
            # Handle range (e.g. 1-3)
            if [[ "$sel" == *-* ]]; then
                start="${sel%-*}"
                end="${sel#*-}"
                for ((j=start; j<=end; j++)); do
                    if [[ $j -ge 1 && $j -le ${#MATCHED_NS[@]} ]]; then
                        SELECTED_INDICES+=($((j-1)))
                    fi
                done
            else
                # Single number
                if [[ "$sel" =~ ^[0-9]+$ ]] && [[ $sel -ge 1 && $sel -le ${#MATCHED_NS[@]} ]]; then
                    SELECTED_INDICES+=($((sel-1)))
                fi
            fi
        done
        ;;
esac

if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
    warn "No deployment selected"
    exit 0
fi

# Display operations to be performed
echo
log "Will perform the following update operations:"
for idx in "${SELECTED_INDICES[@]}"; do
    echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> ?"
done

echo
log "Please enter complete target image name (with tag):"
log "Hint: Current search keyword is: $IMAGE"
echo
read -p "Target image: " FINAL_IMAGE

if [[ -z "$FINAL_IMAGE" ]]; then
    error "Target image cannot be empty"
    exit 1
fi

# Display final replacement plan
echo
log "Final replacement plan:"
for idx in "${SELECTED_INDICES[@]}"; do
    echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> $FINAL_IMAGE"
done

echo
read -p "Confirm execution? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "User cancelled operation"
    exit 0
fi

# Execute update
echo
log "Starting image update..."

for idx in "${SELECTED_INDICES[@]}"; do
    ns="${MATCHED_NS[idx]}"
    deploy="${MATCHED_DEPLOY[idx]}"
    container="${MATCHED_CONTAINER[idx]}"
    
    log "Updating container $container in $ns/$deploy..."
    
    if kubectl set image deployment/"$deploy" "$container"="$FINAL_IMAGE" -n "$ns" --record; then
        success "✓ $ns/$deploy updated successfully"
        
        # Wait for rollout completion
        log "Waiting for $ns/$deploy rollout to complete..."
        if kubectl rollout status deployment/"$deploy" -n "$ns" --timeout=30s; then
            success "✓ $ns/$deploy rollout completed"
        else
            error "✗ $ns/$deploy rollout timeout or failed"
            warn "To rollback, execute: kubectl rollout undo deployment/$deploy -n $ns"
        fi
    else
        error "✗ $ns/$deploy update failed"
    fi
    echo
done

success "Image update operation completed!"

# Display updated namespace image information
echo
log "Displaying updated image information..."

# Collect all involved namespaces
UPDATED_NAMESPACES=()
for idx in "${SELECTED_INDICES[@]}"; do
    ns="${MATCHED_NS[idx]}"
    # Check if already in the list
    if [[ ! " ${UPDATED_NAMESPACES[*]} " =~ " ${ns} " ]]; then
        UPDATED_NAMESPACES+=("$ns")
    fi
done

# Display all deployment image information for each namespace
for ns in "${UPDATED_NAMESPACES[@]}"; do
    echo
    success "All Deployment image information in namespace '$ns':"
    echo
    
    # Get all deployments and their images in this namespace
    ALL_DEPLOYMENTS=$(kubectl get deployments -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"="}{.image}{";"}{end}{"\n"}{end}' 2>/dev/null)
    
    if [[ -z "$ALL_DEPLOYMENTS" ]]; then
        warn "No deployments found in namespace '$ns'"
        continue
    fi
    
    printf "  %-30s %-20s %-50s\n" "Deployment" "Container" "Image"
    printf "  %-30s %-20s %-50s\n" "----------" "---------" "-----"
    
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        
        # Parse line: deployment|container1=image1;container2=image2;
        deploy="${line%%|*}"
        containers="${line#*|}"
        
        # Parse containers and images
        IFS=';' read -ra container_pairs <<< "$containers"
        for pair in "${container_pairs[@]}"; do
            if [[ -z "$pair" ]]; then continue; fi
            
            container="${pair%%=*}"
            image="${pair#*=}"
            
            # Check if just updated
            updated_marker=""
            for idx in "${SELECTED_INDICES[@]}"; do
                if [[ "${MATCHED_NS[idx]}" == "$ns" && "${MATCHED_DEPLOY[idx]}" == "$deploy" && "${MATCHED_CONTAINER[idx]}" == "$container" ]]; then
                    updated_marker=" ✓ (just updated)"
                    break
                fi
            done
            
            printf "  %-30s %-20s %-50s%s\n" "$deploy" "$container" "$image" "$updated_marker"
        done
    done <<< "$ALL_DEPLOYMENTS"
done

echo
log "Image information display completed!"
```
