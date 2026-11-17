#!/bin/bash

# K8s Cluster Migration Proxy Deployment Script
# This script deploys the basic infrastructure for the migration proxy

set -e

NAMESPACE="aibang-1111111111-bbdm"
KUBECTL_CMD="kubectl"

echo "🚀 Deploying K8s Migration Proxy Infrastructure..."

# Check if namespace exists
if ! $KUBECTL_CMD get namespace $NAMESPACE >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

# Apply configurations in order
echo "📝 Applying ConfigMap..."
$KUBECTL_CMD apply -f nginx-configmap.yaml

echo "🔗 Applying External Services..."
$KUBECTL_CMD apply -f external-service.yaml
if [ -f "k8s/external-services.yaml" ]; then
    echo "🔗 Applying Enhanced External Services..."
    $KUBECTL_CMD apply -f k8s/external-services.yaml
fi

echo "🌐 Applying DNS Configuration..."
if [ -f "k8s/dns-config.yaml" ]; then
    $KUBECTL_CMD apply -f k8s/dns-config.yaml
fi

echo "🚀 Applying Deployment..."
$KUBECTL_CMD apply -f deployment.yaml

echo "🌐 Applying Service..."
$KUBECTL_CMD apply -f service.yaml

echo "📊 Applying ServiceMonitor..."
$KUBECTL_CMD apply -f servicemonitor.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
$KUBECTL_CMD rollout status deployment/migration-proxy -n $NAMESPACE --timeout=300s

# Check pod status
echo "🔍 Checking pod status..."
$KUBECTL_CMD get pods -n $NAMESPACE -l app=migration-proxy

# Test health endpoint
echo "🏥 Testing health endpoint..."
POD_NAME=$($KUBECTL_CMD get pods -n $NAMESPACE -l app=migration-proxy -o jsonpath='{.items[0].metadata.name}')
if [ ! -z "$POD_NAME" ]; then
    $KUBECTL_CMD exec -n $NAMESPACE $POD_NAME -- curl -s http://localhost:8080/health
    echo ""
fi

# Validate ExternalName services
echo "🔍 Validating ExternalName services..."
if [ -f "scripts/validate-external-services.py" ]; then
    python3 scripts/validate-external-services.py --namespace $NAMESPACE || echo "⚠️  ExternalName service validation had issues"
fi

# Test connectivity to new cluster
echo "🌐 Testing connectivity to new cluster..."
if [ -f "scripts/verify-connectivity.sh" ]; then
    bash scripts/verify-connectivity.sh || echo "⚠️  Connectivity test had issues"
fi

echo "✅ Migration proxy infrastructure deployed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Verify the proxy is working: kubectl port-forward -n $NAMESPACE svc/migration-proxy 8080:8080"
echo "2. Test health endpoint: curl http://localhost:8080/health"
echo "3. Verify ExternalName services: kubectl get svc -n $NAMESPACE -l component=external-service"
echo "4. Test DNS resolution: nslookup api-name01.kong.dev.aliyun.intracloud.cn.aibang"
echo "5. Configure Ingress to route traffic to the migration-proxy service"
echo "6. Proceed to task 4: Implement Ingress configuration updates"