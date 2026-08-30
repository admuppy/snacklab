#!/bin/bash
# Q7 probes (5 pts) — exact probe fields plus the pod actually being Ready
# (a wrong port would keep readiness failing forever).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get pod probe-pod -n dev >/dev/null 2>&1; then
  part 0 2 step7m1
  part 0 2 step7m1
  part 0 1 step7m1
  exit 0
fi
P=$(kubectl get pod probe-pod -n dev -o json)
C=$(echo "$P" | jq '.spec.containers[0]')

r=$(echo "$C" | jq '.readinessProbe // {}')
if [ "$(echo "$r" | jq -r '.httpGet.path // ""')" = "/" ] \
  && [ "$(echo "$r" | jq -r '.httpGet.port // ""')" = "80" ] \
  && [ "$(echo "$r" | jq -r '.initialDelaySeconds // ""')" = "3" ] \
  && [ "$(echo "$r" | jq -r '.periodSeconds // ""')" = "5" ]; then
  part 2 2 q7c1
else
  part 0 2 step7m2
fi

l=$(echo "$C" | jq '.livenessProbe // {}')
if [ "$(echo "$l" | jq -r '.httpGet.path // ""')" = "/" ] \
  && [ "$(echo "$l" | jq -r '.httpGet.port // ""')" = "80" ] \
  && [ "$(echo "$l" | jq -r '.periodSeconds // ""')" = "10" ]; then
  part 2 2 q7c2
else
  part 0 2 step7m3
fi

ready=$(echo "$P" | jq -r '.status.conditions[]? | select(.type=="Ready") | .status')
if [ "$ready" = "True" ]; then part 1 1 q7c3; else part 0 1 step7m4; fi
exit 0
