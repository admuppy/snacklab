#!/bin/bash
# Q4 RBAC least privilege (6 pts) — verify effective permissions via auth can-i,
# so any rule notation passes as long as the outcome is right.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SA=system:serviceaccount:apps:ci-bot
can() { kubectl auth can-i "$1" "$2" -n apps --as="$SA" 2>/dev/null; }

if kubectl get role ci-role -n apps >/dev/null 2>&1; then part 1 1 q4c1; else part 0 1 step4m1; fi

RB=$(kubectl get rolebinding ci-bot-rb -n apps -o json 2>/dev/null)
if [ -z "$RB" ]; then
  part 0 1 step4m2
elif [ "$(echo "$RB" | jq -r '.roleRef.kind + "/" + .roleRef.name')" = "Role/ci-role" ]; then
  part 1 1 q4c2
else
  part 0 1 step4m3 "$(echo "$RB" | jq -r '.roleRef.kind + "/" + .roleRef.name')"
fi

miss=
for v in "get pods" "list pods" "get deployments.apps" "list deployments.apps" "update deployments.apps"; do
  set -- $v
  [ "$(can "$1" "$2")" = yes ] || { miss="$v"; break; }
done
if [ -z "$miss" ]; then part 2 2 q4c3; else part 0 2 step4m4 "$miss"; fi

over=
for v in "list secrets" "delete pods" "create deployments.apps" "delete deployments.apps"; do
  set -- $v
  [ "$(can "$1" "$2")" = no ] || { over="$v"; break; }
done
if [ -z "$over" ]; then part 2 2 q4c4; else part 0 2 step4m5 "$over"; fi
exit 0
