#!/bin/bash
# step1: 노드에 disktype=ssd 레이블 + 파드 'affine' 이 nodeAffinity 로 그 노드에 스케줄되어 Running
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
lbl=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.disktype}' 2>/dev/null)
[ "$lbl" = "ssd" ] || { labmsg step1m1 "$node"; exit 1; }
kubectl get pod affine -n default -o json > /tmp/a.json 2>/dev/null || { labmsg step1m2; exit 1; }
jq -e '.spec.affinity.nodeAffinity' /tmp/a.json >/dev/null || { labmsg step1m3; exit 1; }
phase=$(jq -r '.status.phase' /tmp/a.json)
[ "$phase" = "Running" ] || { labmsg step1m4 "$phase"; exit 1; }
labmsg step1m5
