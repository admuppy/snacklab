#!/bin/bash
# Q10 ConfigMap / Secret (7 pts) — resource values plus what the container
# actually sees: the env var and the mounted secret file.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ "$(kubectl get cm app-config -n dev -o jsonpath='{.data.mode}' 2>/dev/null)" = "production" ] \
  && [ "$(kubectl get cm app-config -n dev -o jsonpath='{.data.timeout}' 2>/dev/null)" = "30" ]; then
  part 1 1 q10c1
else
  part 0 1 step10m1
fi

u=$(kubectl get secret db-cred -n dev -o jsonpath='{.data.user}' 2>/dev/null | base64 -d 2>/dev/null)
p=$(kubectl get secret db-cred -n dev -o jsonpath='{.data.pass}' 2>/dev/null | base64 -d 2>/dev/null)
if [ "$u" = "admin" ] && [ "$p" = "S3cret1" ]; then part 1 1 q10c2; else part 0 1 step10m2; fi

if ! kubectl get pod webapp -n dev >/dev/null 2>&1; then
  part 0 1 step10m3
  part 0 2 step10m3
  part 0 2 step10m3
  exit 0
fi
P=$(kubectl get pod webapp -n dev -o json)

# env must come from the ConfigMap key, not a hard-coded literal
src=$(echo "$P" | jq -r '.spec.containers[0].env[]? | select(.name=="APP_MODE") | .valueFrom.configMapKeyRef | "\(.name // "")/\(.key // "")"' | head -1)
if [ "$src" = "app-config/mode" ]; then part 1 1 q10c3; else part 0 1 step10m4; fi

if [ "$(timeout 12 kubectl exec -n dev webapp -- sh -c 'echo $APP_MODE' 2>/dev/null)" = "production" ]; then
  part 2 2 q10c4
else
  part 0 2 step10m5
fi

if [ "$(timeout 12 kubectl exec -n dev webapp -- cat /etc/creds/user 2>/dev/null)" = "admin" ]; then
  part 2 2 q10c5
else
  part 0 2 step10m6
fi
exit 0
