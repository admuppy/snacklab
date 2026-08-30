#!/bin/bash
# step1: ServiceAccount 'deployer' 가 default 네임스페이스에 있는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get serviceaccount deployer -n default >/dev/null 2>&1 \
  || { labmsg step1m1; exit 1; }
labmsg step1m2
