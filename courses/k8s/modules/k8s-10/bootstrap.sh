#!/bin/bash
# k8s-10 준비 — 클러스터 대기 + '고장난' 리소스 3종을 심는다(멱등). 학습자가 진단·수리한다.
#   ① Deployment shop : 이미지 태그 오타 → ImagePullBackOff
#   ② Service   shop  : selector 오타(app=shopX) → 엔드포인트 없음
#   ③ Deployment cart : 없는 ConfigMap(cart-config) 참조 → 컨테이너 생성 실패
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/work
for i in $(seq 1 80); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: shop, namespace: default }
spec:
  replicas: 2
  selector: { matchLabels: { app: shop } }
  template:
    metadata: { labels: { app: shop } }
    spec:
      containers:
        - name: web
          image: nginx:1.26-doesnotexist      # ← 고장 ①: 존재하지 않는 태그
          ports: [{ containerPort: 80 }]
---
apiVersion: v1
kind: Service
metadata: { name: shop, namespace: default }
spec:
  selector: { app: shopX }                     # ← 고장 ②: 셀렉터 오타 (실제는 app=shop)
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: cart, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: cart } }
  template:
    metadata: { labels: { app: cart } }
    spec:
      containers:
        - name: web
          image: nginx:1.26
          envFrom:
            - configMapRef: { name: cart-config }   # ← 고장 ③: 없는 ConfigMap
EOF
echo "PASS"
