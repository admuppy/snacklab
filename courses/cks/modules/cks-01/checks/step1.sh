#!/bin/bash
# Q1 NetworkPolicy (7 pts) — grade the policy objects AND live traffic
# (k3s enforces NetworkPolicy via kube-router).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

haveD=0; haveA=0
if kubectl get netpol deny-all -n prod >/dev/null 2>&1; then haveD=1; part 1 1 q1c1; else part 0 1 step1m1 "deny-all"; fi
if kubectl get netpol allow-frontend -n prod >/dev/null 2>&1; then haveA=1; part 1 1 q1c2; else part 0 1 step1m1 "allow-frontend"; fi

if [ $haveD = 1 ]; then
  D=$(kubectl get netpol deny-all -n prod -o json)
  if [ "$(echo "$D" | jq -r '.spec.podSelector | keys | length')" != "0" ]; then part 0 1 step1m2
  elif ! echo "$D" | jq -e '.spec.policyTypes | index("Ingress")' >/dev/null 2>&1; then part 0 1 step1m3
  else part 1 1 q1c3; fi
else
  part 0 1 step1m1 "deny-all"
fi

if [ $haveA = 1 ]; then
  A=$(kubectl get netpol allow-frontend -n prod -o json)
  if [ "$(echo "$A" | jq -r '.spec.podSelector.matchLabels.app // ""')" != "backend" ]; then part 0 1 step1m4
  elif ! echo "$A" | jq -e '.spec.ingress[0].from[] | select(.podSelector.matchLabels.app=="frontend")' >/dev/null 2>&1; then part 0 1 step1m5
  else part 1 1 q1c4; fi
else
  part 0 1 step1m1 "allow-frontend"
fi

# live-traffic verdict against the backend pod IP
ip=$(kubectl get pod backend -n prod -o jsonpath='{.status.podIP}' 2>/dev/null)
missp=
for p in frontend other; do
  kubectl get pod "$p" -n prod >/dev/null 2>&1 || missp="$p"
done
if [ -z "$ip" ]; then
  part 0 2 step1m6
  part 0 1 step1m6
elif [ -n "$missp" ]; then
  part 0 2 step1m7 "$missp"
  part 0 1 step1m7 "$missp"
else
  if timeout 15 kubectl exec -n prod frontend -- wget -T 4 -q -O- "http://$ip:80/" >/dev/null 2>&1; then
    part 2 2 q1c5
  else
    part 0 2 step1m8
  fi
  if timeout 12 kubectl exec -n prod other -- wget -T 3 -q -O- "http://$ip:80/" >/dev/null 2>&1; then
    part 0 1 step1m9
  else
    part 1 1 q1c6
  fi
fi
exit 0
