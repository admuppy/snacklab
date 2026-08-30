#!/bin/bash
# k8s-02 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: ClusterIP 로 노출
kubectl expose deployment web --name=web --port=80 --target-port=80 \
  --dry-run=client -o yaml | kubectl apply -f -

# step2: NodePort 로 노출
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80 \
  --dry-run=client -o yaml | kubectl apply -f -

# step3: Headless Service (clusterIP: None)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-h
  namespace: default
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
EOF

# 확인: 클러스터 내부에서 DNS 로 접근 (선택)
kubectl run curl-test --image=busybox:1.36 --restart=Never --rm -i --quiet -- \
  sh -c 'wget -qO- --timeout=3 http://web.default.svc.cluster.local | head -1' || true

echo "solution applied"
