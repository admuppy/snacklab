#!/bin/bash
# cka-01 시험 환경 준비 (멱등). 180초 예산 안에 끝나야 하므로 "기다리는" 구간을 최소화한다.
#
#  - 네임스페이스 app-prod / ops / broken
#  - Q2 용 대기(Pending) 상태 CSR  dev-user
#  - Q9 검증용 트래픽 발신 파드 client(role=client) / intruder(라벨 없음)
#  - Q13~Q15 용 고장난 워크로드 3종
#  - 답안 파일 디렉터리 ~/answers
#
# 고장난 워크로드가 Ready 가 되기를 기다리지 않는다(애초에 안 된다). client/intruder 도
# 기다리지 않는다 — 학습자가 Q9 에 도달할 즈음이면 이미 Running 이고, 체크가 상태를 확인한다.
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/answers ~/work

# 1) 클러스터 기동 대기 (최대 150초)
for i in $(seq 1 75); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done

# 2) 네임스페이스
for ns in app-prod ops broken; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

# 3) Q2 — 승인 대기 중인 CSR. 개인키/CSR 은 ~/work 에 남겨 학습자가 참고할 수 있게 한다.
if ! kubectl get csr dev-user >/dev/null 2>&1; then
  openssl genrsa -out ~/work/dev-user.key 2048 2>/dev/null
  openssl req -new -key ~/work/dev-user.key -out ~/work/dev-user.csr \
    -subj "/CN=dev-user/O=developers" 2>/dev/null
  kubectl apply -f - >/dev/null <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: dev-user
spec:
  request: $(base64 -w0 ~/work/dev-user.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
YAML
fi

# 4) Q9 검증용 발신 파드 두 개 (busybox 를 여기서 당겨 두면 이후 문항이 빨라진다)
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: app-prod
  labels: { role: client }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
---
apiVersion: v1
kind: Pod
metadata:
  name: intruder
  namespace: app-prod
  labels: { role: outsider }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# 5) Q13 — 존재하지 않는 이미지 태그로 영원히 기동하지 못하는 Deployment
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: broken
spec:
  replicas: 2
  selector: { matchLabels: { app: api } }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: api
          image: nginx:1.99-does-not-exist
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 20m, memory: 32Mi } }
YAML

# 6) Q14 — 백엔드는 정상인데 Service 의 셀렉터·targetPort 가 둘 다 틀린 경우
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
  namespace: broken
spec:
  replicas: 1
  selector: { matchLabels: { app: cache } }
  template:
    metadata:
      labels: { app: cache }
    spec:
      containers:
        - name: cache
          image: nginx:1.26
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 20m, memory: 32Mi } }
---
apiVersion: v1
kind: Service
metadata:
  name: cache-svc
  namespace: broken
spec:
  type: ClusterIP
  selector: { app: cach }
  ports:
    - port: 80
      targetPort: 8080
YAML

# 7) Q15 — ConfigMap 의 키 이름이 컨테이너가 읽는 경로와 어긋나 CrashLoopBackOff
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: worker-config
  namespace: broken
data:
  application.conf: |
    mode=batch
    interval=30
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: broken
spec:
  replicas: 1
  selector: { matchLabels: { app: worker } }
  template:
    metadata:
      labels: { app: worker }
    spec:
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "cat /config/app.conf && sleep 86400"]
          volumeMounts:
            - { name: cfg, mountPath: /config }
          resources: { requests: { cpu: 10m, memory: 16Mi } }
      volumes:
        - name: cfg
          configMap: { name: worker-config }
YAML

# 8) Q16/Q17 — exam infra (2026-08-06). The datastore is already embedded etcd
#    (course.json clusterInit → K3S_CLUSTER_INIT). Here: the backup dir, two KWOK fake
#    workers, and the workload the learner will drain. Fake nodes carry the
#    kwok.x-k8s.io/node taint so nothing from other questions can land on them —
#    only the payments deployment tolerates it.
mkdir -p ~/backup
if [ -x /usr/local/bin/kwok ]; then
  sudo systemctl enable --now kwok >/dev/null 2>&1 || true
  for n in worker-1 worker-2; do
    kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Node
metadata:
  name: $n
  annotations:
    kwok.x-k8s.io/node: fake
  labels:
    kubernetes.io/hostname: $n
    kubernetes.io/os: linux
    kubernetes.io/arch: amd64
    node-role.kubernetes.io/worker: "true"
    type: kwok
spec:
  taints:
    - { key: kwok.x-k8s.io/node, value: fake, effect: NoSchedule }
YAML
  done
  # Cosmetic realism: kwok stamps kubeletVersion "kwok-vX" — overwrite via the status
  # subresource so `kubectl get nodes` shows a k3s version. kwok's stage templates use
  # `or .status.nodeInfo.*` fallbacks, so patched values survive heartbeats.
  ver=$(kubectl get node -l node-role.kubernetes.io/control-plane \
        -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null)
  for n in worker-1 worker-2; do
    kubectl patch node "$n" --subresource=status --type=merge -p "{\"status\":{
      \"nodeInfo\":{\"kubeletVersion\":\"${ver:-v1.36.2+k3s1}\",
                    \"containerRuntimeVersion\":\"containerd://2.0.5-k3s1\",
                    \"osImage\":\"Ubuntu 24.04 LTS\",
                    \"kernelVersion\":\"$(uname -r)\"},
      \"capacity\":{\"cpu\":\"2\",\"memory\":\"4Gi\",\"pods\":\"110\"},
      \"allocatable\":{\"cpu\":\"2\",\"memory\":\"4Gi\",\"pods\":\"110\"}}}" >/dev/null 2>&1 || true
  done

  kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: maint
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments
  namespace: maint
spec:
  replicas: 4
  selector: { matchLabels: { app: payments } }
  template:
    metadata:
      labels: { app: payments }
    spec:
      nodeSelector: { type: kwok }
      tolerations:
        - { key: kwok.x-k8s.io/node, operator: Equal, value: fake, effect: NoSchedule }
      containers:
        - name: payments
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML
fi

echo "PASS"
