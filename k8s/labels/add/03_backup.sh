#!/bin/bash

# 03_backup.sh
# Purpose: Backup all deployments in all namespaces before making changes.

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_deployments_${TIMESTAMP}.yaml"

echo "Backing up all deployments to $BACKUP_FILE..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found."
    exit 1
fi

kubectl get deployments --all-namespaces -o yaml > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Backup successful: $BACKUP_FILE"
    echo "To restore (use with caution): kubectl apply -f $BACKUP_FILE"
else
    echo "Backup failed."
    exit 1
fi
