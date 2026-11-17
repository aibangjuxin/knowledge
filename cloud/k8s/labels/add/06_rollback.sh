#!/bin/bash

# 06_rollback.sh
# Purpose: Rollback changes by restoring from backup.

# Find the latest backup file
BACKUP_FILE=$(ls -t backup_deployments_*.yaml 2>/dev/null | head -n 1)

if [ -z "$BACKUP_FILE" ]; then
    echo "Error: No backup file found (backup_deployments_*.yaml)."
    echo "Cannot perform automatic rollback."
    exit 1
fi

echo "Found latest backup: $BACKUP_FILE"
echo "WARNING: This will restore all deployments to the state in this backup file."
echo "Are you sure you want to proceed? (y/n)"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Restoring from backup..."
    kubectl apply -f "$BACKUP_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Rollback complete."
    else
        echo "Rollback failed."
    fi
else
    echo "Rollback cancelled."
fi
