#!/bin/bash
# step3: 누락된 ConfigMap 'cart-config' 를 만들어 Deployment 'cart' 가 Ready 가 되었는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get cm cart-config -n default >/dev/null 2>&1 \
  || { labmsg step3m1; exit 1; }
rdy=$(kubectl get deploy cart -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${rdy:-0}" -ge 1 ] 2>/dev/null \
  || { labmsg step3m2 "${rdy:-0}"; exit 1; }
labmsg step3m3
