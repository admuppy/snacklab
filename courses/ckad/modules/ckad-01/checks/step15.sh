#!/bin/bash
# Q15 Ingress (6 pts) — no controller in this environment (k3s traefik is
# disabled), so grade the resource spec item by item, like the real exam.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get ingress web-ing -n prod >/dev/null 2>&1; then
  part 0 1 step15m1
  part 0 1 step15m1
  part 0 2 step15m1
  part 0 2 step15m1
  exit 0
fi
I=$(kubectl get ingress web-ing -n prod -o json)
part 1 1 q15c1     # ingress exists

if echo "$I" | jq -e '.spec.rules[] | select(.host=="shop.example.com")' >/dev/null 2>&1; then
  part 1 1 q15c2
else
  part 0 1 step15m2
fi

path_ok() {  # $1=path $2=service -> 0 if a Prefix rule routes $1 to $2:80
  echo "$I" | jq -e --arg p "$1" --arg s "$2" '
    .spec.rules[] | select(.host=="shop.example.com") | .http.paths[]
    | select(.path==$p and .pathType=="Prefix"
        and .backend.service.name==$s
        and (.backend.service.port.number==80 or .backend.service.port.name=="80"))
  ' >/dev/null 2>&1
}
if path_ok "/" frontend-svc; then part 2 2 q15c3; else part 0 2 step15m3 "/" "frontend-svc"; fi
if path_ok "/shop" shop-svc; then part 2 2 q15c4; else part 0 2 step15m3 "/shop" "shop-svc"; fi
exit 0
