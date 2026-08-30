#!/bin/bash
# Q8 remove host access (5 pts) — each of the four host-access vectors must be gone,
# and the pod must still run.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

D=$(kubectl get deploy node-tool -n sys-hard -o json 2>/dev/null)
if [ -z "$D" ]; then
  for i in 1 2 3 4 5; do part 0 1 step8m1; done
  exit 0
fi
T=$(echo "$D" | jq '.spec.template.spec')

if echo "$T" | jq -e '[.containers[] | .securityContext.privileged // false] | any' >/dev/null 2>&1; then
  part 0 1 step8m2
else
  part 1 1 q8c1
fi
if [ "$(echo "$T" | jq -r '.hostPID // false')" = "true" ]; then part 0 1 step8m3; else part 1 1 q8c2; fi
if [ "$(echo "$T" | jq -r '.hostNetwork // false')" = "true" ]; then part 0 1 step8m4; else part 1 1 q8c3; fi
if echo "$T" | jq -e '[.volumes[]? | select(.hostPath)] | length > 0' >/dev/null 2>&1; then
  part 0 1 step8m5
else
  part 1 1 q8c4
fi

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" -ge 1 ]; then part 1 1 q8c5; else part 0 1 step8m6; fi
exit 0
