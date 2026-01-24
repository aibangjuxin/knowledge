#!/bin/bash

################################################################################
# Script: debug-trust-configs.sh
# Description: Debug version to test trust config access
# Usage: ./debug-trust-configs.sh [--project PROJECT_ID]
################################################################################

set -x  # Enable debug mode

PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="global"

echo "================================"
echo "Testing Trust Config Access"
echo "================================"
echo "Project: $PROJECT_ID"
echo "Location: $LOCATION"
echo ""

echo "Step 1: List trust configs"
echo "---"
gcloud certificate-manager trust-configs list \
    --location="$LOCATION" \
    --project="$PROJECT_ID" \
    --format="table(name,createTime)" 

echo ""
echo "Step 2: Get full resource names"
echo "---"
FULL_NAMES=$(gcloud certificate-manager trust-configs list \
    --location="$LOCATION" \
    --project="$PROJECT_ID" \
    --format="value(name)")

echo "Full names:"
echo "$FULL_NAMES"

echo ""
echo "Step 3: Extract short names"
echo "---"
while IFS= read -r full_name; do
    if [ -n "$full_name" ]; then
        short_name=$(basename "$full_name")
        echo "Full: $full_name"
        echo "Short: $short_name"
        echo ""
        
        echo "Step 4: Try describe with short name"
        gcloud certificate-manager trust-configs describe "$short_name" \
            --location="$LOCATION" \
            --project="$PROJECT_ID" \
            --format=yaml | head -10
        
        echo ""
        echo "Step 5: Get JSON format"
        gcloud certificate-manager trust-configs describe "$short_name" \
            --location="$LOCATION" \
            --project="$PROJECT_ID" \
            --format=json | jq -r '.name, .createTime' 2>/dev/null || echo "jq failed"
        
        echo ""
        echo "---"
        break  # Only test first one
    fi
done <<< "$FULL_NAMES"

echo ""
echo "Debug test completed!"
