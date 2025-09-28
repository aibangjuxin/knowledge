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