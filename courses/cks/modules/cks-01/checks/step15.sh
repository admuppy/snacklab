#!/bin/bash
# Q15 audit logging (8 pts) — policy file, k3s config args, and a functional probe:
# read a secret, then expect a fresh "secrets" entry in the audit log.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
POLICY=/var/lib/rancher/k3s/server/audit-policy.yaml
LOG=/var/lib/rancher/k3s/server/logs/audit.log
CFG=/etc/rancher/k3s/config.yaml

if sudo test -s "$POLICY" && sudo grep -q 'secrets' "$POLICY" && sudo grep -q 'Metadata' "$POLICY"; then
  part 2 2 q15c1
else
  part 0 2 step15m1
fi

if sudo test -s "$CFG" && sudo grep -q 'audit-policy-file' "$CFG" && sudo grep -q 'audit-log-path' "$CFG"; then
  part 2 2 q15c2
else
  part 0 2 step15m2
fi

if sudo test -f "$LOG"; then
  part 1 1 q15c3
else
  part 0 1 step15m3
  part 0 3 step15m3
  exit 0
fi

# functional probe — this GET must land in the log at Metadata level
kubectl get secret -n kube-system >/dev/null 2>&1
sleep 3
if sudo tail -n 200 "$LOG" 2>/dev/null | grep -q '"resource":"secrets"'; then
  part 3 3 q15c4
else
  part 0 3 step15m4
fi
exit 0
