#!/bin/bash
set -e

IMAGE_NAME="dns-verify-tool"
CONTAINER_NAME="dns-tool"
PORT=8000

echo "Building Docker image..."
docker build -t "$IMAGE_NAME" .

echo "Stopping existing container (if any)..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting new container on port $PORT..."
docker run -d -p "$PORT:$PORT" --name "$CONTAINER_NAME" "$IMAGE_NAME"

echo ""
echo "✅ Success! Service is running."
echo "➡️  Open: http://localhost:$PORT/Intra-verify-domain.html"
