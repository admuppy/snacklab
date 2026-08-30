#!/bin/bash
# Q16 NetworkPolicy (7 pts) — policy shape plus what actually matters: real
# traffic (k3s enforces NetworkPolicy via kube-router).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get netpol cache-guard -n dev >/dev/null 2>&1; then
  part 0 1 step16m1
  part 0 1 step16m1
  part 0 1 step16m1
  part 0 2 step16m1
  part 0 2 step16m1
  exit 0
fi
N=$(kubectl get netpol cache-guard -n dev -o json)
part 1 1 q16c1     # policy exists

if [ "$(echo "$N" | jq -r '.spec.podSelector.matchLabels.app // ""')" = "cache" ]; then
  part 1 1 q16c2
else
  part 0 1 step16m2
fi

if echo "$N" | jq -e '.spec.ingress[0].from[] | select(.podSelector.matchLabels.role=="client")' >/dev/null 2>&1; then
  part 1 1 q16c3
else
  part 0 1 step16m3
fi

ip=$(kubectl get pod cache -n dev -o jsonpath='{.status.podIP}' 2>/dev/null)
missp=
for p in client intruder; do
  kubectl get pod "$p" -n dev >/dev/null 2>&1 || missp="$p"
done
if [ -z "$ip" ]; then
  part 0 2 step16m4
  part 0 2 step16m4
elif [ -n "$missp" ]; then
  part 0 2 step16m5 "$missp"
  part 0 2 step16m5 "$missp"
else
  if timeout 15 kubectl exec -n dev client -- wget -T 4 -q -O- "http://$ip:80/" >/dev/null 2>&1; then
    part 2 2 q16c4
  else
    part 0 2 step16m6
  fi
  if timeout 12 kubectl exec -n dev intruder -- wget -T 3 -q -O- "http://$ip:80/" >/dev/null 2>&1; then
    part 0 2 step16m7
  else
    part 2 2 q16c5
  fi
fi
exit 0
