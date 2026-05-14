# Shell Scripts Collection

Generated on: 2025-09-28 19:01:35
Directory: /Users/lex/git/knowledge/React/scripts

## `build.sh`

```bash
#!/bin/bash

# Build script for React Docker application

set -e

echo "🚀 Building React Docker Application..."

# Build Docker image
echo "📦 Building Docker image..."
docker build -t react-docker-app:latest .

echo "✅ Docker image built successfully!"

# Tag for different environments
docker tag react-docker-app:latest react-docker-app:$(date +%Y%m%d-%H%M%S)

echo "🏷️  Image tagged with timestamp"
echo "🎉 Build completed successfully!"
```

## `deploy.sh`

```bash
#!/bin/bash

# Deploy script for Kubernetes

set -e

echo "🚀 Deploying React application to Kubernetes..."

# Apply Kubernetes manifests
echo "📋 Applying Kubernetes manifests..."

kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml

echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/react-app --timeout=300s

echo "🔍 Checking pod status..."
kubectl get pods -l app=react-app

echo "🌐 Service information:"
kubectl get services -l app=react-app

echo "📊 HPA status:"
kubectl get hpa react-app-hpa

echo "✅ Deployment completed successfully!"
echo "🎯 Application should be accessible via NodePort 30080"
```

