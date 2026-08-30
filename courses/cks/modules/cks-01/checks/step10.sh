#!/bin/bash
# Q10 Pod Security Admission (7 pts) — namespace label + a compliant, rolled-out pod.
# Old privileged pods surviving the label is the classic trap: we inspect the live pod.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

lbl=$(kubectl get ns restricted-ns \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
if [ "$lbl" = "restricted" ]; then part 2 2 q10c1; else part 0 2 step10m1 "${lbl:-none}"; fi

D=$(kubectl get deploy legacy -n restricted-ns -o json 2>/dev/null)
if [ -z "$D" ]; then
  part 0 3 step10m2
  part 0 2 step10m2
  exit 0
fi

# newest Running, non-terminating pod — the old privileged pod may linger as Terminating
pod=$(kubectl get pod -n restricted-ns -l app=legacy -o json 2>/dev/null | jq -r \
  '[.items[] | select(.status.phase=="Running" and (.metadata.deletionTimestamp|not))]
   | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty')
if [ -z "$pod" ]; then
  part 0 3 step10m3
else
  P=$(kubectl get pod "$pod" -n restricted-ns -o json | jq '.spec')
  C=$(echo "$P" | jq '.containers[0].securityContext // {}')
  bad=
  priv=$(echo "$C" | jq -r '.privileged // false')
  [ "$priv" = "false" ] || bad="privileged"
  seccomp=$(echo "$P" | jq -r '.securityContext.seccompProfile.type // ""')
  cseccomp=$(echo "$C" | jq -r '.seccompProfile.type // ""')
  [ "$seccomp" = "RuntimeDefault" ] || [ "$cseccomp" = "RuntimeDefault" ] || bad="${bad:-seccompProfile}"
  nonroot=$(echo "$P" | jq -r '.securityContext.runAsNonRoot // false')
  cnonroot=$(echo "$C" | jq -r '.runAsNonRoot // false')
  [ "$nonroot" = "true" ] || [ "$cnonroot" = "true" ] || bad="${bad:-runAsNonRoot}"
  # plain jq (no // fallback): false is falsy and would be swallowed by //
  [ "$(echo "$C" | jq -r '.allowPrivilegeEscalation')" = "false" ] || bad="${bad:-allowPrivilegeEscalation}"
  echo "$C" | jq -e '.capabilities.drop | index("ALL")' >/dev/null 2>&1 || bad="${bad:-capabilities.drop}"
  if [ -z "$bad" ]; then part 3 3 q10c2; else part 0 3 step10m4 "$bad"; fi
fi

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" -ge 1 ]; then part 2 2 q10c3; else part 0 2 step10m5; fi
exit 0
