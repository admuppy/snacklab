#!/bin/bash
# k8s-02 준비 — 클러스터 대기 + 백엔드 Deployment 'web'(app=web, 2 레플리카) 배포(멱등).
# 학습자는 이 Deployment 를 여러 종류의 Service 로 노출하는 데 집중한다.
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/work
for i in $(seq 1 80); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done
kubectl create deployment web --image=nginx:1.26 --replicas=2 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout status deploy/web --timeout=120s >/dev/null 2>&1 || true
echo "PASS"
