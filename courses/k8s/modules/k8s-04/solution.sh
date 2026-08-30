#!/bin/bash
# k8s-04 모범답안 — 멱등. liveness/readiness exec 프로브 + 자동 재시작 유발
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 컨테이너는 /tmp/healthy 를 만든 뒤 30초 후 삭제 → liveness 실패 → 재시작(자가치유).
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: default
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF

# 재시작이 관측될 때까지 대기(모범답안 확인용)
# NOTE: right after apply the pod may not exist yet — a bare $(kubectl ... jsonpath
# '{.items[0]…}') errors on the empty list and, under set -e, kills the script.
# Guard every probe in the loop so only the final observation matters.
for i in $(seq 1 20); do
  pod=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  rc=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)
  [ "${rc:-0}" -ge 1 ] 2>/dev/null && break
  sleep 5
done
kubectl get pod -l app=web
echo "solution applied (restartCount=${rc:-0})"
