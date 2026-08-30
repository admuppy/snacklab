#!/bin/bash
# Q14 엔드포인트가 비어 있는 Service (10점) — 셀렉터와 targetPort 두 곳이 어긋나 있다.
# 최종 판정은 "실제 HTTP 응답" 으로 한다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get svc cache-svc -n broken >/dev/null 2>&1; then
  part 0 2 step14m1
  part 0 1 step14m1
  part 0 4 step14m1
  part 0 3 step14m1
  exit 0
fi
part 2 2 q14c1     # 서비스 유지
S=$(kubectl get svc cache-svc -n broken -o json)
p=$(echo "$S" | jq -r '.spec.ports[0].port // ""')
if [ "$p" = "80" ]; then part 1 1 q14c2; else part 0 1 step14m2 "${p:-(없음)}"; fi

n=$(kubectl get endpoints cache-svc -n broken -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$n" -ge 1 ]; then part 4 4 q14c3; else part 0 4 step14m3; fi

if ! kubectl get pod client -n app-prod >/dev/null 2>&1; then
  part 0 3 step14m4
else
  body=$(timeout 15 kubectl exec -n app-prod client -- \
    wget -T 4 -q -O- http://cache-svc.broken.svc.cluster.local:80/ 2>/dev/null | head -c 200)
  if echo "$body" | grep -qi nginx; then part 3 3 q14c4; else part 0 3 step14m5; fi
fi
exit 0
