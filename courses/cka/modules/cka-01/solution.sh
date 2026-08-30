#!/bin/bash
# cka-01 모범답안 — 17문항을 모두 통과시키는 기준 답. E2E 회귀 검증에 쓰인다.
# (학습자에게 노출되지 않는다. 포털은 solution.sh 를 서빙하지 않는다.)
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/answers

# ── Q1 RBAC ────────────────────────────────────────────────
kubectl create serviceaccount deploy-bot -n app-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create role pod-reader -n app-prod \
  --verb=get,list,watch --resource=pods,deployments.apps \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create rolebinding deploy-bot-rb -n app-prod \
  --role=pod-reader --serviceaccount=app-prod:deploy-bot \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Q2 CSR 승인 + 열람 권한 ────────────────────────────────
kubectl certificate approve dev-user >/dev/null 2>&1 || true
kubectl create rolebinding dev-user-view -n app-prod \
  --clusterrole=view --user=dev-user \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Q3 정적 파드 ───────────────────────────────────────────
sudo tee /var/lib/rancher/k3s/agent/pod-manifests/ops-static.yaml >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: ops-static
  namespace: default
spec:
  containers:
    - name: ops
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
YAML

# ── Q4 ResourceQuota / LimitRange ──────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata: { name: ops-quota, namespace: ops }
spec:
  hard:
    pods: "5"
    requests.cpu: "1"
    requests.memory: 1Gi
---
apiVersion: v1
kind: LimitRange
metadata: { name: ops-limits, namespace: ops }
spec:
  limits:
    - type: Container
      defaultRequest: { cpu: 100m, memory: 128Mi }
      default: { cpu: 200m, memory: 256Mi }
YAML

# ── Q5 Deployment web ──────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: app-prod }
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: web
          image: nginx:1.26
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 50m, memory: 64Mi } }
YAML

# ── Q6 DaemonSet ───────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: ops }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q7 사이드카 ────────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: logger, namespace: app-prod, labels: { app: logger } }
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "tail -f /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q8 Service (ClusterIP + NodePort) ──────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata: { name: web-svc, namespace: app-prod }
spec:
  type: ClusterIP
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Service
metadata: { name: web-np, namespace: app-prod }
spec:
  type: NodePort
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80, nodePort: 30080 }]
YAML

# ── Q9 NetworkPolicy ───────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: app-prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client, namespace: app-prod }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { role: client } }
      ports:
        - protocol: TCP
          port: 80
YAML

# ── Q10 Ingress ────────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: app-prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
YAML

# ── Q11 정적 PV/PVC ────────────────────────────────────────
sudo mkdir -p /mnt/data
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 1Gi }
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  persistentVolumeReclaimPolicy: Retain
  hostPath: { path: /mnt/data, type: DirectoryOrCreate }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-data, namespace: app-prod }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: data-user, namespace: app-prod }
spec:
  volumes:
    - name: d
      persistentVolumeClaim: { claimName: pvc-data }
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      volumeMounts: [{ name: d, mountPath: /data }]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q12 동적 프로비저닝 ────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-dyn, namespace: app-prod }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources: { requests: { storage: 500Mi } }
---
apiVersion: v1
kind: Pod
metadata: { name: writer, namespace: app-prod }
spec:
  volumes:
    - name: d
      persistentVolumeClaim: { claimName: pvc-dyn }
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "echo cka > /data/hello.txt; sleep 86400"]
      volumeMounts: [{ name: d, mountPath: /data }]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q13 이미지 태그 수정 ───────────────────────────────────
kubectl set image deploy/api -n broken api=nginx:1.26 >/dev/null

# ── Q14 Service 셀렉터·targetPort 수정 ─────────────────────
kubectl patch svc cache-svc -n broken --type=merge \
  -p '{"spec":{"selector":{"app":"cache"},"ports":[{"port":80,"targetPort":80}]}}' >/dev/null

# ── Q15 ConfigMap 키 수정 + 원인 보고 ──────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata: { name: worker-config, namespace: broken }
data:
  app.conf: |
    mode=batch
    interval=30
YAML
kubectl rollout restart deploy/worker -n broken >/dev/null
echo "configmap/worker-config" > ~/answers/q15.txt

# ── 수렴 대기 ──────────────────────────────────────────────
kubectl rollout status deploy/web -n app-prod --timeout=180s >/dev/null
kubectl rollout status ds/node-agent -n ops --timeout=120s >/dev/null
kubectl rollout status deploy/api -n broken --timeout=180s >/dev/null
kubectl rollout status deploy/worker -n broken --timeout=180s >/dev/null
kubectl rollout status deploy/cache -n broken --timeout=180s >/dev/null
for p in logger data-user writer client intruder; do
  kubectl wait --for=condition=Ready pod/$p -n app-prod --timeout=120s >/dev/null 2>&1 || true
done
# 정적 파드 미러가 올라오기까지
for i in $(seq 1 40); do
  kubectl get pod -n default 2>/dev/null | grep -q '^ops-static-.* Running' && break
  sleep 3
done
# Q15 체크는 "재시작 루프가 멈췄다"를 컨테이너 가동 시간으로 본다
sleep 25

# ── Q16 etcd backup + offline restore ──────────────────────
# Real-exam flow: etcdctl for the snapshot, etcdutl for the offline restore.
# Certs are root-only, hence sudo (the exam host works the same way).
mkdir -p ~/backup
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  snapshot save /home/learner/backup/etcd-snap.db >/dev/null
sudo rm -rf /home/learner/backup/restored
sudo etcdutl snapshot restore /home/learner/backup/etcd-snap.db \
  --data-dir /home/learner/backup/restored >/dev/null 2>&1

# ── Q17 drain worker-1 ─────────────────────────────────────
# Fake nodes are KWOK-backed: eviction + rescheduling to worker-2 happen for real.
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data >/dev/null 2>&1 || \
  kubectl drain worker-1 --ignore-daemonsets >/dev/null
# payments must come back 4/4 on worker-2
kubectl rollout status deploy/payments -n maint --timeout=120s >/dev/null

echo "PASS"
