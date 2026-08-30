#!/bin/bash
# Q8 Service (7점) — 스펙 + 엔드포인트 + 실제 DNS/HTTP 응답까지 항목별로 확인한다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
eps() { kubectl get endpoints "$1" -n app-prod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w; }

if kubectl get svc web-svc -n app-prod >/dev/null 2>&1; then
  S=$(kubectl get svc web-svc -n app-prod -o json)
  if [ "$(echo "$S" | jq -r .spec.type)" != ClusterIP ]; then part 0 1 step8m2 "web-svc" "ClusterIP"
  elif [ "$(echo "$S" | jq -r '.spec.ports[0].port')" != "80" ]; then part 0 1 step8m3 "web-svc" "80"
  else part 1 1 q8c1; fi
  n=$(eps web-svc)
  if [ "$n" -ge 3 ]; then part 1 1 q8c2; else part 0 1 step8m4 "web-svc" "$n"; fi
else
  part 0 1 step8m1 "web-svc"
  part 0 1 step8m1 "web-svc"
fi

if kubectl get svc web-np -n app-prod >/dev/null 2>&1; then
  N=$(kubectl get svc web-np -n app-prod -o json)
  if [ "$(echo "$N" | jq -r .spec.type)" = NodePort ]; then part 1 1 q8c3; else part 0 1 step8m2 "web-np" "NodePort"; fi
  np=$(echo "$N" | jq -r '.spec.ports[0].nodePort // ""')
  if [ "$np" = "30080" ]; then part 1 1 q8c4; else part 0 1 step8m5 "${np:-(없음)}"; fi
  n=$(eps web-np)
  if [ "$n" -ge 3 ]; then part 1 1 q8c5; else part 0 1 step8m4 "web-np" "$n"; fi
else
  part 0 1 step8m1 "web-np"
  part 0 1 step8m1 "web-np"
  part 0 1 step8m1 "web-np"
fi

# DNS + HTTP: client 파드에서 서비스 이름으로 응답이 와야 한다
if ! kubectl get pod client -n app-prod >/dev/null 2>&1; then
  part 0 2 step8m6
else
  body=$(timeout 15 kubectl exec -n app-prod client -- \
    wget -T 4 -q -O- http://web-svc.app-prod.svc.cluster.local:80/ 2>/dev/null | head -c 200)
  if echo "$body" | grep -qi nginx; then part 2 2 q8c6; else part 0 2 step8m7; fi
fi
exit 0
