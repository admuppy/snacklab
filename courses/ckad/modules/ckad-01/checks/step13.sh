#!/bin/bash
# Q13 requests/limits under quota (6 pts) — exact resource values and both
# replicas actually Ready (without requests the quota rejects the pods, so a
# Ready deployment proves the learner understood the point of the task).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get deploy worker -n batch >/dev/null 2>&1; then
  part 0 1 step13m1
  part 0 2 step13m1
  part 0 2 step13m1
  part 0 1 step13m1
  exit 0
fi
D=$(kubectl get deploy worker -n batch -o json)
R=$(echo "$D" | jq '.spec.template.spec.containers[0].resources')

rep=$(echo "$D" | jq -r '.spec.replicas // ""')
if [ "$rep" = "2" ]; then part 1 1 q13c1; else part 0 1 step13m2 "${rep:-(none)}"; fi

if [ "$(echo "$R" | jq -r '.requests.cpu // ""')" = "100m" ] \
  && [ "$(echo "$R" | jq -r '.requests.memory // ""')" = "64Mi" ]; then
  part 2 2 q13c2
else
  part 0 2 step13m3
fi

if [ "$(echo "$R" | jq -r '.limits.cpu // ""')" = "200m" ] \
  && [ "$(echo "$R" | jq -r '.limits.memory // ""')" = "128Mi" ]; then
  part 2 2 q13c3
else
  part 0 2 step13m4
fi

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" = "2" ]; then part 1 1 q13c4; else part 0 1 step13m5 "$ready"; fi
exit 0
