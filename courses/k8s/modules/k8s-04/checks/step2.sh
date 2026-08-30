#!/bin/bash
# step2: 파드에 readinessProbe 가 정의되어 있는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
pod=$(kubectl get pod -l app=web -n default -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$pod" ] || { labmsg step2m1; exit 1; }
kubectl get pod "$pod" -n default -o json > /tmp/p.json 2>/dev/null
jq -e '.spec.containers[0].readinessProbe' /tmp/p.json >/dev/null \
  || { labmsg step2m2; exit 1; }
labmsg step2m3 "$pod"
