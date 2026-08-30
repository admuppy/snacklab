#!/bin/bash
# Q11 SecurityContext (6 pts) — each hardening field, then proof: the process
# really runs as uid 1000. NOTE: never use jq's `// ""` on boolean fields —
# it swallows `false` (allowPrivilegeEscalation) — compare the raw value.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get pod secure-app -n dev >/dev/null 2>&1; then
  part 0 1 step11m1
  part 0 1 step11m1
  part 0 1 step11m1
  part 0 1 step11m1
  part 0 2 step11m1
  exit 0
fi
P=$(kubectl get pod secure-app -n dev -o json)
C=$(echo "$P" | jq '.spec.containers[0]')
# fields may sit on the pod or the container securityContext — accept either
pj() { echo "$P" | jq -r ".spec.securityContext.$1"; }
cj() { echo "$C" | jq -r ".securityContext.$1"; }
either() { [ "$(pj "$1")" = "$2" ] || [ "$(cj "$1")" = "$2" ]; }

if either runAsUser 1000 && either runAsNonRoot true; then part 1 1 q11c1; else part 0 1 step11m2; fi
if [ "$(cj allowPrivilegeEscalation)" = "false" ]; then part 1 1 q11c2; else part 0 1 step11m3; fi
if [ "$(cj readOnlyRootFilesystem)" = "true" ]; then part 1 1 q11c3; else part 0 1 step11m4; fi
if echo "$C" | jq -e '.securityContext.capabilities.drop | index("ALL")' >/dev/null 2>&1; then
  part 1 1 q11c4
else
  part 0 1 step11m5
fi

phase=$(echo "$P" | jq -r .status.phase)
uid=$(timeout 12 kubectl exec -n dev secure-app -- id -u 2>/dev/null)
if [ "$phase" = "Running" ] && [ "$uid" = "1000" ]; then part 2 2 q11c5; else part 0 2 step11m6 "$phase" "${uid:-(none)}"; fi
exit 0
