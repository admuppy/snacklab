#!/bin/bash
# Q5 canary (6 pts) — canary deployment spec, service actually picking up the
# canary pod, and the 3:1 stable/canary split behind the service.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get deploy shop-canary -n prod >/dev/null 2>&1; then
  part 0 2 step5m1
  part 0 1 step5m1
  part 0 1 step5m1
  part 0 2 step5m1
  exit 0
fi
C=$(kubectl get deploy shop-canary -n prod -o json)
img=$(echo "$C" | jq -r '.spec.template.spec.containers[0].image // ""')
rep=$(echo "$C" | jq -r '.spec.replicas // ""')
okimg=0
case "$img" in nginx:1.26|docker.io/nginx:1.26|docker.io/library/nginx:1.26) okimg=1 ;; esac
if [ $okimg = 1 ] && [ "$rep" = "1" ]; then part 2 2 q5c1; else part 0 2 step5m2 "$img" "${rep:-(none)}"; fi

lab=$(echo "$C" | jq -r '.spec.template.metadata.labels | "\(.app // "")/\(.track // "")"')
if [ "$lab" = "shop/canary" ]; then part 1 1 q5c2; else part 0 1 step5m3 "$lab"; fi

S=$(kubectl get deploy shop -n prod -o json 2>/dev/null)
srep=$(echo "$S" | jq -r '.spec.replicas // ""')
sready=$(echo "$S" | jq -r '.status.readyReplicas // 0')
if [ "$srep" = "3" ] && [ "$sready" = "3" ]; then part 1 1 q5c3; else part 0 1 step5m4 "${srep:-(none)}" "$sready"; fi

# the service must see exactly 4 endpoints, one of which is the canary pod
cip=$(kubectl get pod -n prod -l app=shop,track=canary -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
eps=$(kubectl get endpoints shop-svc -n prod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
n=$(echo "$eps" | wc -w)
if [ -n "$cip" ] && echo " $eps " | grep -q " $cip " && [ "$n" = "4" ]; then
  part 2 2 q5c4
else
  part 0 2 step5m5 "$n"
fi
exit 0
