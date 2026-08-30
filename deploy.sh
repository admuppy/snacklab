#!/bin/bash
# 포털 helm 릴리스 업그레이드 (릴리스명 lab, ns snacklab).
# 사용: ./deploy.sh <image-tag>    예: ./deploy.sh v1.5
# This changes the live release — double-check before running.
set -euo pipefail
cd "$(dirname "$0")"
TAG=${1:?사용법: ./deploy.sh <image-tag>}
NS=snacklab
REL=lab

# 현재 라이브 값(values-live.yaml)을 유지하며 이미지 태그만 올린다.
helm upgrade "$REL" ./chart -n "$NS" \
  -f chart/values-live.yaml \
  --set image.tag="$TAG" \
  --wait --timeout 5m

kubectl rollout status deploy/lab-snacklab -n "$NS" --timeout=5m
echo "deployed snacklab-portal:$TAG"
