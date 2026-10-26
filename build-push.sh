#!/usr/bin/env bash
# Build and push both images to Docker Hub.
# Usage (from repo root): ./build-push.sh v1.0.0
set -euo pipefail
TAG="${1:?usage: ./build-push.sh <tag>  e.g. v1.0.0}"
USER="rdomala"

# linux/amd64 + linux/arm64 so the same tag works on kind (Apple Silicon) and EKS
for svc in frontend backend; do
  docker buildx build --platform linux/amd64,linux/arm64 \
    -t "$USER/product1-$svc:$TAG" --push "./src/$svc"
done
echo "Pushed $USER/product1-frontend:$TAG and $USER/product1-backend:$TAG"
