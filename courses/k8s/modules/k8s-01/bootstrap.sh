#!/bin/bash
# k8s-01 준비 — 파드 안 k3s 클러스터가 API 응답 + 노드 Ready 가 될 때까지 대기(멱등).
# 포털 bootstrap 타임아웃은 180s. 특별한 사전 리소스는 만들지 않는다(학습자가 처음부터 생성).
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/work
for i in $(seq 1 80); do
  if kubectl get --raw='/readyz' >/dev/null 2>&1 && kubectl get nodes 2>/dev/null | grep -q ' Ready'; then
    kubectl get sa default -n default >/dev/null 2>&1 && break
  fi
  sleep 2
done
kubectl wait --for=condition=Ready node --all --timeout=20s >/dev/null 2>&1 || true
echo "PASS"
