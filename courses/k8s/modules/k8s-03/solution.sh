#!/bin/bash
# k8s-03 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: ConfigMap
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap" \
  --dry-run=client -o yaml | kubectl apply -f -

# step2: Secret (Opaque)
kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD='s3cr3t-pw' \
  --dry-run=client -o yaml | kubectl apply -f -

# step3: ConfigMap 을 env(envFrom), Secret 을 볼륨으로 소비하는 파드
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: default
spec:
  containers:
    - name: app
      image: nginx:1.26
      envFrom:
        - configMapRef: { name: app-config }
      volumeMounts:
        - name: secret-vol
          mountPath: /etc/app-secret
          readOnly: true
  volumes:
    - name: secret-vol
      secret: { secretName: app-secret }
EOF
kubectl wait --for=condition=Ready pod/app --timeout=60s

# 확인
kubectl exec app -- printenv APP_MODE APP_GREETING
kubectl exec app -- ls /etc/app-secret
echo "solution applied"
