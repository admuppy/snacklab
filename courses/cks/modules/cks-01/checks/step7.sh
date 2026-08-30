#!/bin/bash
# Q7 seccomp RuntimeDefault (5 pts) — accept pod-level OR all-containers-level.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

D=$(kubectl get deploy runner -n sys-hard -o json 2>/dev/null)
if [ -z "$D" ]; then
  part 0 3 step7m1
  part 0 2 step7m1
  exit 0
fi

podlvl=$(echo "$D" | jq -r '.spec.template.spec.securityContext.seccompProfile.type // ""')
allctr=$(echo "$D" | jq -r '[.spec.template.spec.containers[] |
  .securityContext.seccompProfile.type // ""] | if length>0 and all(.=="RuntimeDefault") then "RuntimeDefault" else "" end')
if [ "$podlvl" = "RuntimeDefault" ] || [ "$allctr" = "RuntimeDefault" ]; then
  part 3 3 q7c1
else
  part 0 3 step7m2
fi

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" -ge 2 ]; then part 2 2 q7c2; else part 0 2 step7m3 "$ready"; fi
exit 0
