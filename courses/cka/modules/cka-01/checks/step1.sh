#!/bin/bash
# Q1 RBAC (5 pts) — object names AND the effectively granted permissions.
# Permissions go through `auth can-i`, so any rule spelling that yields the right
# access passes. Rebalanced 7→5 (2026-08-06) to make room for Q16/Q17: the three
# object-existence parts collapsed into one.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SA=system:serviceaccount:app-prod:deploy-bot
can() { kubectl auth can-i "$1" "$2" -n "$3" --as="$SA" 2>/dev/null; }

if ! kubectl get sa deploy-bot -n app-prod >/dev/null 2>&1; then part 0 1 step1m1
elif ! kubectl get role pod-reader -n app-prod >/dev/null 2>&1; then part 0 1 step1m2
elif ! kubectl get rolebinding deploy-bot-rb -n app-prod >/dev/null 2>&1; then part 0 1 step1m3
else part 1 1 q1a1; fi

miss=
for v in "list pods" "watch pods" "get deployments.apps" "list deployments.apps"; do
  set -- $v
  [ "$(can "$1" "$2" app-prod)" = yes ] || { miss="$v"; break; }
done
if [ -z "$miss" ]; then part 2 2 q1c4; else part 0 2 step1m4 "$miss"; fi

# Over-permission is a deduction — must stay read-only and namespace-scoped
over=
[ "$(can delete pods app-prod)" = no ] || over="delete pods"
[ -n "$over" ] || { [ "$(can create pods app-prod)" = no ] || over="create pods"; }
if [ -z "$over" ]; then part 1 1 q1c5; else part 0 1 step1m5 "$over"; fi

if [ "$(can list pods default)" = no ]; then part 1 1 q1c6; else part 0 1 step1m6; fi
exit 0
