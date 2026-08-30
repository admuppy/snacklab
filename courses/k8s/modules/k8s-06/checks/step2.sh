#!/bin/bash
# step2: 노드에 lab=demo:NoSchedule 테인트 + 파드 'tolerant' 가 그 테인트를 톨러레이트하며 Running
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
eff=$(kubectl get node "$node" -o json 2>/dev/null | jq -r '.spec.taints[]? | select(.key=="lab") | .effect')
[ "$eff" = "NoSchedule" ] || { labmsg step2m1 "$node"; exit 1; }
kubectl get pod tolerant -n default -o json > /tmp/t.json 2>/dev/null || { labmsg step2m2; exit 1; }
jq -e '.spec.tolerations[]? | select(.key=="lab")' /tmp/t.json >/dev/null || { labmsg step2m3; exit 1; }
phase=$(jq -r '.status.phase' /tmp/t.json)
[ "$phase" = "Running" ] || { labmsg step2m4 "$phase"; exit 1; }
labmsg step2m5
