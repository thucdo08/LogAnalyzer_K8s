#!/bin/bash
# Script build và push Docker image lên private registry
# Chạy trên máy có Docker: bash scripts/build-push.sh
# Yêu cầu: Docker daemon đã config --insecure-registry jfrog.dofuta.site

set -e

REGISTRY="jfrog.dofuta.site"
TAG=${1:-$(git rev-parse --short HEAD)}

echo "🔨 Building images with tag: $TAG"

docker build -t ${REGISTRY}/loganalyzer-backend:${TAG} \
             -t ${REGISTRY}/loganalyzer-backend:latest \
             ./backend

docker build -t ${REGISTRY}/loganalyzer-frontend:${TAG} \
             -t ${REGISTRY}/loganalyzer-frontend:latest \
             ./frontend

echo "📤 Pushing to registry: $REGISTRY"
docker push ${REGISTRY}/loganalyzer-backend:${TAG}
docker push ${REGISTRY}/loganalyzer-backend:latest
docker push ${REGISTRY}/loganalyzer-frontend:${TAG}
docker push ${REGISTRY}/loganalyzer-frontend:latest

echo "✅ Done! Images pushed:"
echo "   ${REGISTRY}/loganalyzer-backend:${TAG}"
echo "   ${REGISTRY}/loganalyzer-frontend:${TAG}"
echo ""
echo "👉 ArgoCD sẽ tự phát hiện image mới nếu đã cài Image Updater"
echo "   Hoặc chạy: kubectl -n argocd app sync loganalyzer-production"
