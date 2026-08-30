#!/bin/bash
# Q6 kustomize (7 pts) — the overlay must exist as files AND have been applied:
# result in the cluster (namespace, replicas, image) is what earns the points.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
OV=~/work/kustomize/overlays/prod

# overlay directory refers back to the base
ok=0
for f in "$OV/kustomization.yaml" "$OV/kustomization.yml"; do
  [ -f "$f" ] && grep -q "base" "$f" && ok=1 && break
done
if [ $ok = 1 ]; then part 2 2 q6c1; else part 0 2 step6m1; fi

if ! kubectl get deploy hello-web -n prod >/dev/null 2>&1; then
  part 0 1 step6m2
  part 0 1 step6m2
  part 0 2 step6m2
  part 0 1 step6m2
  exit 0
fi
D=$(kubectl get deploy hello-web -n prod -o json)
part 1 1 q6c2     # deployed into prod

rep=$(echo "$D" | jq -r '.spec.replicas // ""')
if [ "$rep" = "2" ]; then part 1 1 q6c3; else part 0 1 step6m3 "${rep:-(none)}"; fi

img=$(echo "$D" | jq -r '.spec.template.spec.containers[0].image // ""')
case "$img" in nginx:1.26|docker.io/nginx:1.26|docker.io/library/nginx:1.26) part 2 2 q6c4 ;;
  *) part 0 2 step6m4 "$img" ;; esac

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" = "2" ]; then part 1 1 q6c5; else part 0 1 step6m5 "$ready"; fi
exit 0
