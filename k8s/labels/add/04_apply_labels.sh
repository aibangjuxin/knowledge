#!/bin/bash

# 04_apply_labels.sh
# Purpose: Iterate through deployments, match with mapping, and apply labels.

MAPPING_FILE="mapping.json"
LOG_DIR="logs"
DRY_RUN=false

# Create log directory
mkdir -p "$LOG_DIR"
SUCCESS_LOG="$LOG_DIR/success.log"
FAILED_LOG="$LOG_DIR/failed.log"
UNMATCHED_LOG="$LOG_DIR/unmatched.log"
SKIPPED_LOG="$LOG_DIR/skipped.log"

# Clear previous logs
> "$SUCCESS_LOG"
> "$FAILED_LOG"
> "$UNMATCHED_LOG"
> "$SKIPPED_LOG"

# Parse arguments
if [[ "$1" == "-d" || "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "Running in DRY-RUN mode. No changes will be applied."
fi

if [ ! -f "$MAPPING_FILE" ]; then
    echo "Error: $MAPPING_FILE not found. Run 02_generate_mapping.sh first."
    exit 1
fi

echo "Starting label application process..."

# Get all deployments (Namespace Name)
# Using process substitution to avoid subshell issues
while read -r ns name; do
    # 1. Extract API Name
    # Remove '-deployment' suffix
    temp_name=${name%-deployment}
    # Remove version suffix (assuming format -X-X-X, e.g., -1-0-2)
    # Using sed for regex replacement
    api_name=$(echo "$temp_name" | sed -E 's/-[0-9]+-[0-9]+-[0-9]+$//')

    # 2. Lookup in mapping file
    # Use jq to get the object for this api_name. If null, it doesn't exist.
    match=$(jq -r --arg key "$api_name" '.[$key] // empty' "$MAPPING_FILE")

    if [ -z "$match" ]; then
        echo "[$ns/$name] -> API: $api_name -> Unmatched"
        echo "$ns $name ($api_name)" >> "$UNMATCHED_LOG"
        continue
    fi

    # Extract labels
    eid=$(echo "$match" | jq -r '.eidnumber')
    bid=$(echo "$match" | jq -r '.bidnumber')

    echo "[$ns/$name] -> API: $api_name -> Match! EID: $eid, BID: $bid"

    # 3. Patch Deployment
    PATCH_JSON="{\"metadata\":{\"labels\":{\"eidnumber\":\"$eid\",\"bidnumber\":\"$bid\"}}}"
    
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] kubectl patch deployment $name -n $ns -p '$PATCH_JSON'"
    else
        # Execute patch
        if kubectl patch deployment "$name" -n "$ns" --type=merge -p "$PATCH_JSON" &> /dev/null; then
            echo "$ns $name patched with EID:$eid BID:$bid" >> "$SUCCESS_LOG"
        else
            echo "Failed to patch $ns $name"
            echo "$ns $name" >> "$FAILED_LOG"
        fi
    fi

done < <(kubectl get deployments --all-namespaces -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers)

echo "----------------------------------------"
echo "Processing complete."
echo "Logs:"
echo "  Success:   $(wc -l < "$SUCCESS_LOG")"
echo "  Failed:    $(wc -l < "$FAILED_LOG")"
echo "  Unmatched: $(wc -l < "$UNMATCHED_LOG")"
if [ "$DRY_RUN" = true ]; then
    echo "Note: This was a DRY RUN."
fi
