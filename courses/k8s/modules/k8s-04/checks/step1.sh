#!/bin/bash
# step1: Deployment 'web' 의 파드가 livenessProbe 를 갖고 Running 인지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
pod=$(kubectl get pod -l app=web -n default -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$pod" ] || { labmsg step1m1; exit 1; }
kubectl get pod "$pod" -n default -o json > /tmp/p.json 2>/dev/null
jq -e '.spec.containers[0].livenessProbe' /tmp/p.json >/dev/null \
  || { labmsg step1m2; exit 1; }
labmsg step1m3 "$pod"
