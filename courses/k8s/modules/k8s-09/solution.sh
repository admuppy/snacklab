#!/bin/bash
# k8s-09 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: 베이스라인 확인 + 기록 (정책 없음)
kubectl delete netpol default-deny web-allow-client -n default --ignore-not-found
mkdir -p ~/work
# web/client may still be starting right after bootstrap — wait, then retry the
# baseline fetch until it lands. (In `a && b`, set -e ignores a's failure, so a
# single unguarded wget can silently leave an empty baseline.txt.)
kubectl rollout status deploy/web --timeout=120s
kubectl wait --for=condition=Ready pod/client --timeout=120s
for i in $(seq 1 10); do
  kubectl exec client -- wget -q -T 3 -t 1 -O- http://web > ~/work/baseline.txt 2>/dev/null || true
  [ -s ~/work/baseline.txt ] && break
  sleep 3
done
[ -s ~/work/baseline.txt ] && echo "baseline OK: client→web 열림 (~/work/baseline.txt 기록)"

# step2: default-deny — web 파드로의 모든 ingress 차단
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
sleep 2
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web >/dev/null 2>&1 \
  && echo "예상과 다름: 아직 열려 있음" || echo "차단됨: client→web 막힘"

# step3: app=client 출처만 허용
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
sleep 2
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web >/dev/null && echo "복구됨: client→web 다시 열림"
echo "solution applied"
