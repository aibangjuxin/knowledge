#!/bin/bash
set -e

# Required Environment Variables:
# USER: Username (e.g., userA)
# API: API Name (e.g., api1)
# IMAGE_NAME: Full image path (e.g., asia-east1-docker.pkg.dev/myproj/userA/api1:v1.2.3)
# REPLICAS: Number of replicas
# CPU_REQUEST: CPU request (e.g., 100m)
# MEMORY_REQUEST: Memory request (e.g., 128Mi)
# CPU_LIMIT: CPU limit (e.g., 200m)
# MEMORY_LIMIT: Memory limit (e.g., 256Mi)

if [[ -z "$USER" || -z "$API" || -z "$IMAGE_NAME" ]]; then
  echo "Error: Missing required environment variables (USER, API, IMAGE_NAME)"
  exit 1
fi

TEMPLATE_DIR="users/$USER/$API/templates"
RENDERED_FILE="rendered.yaml"

echo "Rendering manifests for $USER/$API..."

# Ensure the output file is empty
> "$RENDERED_FILE"

# Loop through templates and substitute variables
for template in "$TEMPLATE_DIR"/*.yaml; do
  echo "---" >> "$RENDERED_FILE"
  envsubst < "$template" >> "$RENDERED_FILE"
done

echo "Validating manifests with kubeconform..."
if command -v kubeconform &> /dev/null; then
  kubeconform -strict -summary "$RENDERED_FILE"
else
  echo "Warning: kubeconform not found, skipping validation."
fi

echo "Applying manifests to namespace $USER..."
# Ensure namespace exists (idempotent)
kubectl create namespace "$USER" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$RENDERED_FILE" -n "$USER"

echo "Deployment completed successfully."
