#!/bin/bash
# Build learner environment images locally with plain docker (no cluster/kaniko).
# Tags land under $IMAGE_REGISTRY so the portal's registry-prefix resolution finds
# them without pulling. Run from anywhere; context is the repository root.
set -euo pipefail
cd "$(dirname "$0")/.."
REGISTRY=${IMAGE_REGISTRY:-ghcr.io/admuppy}

docker build -f learner/Dockerfile -t "$REGISTRY/snacklab-linux:v2" .

# k8s learner image (embedded k3s). course.json files currently reference v5 (k8s,
# cks, ckad) and v6 (cka) — tag the same build as both.
docker build -f k8s-lab/Dockerfile -t "$REGISTRY/snacklab-k8s:v5" .
docker tag "$REGISTRY/snacklab-k8s:v5" "$REGISTRY/snacklab-k8s:v6"

echo "built: $REGISTRY/snacklab-linux:v2, $REGISTRY/snacklab-k8s:v5 (=v6)"
