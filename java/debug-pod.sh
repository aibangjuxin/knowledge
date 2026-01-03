#!/bin/bash

set -euo pipefail

usage() { 
  cat << EOF
Usage: $0 -t <target-image> [-s <sidecar-image>] [-n <namespace>]
  -t: Target GAR image (required), e.g., asia-docker.pkg.dev/PROJECT/REPO/java-application:latest
  -s: Sidecar debug image, default: praqma/network-multitool:latest
  -n: Kubernetes namespace, auto-detect current or default: default
  -h: Show this help
EOF
  exit 1
}

# Defaults
SIDECAR_IMAGE="praqma/network-multitool:latest"
NAMESPACE="default"
TARGET_IMAGE=""

# Parse args
while getopts t:s:n:h opt; do
  case \$opt in
    t) TARGET_IMAGE="\$OPTARG" ;;
    s) SIDECAR_IMAGE="\$OPTARG" ;;
    n) NAMESPACE="\$OPTARG" ;;
    h) usage ;;
    \\?) usage ;;
  esac
done

if [ -z "\$TARGET_IMAGE" ]; then
  echo "Error: -t target image is required"
  usage
fi

# Auto-detect namespace if 'default' and kubectl ready
if [ "\$NAMESPACE" = "default" ]; then
  CURRENT_NS=\$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null || echo "")
  [ -n "\$CURRENT_NS" ] && NAMESPACE="\$CURRENT_NS"
fi

# Sanitize names
IMAGE_NAME=\$(basename "\${TARGET_IMAGE%:*}")
IMAGE_NAME=\${IMAGE_NAME//[^a-zA-Z0-9-]/-}
DEPLOY_NAME="debug-\$IMAGE_NAME"
YAML_FILE="debug-deploy-\$IMAGE_NAME.yaml"

echo "=== Java Pod Debug Script ==="
echo "Namespace: \$NAMESPACE"
echo "Target Image: \$TARGET_IMAGE"
echo "Sidecar Image: \$SIDECAR_IMAGE"
echo "Deploy Name: \$DEPLOY_NAME"
echo ""

# Generate YAML
cat > "\$YAML_FILE" << YAML_EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \$DEPLOY_NAME
  namespace: \$NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: \$DEPLOY_NAME
  template:
    metadata:
      labels:
        app: \$DEPLOY_NAME
    spec:
      containers:
      - name: app
        image: \$TARGET_IMAGE
        command: ["/bin/sh", "-c"]
        args: ["sleep 36000"]
        # Add volumeMounts/resources/securityContext if needed
YAML_EOF

echo "Generated YAML: \$YAML_FILE"
echo "Applying..."
kubectl apply -f "\$YAML_FILE" -n "\$NAMESPACE"

echo "Waiting for Deployment rollout (120s timeout)..."
if ! kubectl rollout status deployment/\$DEPLOY_NAME -n "\$NAMESPACE" --timeout=120s; then
  echo "Rollout failed, check: kubectl describe pod -l app=\$DEPLOY_NAME -n \$NAMESPACE"
  exit 1
fi

POD_NAME=\$(kubectl get pods -n "\$NAMESPACE" -l app="\$DEPLOY_NAME" --no-headers -o custom-columns=NAME:.metadata.name | head -1)

echo ""
echo "✅ SUCCESS: Debug Pod is Running!"
echo "Pod Name: \$POD_NAME"
echo ""
echo "🚀 DEBUG COMMAND:"
echo "kubectl debug -it \$POD_NAME -n \$NAMESPACE --image=\$SIDECAR_IMAGE --target=app -- sh"
echo ""
echo "📂 INSIDE DEBUG SHELL:"
echo "  cd /proc/1/root/opt/apps/"
echo "  ls -lah *.jar"
echo "  sha256sum *.jar"
echo "  unzip -l *.jar | grep -i 'spring-boot\\|snakeyaml'"
echo "  unzip -p *.jar META-INF/MANIFEST.MF"
echo ""
echo "🧹 CLEANUP:"
echo "  kubectl delete deployment \$DEPLOY_NAME -n \$NAMESPACE"
echo "  rm \$YAML_FILE"
echo ""
echo "💡 See @java/debug-java-pod.md for full guide.