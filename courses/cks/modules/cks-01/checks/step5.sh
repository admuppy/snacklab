#!/bin/bash
# Q5 SA token automount (5 pts) — SA flag, deployment wiring, and the running pod
# must actually have no token mount.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

S=$(kubectl get sa web-sa -n apps -o json 2>/dev/null)
if [ -z "$S" ]; then
  part 0 1 step5m1
  part 0 1 step5m1
else
  part 1 1 q5c1
  if [ "$(echo "$S" | jq -r .automountServiceAccountToken)" = "false" ]; then
    part 1 1 q5c2
  else
    part 0 1 step5m2
  fi
fi

D=$(kubectl get deploy web -n apps -o json 2>/dev/null)
if [ -z "$D" ]; then
  part 0 1 step5m3
  part 0 2 step5m3
  exit 0
fi
if [ "$(echo "$D" | jq -r '.spec.template.spec.serviceAccountName // "default"')" = "web-sa" ]; then
  part 1 1 q5c3
else
  part 0 1 step5m4
fi

# newest Running, non-terminating pod — right after a rollout the old pod may still
# be Running (Terminating) with the token mounted, which must not fail the learner
pod=$(kubectl get pod -n apps -l app=web -o json 2>/dev/null | jq -r \
  '[.items[] | select(.status.phase=="Running" and (.metadata.deletionTimestamp|not))]
   | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty')
if [ -z "$pod" ]; then
  part 0 2 step5m5
elif timeout 12 kubectl exec -n apps "$pod" -- \
    ls /var/run/secrets/kubernetes.io/serviceaccount >/dev/null 2>&1; then
  part 0 2 step5m6
else
  part 2 2 q5c4
fi
exit 0
