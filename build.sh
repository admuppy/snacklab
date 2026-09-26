#!/bin/bash
# Build an image with in-cluster kaniko and push it to a registry
# (context is streamed as a tar over stdin — no docker daemon needed).
#
# Usage:
#   ./build.sh [tag]             portal image (snacklab-portal), default tag = Chart.yaml appVersion
#   ./build.sh portal [tag]      same as above
#   ./build.sh learner [tag]     Linux learner environment image (snacklab-linux), default tag=v2
#   ./build.sh k8s-lab [tag]     Kubernetes learner environment image (snacklab-k8s, embedded k3s), default tag=v1
#   ./build.sh openstack-lab [tag]  OpenStack learner environment image (snacklab-openstack, fake driver), default tag=v1
#   ./build.sh k8s-course [tag]  Kubernetes course content image (snacklab-k8s-course), default tag=v1
#   ./build.sh openstack-course [tag]  OpenStack course content image (snacklab-openstack-course), default tag=v1
#   ./build.sh cka-course [tag]  CKA mock-exam content image (snacklab-cka-course), default tag=v1
#   ./build.sh cks-course [tag]  CKS mock-exam content image (snacklab-cks-course), default tag=v1
#   ./build.sh ckad-course [tag] CKAD mock-exam content image (snacklab-ckad-course), default tag=v1
#                                (exam tracks share the k8s learner image, snacklab-k8s)
#
# Site configuration (env vars, or put them in ./build.env which is sourced if present):
#   REGISTRY     registry + namespace to push to, e.g. ghcr.io/admuppy or registry.example.com/snacklab
#   PUSH_SECRET  name of an existing docker-registry Secret in $NS used for pushing (default: regcred)
#   NS           namespace to run the kaniko pod in (default: snacklab)
set -euo pipefail
cd "$(dirname "$0")"

[ -f ./build.env ] && . ./build.env

REGISTRY=${REGISTRY:?set REGISTRY (e.g. ghcr.io/admuppy) via env or build.env}
PUSH_SECRET=${PUSH_SECRET:-regcred}
NS=${NS:-snacklab}

# Consume the first arg as target if it names one, otherwise build the portal
TARGET=portal
case "${1:-}" in
  portal|learner|k8s-lab|openstack-lab|k8s-course|openstack-course|cka-course|cks-course|ckad-course) TARGET=$1; shift ;;
esac

if [ "$TARGET" = learner ]; then
  DOCKERFILE=learner/Dockerfile
  REPO=$REGISTRY/snacklab-linux
  TAG=${1:-v2}
  POD=learner-image-build
elif [ "$TARGET" = k8s-lab ]; then
  DOCKERFILE=k8s-lab/Dockerfile
  REPO=$REGISTRY/snacklab-k8s
  TAG=${1:-v1}
  POD=k8s-lab-image-build
elif [ "$TARGET" = openstack-lab ]; then
  DOCKERFILE=openstack-lab/Dockerfile
  REPO=$REGISTRY/snacklab-openstack
  TAG=${1:-v1}
  POD=openstack-lab-image-build
elif [ "$TARGET" = k8s-course ]; then
  DOCKERFILE=courses/k8s/Dockerfile
  REPO=$REGISTRY/snacklab-k8s-course
  TAG=${1:-v1}
  POD=k8s-course-image-build
elif [ "$TARGET" = openstack-course ]; then
  DOCKERFILE=courses/openstack/Dockerfile
  REPO=$REGISTRY/snacklab-openstack-course
  TAG=${1:-v1}
  POD=openstack-course-image-build
elif [ "$TARGET" = cka-course ]; then
  DOCKERFILE=courses/cka/Dockerfile
  REPO=$REGISTRY/snacklab-cka-course
  TAG=${1:-v1}
  POD=cka-course-image-build
elif [ "$TARGET" = cks-course ]; then
  DOCKERFILE=courses/cks/Dockerfile
  REPO=$REGISTRY/snacklab-cks-course
  TAG=${1:-v1}
  POD=cks-course-image-build
elif [ "$TARGET" = ckad-course ]; then
  DOCKERFILE=courses/ckad/Dockerfile
  REPO=$REGISTRY/snacklab-ckad-course
  TAG=${1:-v1}
  POD=ckad-course-image-build
else
  DOCKERFILE=portal/Dockerfile
  REPO=$REGISTRY/snacklab-portal
  TAG=${1:-$(python3 -c "import yaml;print(yaml.safe_load(open('chart/Chart.yaml'))['appVersion'])")}
  POD=portal-image-build
fi
IMG=$REPO:$TAG

kubectl get secret "$PUSH_SECRET" -n "$NS" >/dev/null 2>&1 || {
  echo "push secret '$PUSH_SECRET' not found in namespace '$NS'." >&2
  echo "create one first, e.g.:" >&2
  echo "  kubectl create secret docker-registry $PUSH_SECRET -n $NS \\" >&2
  echo "    --docker-server=<registry> --docker-username=<user> --docker-password=<password>" >&2
  exit 1
}

kubectl delete pod "$POD" -n "$NS" --ignore-not-found --wait=true

# Stream the build context tar to kaniko via stdin (excluding node_modules/.git/sessions)
tar czf - --exclude=./v0.1/node_modules --exclude=./.git \
    --exclude=./v0.1/sessions --exclude=./chart/values-live.yaml . \
| kubectl run "$POD" -n "$NS" -i --restart=Never --pod-running-timeout=5m \
    --image=gcr.io/kaniko-project/executor:latest \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "kaniko", "stdin": true, "stdinOnce": true,
          "image": "gcr.io/kaniko-project/executor:latest",
          "args": ["--dockerfile='"$DOCKERFILE"'","--context=tar://stdin","--destination='"$IMG"'","--compressed-caching=false"],
          "volumeMounts": [{"name":"docker-config","mountPath":"/kaniko/.docker"}],
          "resources": {"requests":{"cpu":"1","memory":"2Gi"},"limits":{"memory":"4Gi"}}
        }],
        "volumes": [{"name":"docker-config","secret":{"secretName":"'"$PUSH_SECRET"'","items":[{"key":".dockerconfigjson","path":"config.json"}]}}]
      }
    }'

echo "pushed: $IMG"
