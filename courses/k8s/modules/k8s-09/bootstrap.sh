#!/bin/bash
# k8s-09 준비 — 클러스터 대기 + 베이스라인(서버 web + 서비스 + 클라이언트 파드) 배포(멱등).
# 학습자는 NetworkPolicy 로 이 사이 통신을 차단/허용하는 데 집중한다.
# k3s 는 기본 NetworkPolicy 컨트롤러(kube-router)로 정책을 실제 강제한다.
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/work
for i in $(seq 1 80); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done
kubectl create deployment web --image=nginx:1.26 --dry-run=client -o yaml | kubectl apply -f -
kubectl expose deployment web --name=web --port=80 --target-port=80 \
  --dry-run=client -o yaml | kubectl apply -f -
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: client, namespace: default, labels: { app: client } }
spec:
  containers:
    - name: client
      image: busybox:1.36
      args: ["/bin/sh","-c","sleep 3600"]
      resources: { requests: { cpu: "10m", memory: "16Mi" } }
EOF
kubectl rollout status deploy/web --timeout=120s >/dev/null 2>&1 || true
kubectl wait --for=condition=Ready pod/client --timeout=90s >/dev/null 2>&1 || true
echo "PASS"
