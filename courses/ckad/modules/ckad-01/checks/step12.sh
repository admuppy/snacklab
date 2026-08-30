#!/bin/bash
# Q12 ServiceAccount (6 pts) — SA wired to the pod, automount disabled in the
# spec, and proof: no token directory inside the container.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get sa app-sa -n dev >/dev/null 2>&1; then part 1 1 q12c1; else part 0 1 step12m1; fi

if ! kubectl get pod sa-pod -n dev >/dev/null 2>&1; then
  part 0 2 step12m2
  part 0 1 step12m2
  part 0 2 step12m2
  exit 0
fi
P=$(kubectl get pod sa-pod -n dev -o json)

sa=$(echo "$P" | jq -r '.spec.serviceAccountName // ""')
if [ "$sa" = "app-sa" ]; then part 2 2 q12c2; else part 0 2 step12m3 "${sa:-(none)}"; fi

# boolean: compare raw value, no // fallback
am=$(echo "$P" | jq -r '.spec.automountServiceAccountToken')
if [ "$am" = "false" ]; then part 1 1 q12c3; else part 0 1 step12m4; fi

if timeout 12 kubectl exec -n dev sa-pod -- ls /var/run/secrets/kubernetes.io/serviceaccount >/dev/null 2>&1; then
  part 0 2 step12m5
else
  # ls failing is only meaningful if the pod is actually up
  phase=$(echo "$P" | jq -r .status.phase)
  if [ "$phase" = "Running" ]; then part 2 2 q12c4; else part 0 2 step12m6 "$phase"; fi
fi
exit 0
