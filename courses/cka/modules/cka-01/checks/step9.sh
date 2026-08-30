#!/bin/bash
# Q9 NetworkPolicy (7점) — 정책 객체 모양만이 아니라 "실제로 막히는지" 를 통신으로 판정한다.
# (k3s 는 kube-router 로 NetworkPolicy 를 실제 강제한다.)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

haveD=0; haveA=0
if kubectl get netpol default-deny -n app-prod >/dev/null 2>&1; then haveD=1; part 1 1 q9c1; else part 0 1 step9m1 "default-deny"; fi
if kubectl get netpol allow-client -n app-prod >/dev/null 2>&1; then haveA=1; part 1 1 q9c2; else part 0 1 step9m1 "allow-client"; fi

if [ $haveD = 1 ]; then
  D=$(kubectl get netpol default-deny -n app-prod -o json)
  if [ "$(echo "$D" | jq -r '.spec.podSelector | keys | length')" != "0" ]; then part 0 1 step9m2
  elif ! echo "$D" | jq -e '.spec.policyTypes | index("Ingress")' >/dev/null 2>&1; then part 0 1 step9m3
  else part 1 1 q9c3; fi
else
  part 0 1 step9m1 "default-deny"
fi

if [ $haveA = 1 ]; then
  A=$(kubectl get netpol allow-client -n app-prod -o json)
  if [ "$(echo "$A" | jq -r '.spec.podSelector.matchLabels.app // ""')" != "web" ]; then part 0 1 step9m4
  elif ! echo "$A" | jq -e '.spec.ingress[0].from[] | select(.podSelector.matchLabels.role=="client")' >/dev/null 2>&1; then part 0 1 step9m5
  else part 1 1 q9c4; fi
else
  part 0 1 step9m1 "allow-client"
fi

# 통신 판정: web 파드 IP 로 직접 (Service 유무와 무관하게 정책만 본다)
ip=$(kubectl get pod -n app-prod -l app=web -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
missp=
for p in client intruder; do
  kubectl get pod "$p" -n app-prod >/dev/null 2>&1 || missp="$p"
done
if [ -z "$ip" ]; then
  part 0 2 step9m6
  part 0 1 step9m6
elif [ -n "$missp" ]; then
  part 0 2 step9m7 "$missp"
  part 0 1 step9m7 "$missp"
else
  if timeout 15 kubectl exec -n app-prod client -- wget -T 4 -q -O- "http://$ip:80/" >/dev/null 2>&1; then
    part 2 2 q9c5
  else
    part 0 2 step9m8
  fi
  if timeout 12 kubectl exec -n app-prod intruder -- wget -T 3 -q -O- "http://$ip:80/" >/dev/null 2>&1; then
    part 0 1 step9m9
  else
    part 1 1 q9c6
  fi
fi
exit 0
