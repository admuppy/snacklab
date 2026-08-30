#!/bin/bash
# Q9 SecurityContext hardening (7 pts) — accept the settings at container level
# (pod level counts for the fields that exist there: runAsNonRoot / runAsUser).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

D=$(kubectl get deploy secure-app -n apps -o json 2>/dev/null)
if [ -z "$D" ]; then
  part 0 2 step9m1
  for i in 1 2 3 4 5; do part 0 1 step9m1; done
  exit 0
fi
P=$(echo "$D" | jq '.spec.template.spec')
C=$(echo "$P" | jq '.containers[0].securityContext // {}')

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" -ge 1 ]; then part 2 2 q9c1; else part 0 2 step9m2; fi

v() { echo "$C" | jq -r "$1 // \"\""; }
pv() { echo "$P" | jq -r ".securityContext$1 // \"\""; }

if [ "$(v .runAsNonRoot)" = "true" ] || [ "$(pv .runAsNonRoot)" = "true" ]; then part 1 1 q9c2; else part 0 1 step9m3; fi
if [ "$(v .runAsUser)" = "10001" ] || [ "$(pv .runAsUser)" = "10001" ]; then part 1 1 q9c3; else part 0 1 step9m4; fi
# plain jq (no // fallback): false is falsy, so `false // ""` would erase the value
if [ "$(echo "$C" | jq -r '.allowPrivilegeEscalation')" = "false" ]; then part 1 1 q9c4; else part 0 1 step9m5; fi
if echo "$C" | jq -e '.capabilities.drop | index("ALL")' >/dev/null 2>&1; then part 1 1 q9c5; else part 0 1 step9m6; fi
if [ "$(v .readOnlyRootFilesystem)" = "true" ]; then part 1 1 q9c6; else part 0 1 step9m7; fi
exit 0
