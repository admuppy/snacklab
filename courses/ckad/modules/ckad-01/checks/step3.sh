#!/bin/bash
# Q3 init container (6 pts) — init/main share a volume, and the file the init
# container prepared must actually be served over HTTP.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get pod web-init -n dev >/dev/null 2>&1; then
  part 0 1 step3m1
  part 0 2 step3m1
  part 0 1 step3m1
  part 0 2 step3m1
  exit 0
fi
P=$(kubectl get pod web-init -n dev -o json)

ini=$(echo "$P" | jq -r '.spec.initContainers[0].name // ""')
if [ -n "$ini" ]; then part 1 1 q3c1; else part 0 1 step3m2; fi

# same volume: init mounts it at /work, main container at the nginx docroot
vol=$(echo "$P" | jq -r '.spec.initContainers[0].volumeMounts[]? | select(.mountPath=="/work") | .name' | head -1)
okm=0
if [ -n "$vol" ]; then
  m=$(echo "$P" | jq -r --arg v "$vol" '.spec.containers[0].volumeMounts[]? | select(.name==$v) | .mountPath' | head -1)
  [ "$m" = "/usr/share/nginx/html" ] && okm=1
fi
if [ $okm = 1 ]; then part 2 2 q3c2; else part 0 2 step3m3; fi

ready=$(echo "$P" | jq -r '.status.conditions[]? | select(.type=="Ready") | .status')
if [ "$ready" = "True" ]; then part 1 1 q3c3; else part 0 1 step3m4; fi

ip=$(echo "$P" | jq -r '.status.podIP // ""')
if [ -z "$ip" ]; then
  part 0 2 step3m4
elif timeout 15 kubectl exec -n dev client -- wget -T 4 -q -O- "http://$ip:80/" 2>/dev/null | grep -q "ready-to-serve"; then
  part 2 2 q3c4
else
  part 0 2 step3m5
fi
exit 0
