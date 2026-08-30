#!/bin/bash
# k8s-01 모범답안 — 멱등하게 재실행 가능
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: Deployment 생성 (3 레플리카)
kubectl create deployment web --image=nginx:1.25 --replicas=3 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout status deploy/web --timeout=120s

# step2: 롤링 업데이트 (컨테이너 전체 '*=' 로 이미지 교체)
kubectl set image deploy/web '*=nginx:1.26'
kubectl rollout status deploy/web --timeout=120s

# step3: 직전 리비전(nginx:1.25)으로 롤백
kubectl rollout undo deploy/web
kubectl rollout status deploy/web --timeout=120s

echo "solution applied"
