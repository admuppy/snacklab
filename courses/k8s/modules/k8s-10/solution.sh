#!/bin/bash
# k8s-10 모범답안 — 3중 장애 수리 (멱등)
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# ① 이미지 태그 수리 (ImagePullBackOff → 유효 태그)
kubectl set image deploy/shop web=nginx:1.26
kubectl rollout status deploy/shop --timeout=120s

# ② 서비스 셀렉터 수리 (app=shopX → app=shop)
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
kubectl get endpoints shop

# ③ 누락된 ConfigMap 생성 → cart 파드 기동
kubectl create configmap cart-config \
  --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout status deploy/cart --timeout=120s

kubectl get deploy,svc,endpoints
echo "solution applied"
