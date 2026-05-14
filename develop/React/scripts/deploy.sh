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