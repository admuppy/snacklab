#!/bin/bash
# Q10 Ingress (6점) — 이 환경에는 Ingress 컨트롤러가 없다(k3s traefik 비활성). 실제 라우팅 대신
# 시험과 동일하게 "리소스를 규격대로 작성했는가" 를 항목별로 본다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get ingress web-ing -n app-prod >/dev/null 2>&1; then
  for i in 1 2 3 4 5 6; do part 0 1 step10m1; done
  exit 0
fi
I=$(kubectl get ingress web-ing -n app-prod -o json)
part 1 1 q10c1     # 인그레스 존재

if echo "$I" | jq -e '.spec.rules[] | select(.host=="shop.example.com")' >/dev/null 2>&1; then
  part 1 1 q10c2
else
  part 0 1 step10m2
fi

R=$(echo "$I" | jq '.spec.rules[] | select(.host=="shop.example.com") | .http.paths[] | select(.path=="/")' 2>/dev/null)
if [ -n "$R" ]; then
  part 1 1 q10c3
  pt=$(echo "$R" | jq -r '.pathType // ""')
  if [ "$pt" = "Prefix" ]; then part 1 1 q10c4; else part 0 1 step10m4 "${pt:-(없음)}"; fi
  bs=$(echo "$R" | jq -r '.backend.service.name // ""')
  if [ "$bs" = "web-svc" ]; then part 1 1 q10c5; else part 0 1 step10m5 "${bs:-(없음)}"; fi
  port=$(echo "$R" | jq -r '.backend.service.port.number // .backend.service.port.name // ""')
  if [ "$port" = "80" ]; then part 1 1 q10c6; else part 0 1 step10m6 "${port:-(없음)}"; fi
else
  part 0 1 step10m3
  part 0 1 step10m3
  part 0 1 step10m3
  part 0 1 step10m3
fi
exit 0
