#!/bin/bash
# 준비 — 파드 안 k3s 클러스터 API + 노드 Ready 대기(멱등). 사전 리소스 없음.
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/work
for i in $(seq 1 80); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done
kubectl wait --for=condition=Ready node --all --timeout=20s >/dev/null 2>&1 || true
echo "PASS"
