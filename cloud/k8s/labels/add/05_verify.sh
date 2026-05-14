#!/bin/bash

# 05_verify.sh
# Purpose: Verify that labels were correctly applied to deployments.

LOG_FILE="logs/success.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: $LOG_FILE not found. Run 04_apply_labels.sh first."
    exit 1
fi

echo "Verifying a sample of patched deployments..."

# Check up to 5 random entries from the success log
# Log format: "namespace deployment patched with EID:xxx BID:xxx"
shuf "$LOG_FILE" | head -n 5 | while read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    
    echo "Checking $ns/$name..."
    
    # Get labels
    labels=$(kubectl get deployment "$name" -n "$ns" -o jsonpath='{.metadata.labels}')
    
    eid=$(echo "$labels" | jq -r '.eidnumber // "Not Found"')
    bid=$(echo "$labels" | jq -r '.bidnumber // "Not Found"')
    
    echo "  -> eidnumber: $eid"
    echo "  -> bidnumber: $bid"
    
    if [[ "$eid" != "Not Found" && "$bid" != "Not Found" ]]; then
        echo "  [OK] Labels present."
    else
        echo "  [FAIL] Missing labels!"
    fi
done
