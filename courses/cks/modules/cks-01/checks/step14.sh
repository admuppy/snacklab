#!/bin/bash
# Q14 digest pinning (6 pts) — the deployment must reference nginx by sha256 digest,
# and Ready pods prove the digest is real (a made-up digest cannot pull).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

D=$(kubectl get deploy pinned -n supply -o json 2>/dev/null)
if [ -z "$D" ]; then
  part 0 4 step14m1
  part 0 2 step14m1
  exit 0
fi
img=$(echo "$D" | jq -r '.spec.template.spec.containers[0].image')
if echo "$img" | grep -Eq '^(docker\.io/library/)?nginx@sha256:[0-9a-f]{64}$'; then
  part 4 4 q14c1
elif echo "$img" | grep -q '@sha256:'; then
  part 0 4 step14m2 "$img"
else
  part 0 4 step14m3 "$img"
fi

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" -ge 1 ]; then part 2 2 q14c2; else part 0 2 step14m4; fi
exit 0
