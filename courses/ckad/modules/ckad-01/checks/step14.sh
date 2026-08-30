#!/bin/bash
# Q14 services (7 pts) — spec + endpoints + real traffic: service DNS from a
# pod in another namespace, and the node port from the node itself.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
eps() { kubectl get endpoints "$1" -n prod -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w; }

if kubectl get svc frontend-svc -n prod >/dev/null 2>&1; then
  S=$(kubectl get svc frontend-svc -n prod -o json)
  if [ "$(echo "$S" | jq -r .spec.type)" != "ClusterIP" ]; then part 0 1 step14m2 "frontend-svc" "ClusterIP"
  elif [ "$(echo "$S" | jq -r '.spec.ports[0].port')" != "80" ]; then part 0 1 step14m3 "frontend-svc"
  elif [ "$(eps frontend-svc)" -lt 1 ]; then part 0 1 step14m4 "frontend-svc"
  else part 1 1 q14c1; fi
else
  part 0 1 step14m1 "frontend-svc"
fi

if kubectl get svc frontend-np -n prod >/dev/null 2>&1; then
  N=$(kubectl get svc frontend-np -n prod -o json)
  if [ "$(echo "$N" | jq -r .spec.type)" = "NodePort" ]; then part 1 1 q14c2; else part 0 1 step14m2 "frontend-np" "NodePort"; fi
  np=$(echo "$N" | jq -r '.spec.ports[0].nodePort // ""')
  if [ "$np" = "30080" ]; then part 1 1 q14c3; else part 0 1 step14m5 "${np:-(none)}"; fi
  if [ "$(eps frontend-np)" -ge 1 ]; then part 1 1 q14c4; else part 0 1 step14m4 "frontend-np"; fi
else
  part 0 1 step14m1 "frontend-np"
  part 0 1 step14m1 "frontend-np"
  part 0 1 step14m1 "frontend-np"
fi

# real traffic 1: cross-namespace service DNS from the client pod in dev
if ! kubectl get pod client -n dev >/dev/null 2>&1; then
  part 0 2 step14m6
else
  body=$(timeout 15 kubectl exec -n dev client -- \
    wget -T 4 -q -O- http://frontend-svc.prod.svc.cluster.local:80/ 2>/dev/null | head -c 200)
  if echo "$body" | grep -qi nginx; then part 2 2 q14c5; else part 0 2 step14m7; fi
fi

# real traffic 2: the node port answers on the node itself (single-node k3s,
# so localhost IS the node; the grading shell runs on it)
if timeout 10 curl -fsS -m 4 http://127.0.0.1:30080/ 2>/dev/null | grep -qi nginx; then
  part 1 1 q14c6
else
  part 0 1 step14m8
fi
exit 0
