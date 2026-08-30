#!/bin/bash
# Q9 removed API versions (5 pts) — both resources applied, the file itself
# corrected (no *beta* apiVersions left), and the deployment healthy.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get deploy report-api -n batch >/dev/null 2>&1; then part 1 1 q9c1; else part 0 1 step9m1 "Deployment" "report-api"; fi
if kubectl get cronjob report-gen -n batch >/dev/null 2>&1; then part 1 1 q9c2; else part 0 1 step9m1 "CronJob" "report-gen"; fi

F=~/work/legacy/stack.yaml
if [ -f "$F" ] && grep -q "^apiVersion: apps/v1$" "$F" && grep -q "^apiVersion: batch/v1$" "$F" \
  && ! grep -q "v1beta1" "$F"; then
  part 2 2 q9c3
else
  part 0 2 step9m2
fi

ready=$(kubectl get deploy report-api -n batch -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "${ready:-0}" = "1" ]; then part 1 1 q9c4; else part 0 1 step9m3; fi
exit 0
