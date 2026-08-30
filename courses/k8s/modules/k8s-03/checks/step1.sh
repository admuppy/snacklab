#!/bin/bash
# step1: ConfigMap 'app-config' 에 APP_MODE, APP_GREETING 키가 있는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get cm app-config -n default >/dev/null 2>&1 || { labmsg step1m1; exit 1; }
for k in APP_MODE APP_GREETING; do
  v=$(kubectl get cm app-config -n default -o jsonpath="{.data.$k}" 2>/dev/null)
  [ -n "$v" ] || { labmsg step1m2 "$k"; exit 1; }
done
labmsg step1m3
