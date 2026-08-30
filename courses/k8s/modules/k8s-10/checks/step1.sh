#!/bin/bash
# step1: Deployment 'shop' 이 이미지 수리 후 2개 레플리카 모두 Ready 인지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get deploy shop -n default >/dev/null 2>&1 || { labmsg step1m1; exit 1; }
img=$(kubectl get deploy shop -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$img" in
  *doesnotexist*) labmsg step1m2 "$img"; exit 1 ;;
esac
rdy=$(kubectl get deploy shop -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${rdy:-0}" -ge 2 ] 2>/dev/null || { labmsg step1m3 "${rdy:-0}"; exit 1; }
labmsg step1m4 "$img"
