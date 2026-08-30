#!/bin/bash
# Q8 CrashLoopBackOff (5 pts) — the evidence file must hold the real error
# line, and the deployment must have been repaired to Available.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ -f ~/answers/q8.txt ] && grep -Eq "not found|start-order-daemon" ~/answers/q8.txt; then
  part 2 2 q8c1
else
  part 0 2 step8m1
fi

if ! kubectl get deploy orders -n broken >/dev/null 2>&1; then
  part 0 2 step8m2
  part 0 1 step8m2
  exit 0
fi
D=$(kubectl get deploy orders -n broken -o json)
avail=$(echo "$D" | jq -r '.status.conditions[]? | select(.type=="Available") | .status')
if [ "$avail" = "True" ]; then part 2 2 q8c2; else part 0 2 step8m3; fi

# the fix asked for a specific replacement command, not deleting the container
cmd=$(echo "$D" | jq -r '.spec.template.spec.containers[0].command | join(" ")' 2>/dev/null)
if echo "$cmd" | grep -q "while true"; then part 1 1 q8c3; else part 0 1 step8m4; fi
exit 0
