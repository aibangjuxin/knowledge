#!/bin/bash
set -e

# Required Environment Variables:
# NEXUS_IMAGE: Source image URL (e.g., nexus.local/user/api1:v1.2.3)
# GAR_REPO: Target GAR repository (e.g., asia-east1-docker.pkg.dev/myproj/userA/api1)
# VERSION: Image tag (e.g., v1.2.3)

if [[ -z "$NEXUS_IMAGE" || -z "$GAR_REPO" || -z "$VERSION" ]]; then
  echo "Error: Missing required environment variables (NEXUS_IMAGE, GAR_REPO, VERSION)"
  exit 1
fi

echo "Pulling image from Nexus: $NEXUS_IMAGE"
docker pull "$NEXUS_IMAGE"

TARGET_IMAGE="$GAR_REPO:$VERSION"
echo "Tagging image as: $TARGET_IMAGE"
docker tag "$NEXUS_IMAGE" "$TARGET_IMAGE"

echo "Pushing image to GAR: $TARGET_IMAGE"
docker push "$TARGET_IMAGE"

echo "Image sync completed successfully."
