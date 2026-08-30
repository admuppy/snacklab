#!/bin/bash
# ckad-01 exam environment setup (idempotent). Must finish well within the 180s
# budget, so we avoid waiting on anything that is not strictly required.
#
#  - namespaces dev / prod / batch / broken
#  - prod: deployments api (Q4 rolling update), shop + shop-svc (Q5 canary),
#          frontend (Q14 services)
#  - dev:  pod cache (Q16 target) + traffic probes client(role=client) / intruder
#  - batch: ResourceQuota batch-quota (Q13)
#  - broken: deployment orders crash-looping on a missing command (Q8)
#  - ~/work/kustomize/base   — kustomize base the learner overlays (Q6)
#  - ~/work/legacy/stack.yaml — manifests with removed apiVersions (Q9)
#  - ~/answers directory for written answers
#
# We do NOT wait for the broken workload (it never becomes Ready) nor for the
# probe pods — by the time the learner reaches those tasks they are Running.
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/answers ~/work

# 1) wait for the cluster (up to 150s)
for i in $(seq 1 75); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready' && kubectl get sa default -n default >/dev/null 2>&1 && break
  sleep 2
done

# 2) namespaces
for ns in dev prod batch broken; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

# 3) Q4 — deployment the learner rolls to a new image with surge control
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: prod
spec:
  replicas: 2
  selector: { matchLabels: { app: api } }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: api
          image: nginx:1.25
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 20m, memory: 32Mi } }
YAML

# 4) Q5 — stable release behind a service; the learner adds a canary track
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: prod
spec:
  replicas: 4
  selector: { matchLabels: { app: shop, track: stable } }
  template:
    metadata:
      labels: { app: shop, track: stable }
    spec:
      containers:
        - name: shop
          image: nginx:1.25
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 15m, memory: 24Mi } }
---
apiVersion: v1
kind: Service
metadata:
  name: shop-svc
  namespace: prod
spec:
  type: ClusterIP
  selector: { app: shop }
  ports:
    - port: 80
      targetPort: 80
YAML

# 5) Q14 — backend for the service task
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: prod
spec:
  replicas: 1
  selector: { matchLabels: { app: frontend } }
  template:
    metadata:
      labels: { app: frontend }
    spec:
      containers:
        - name: frontend
          image: nginx:1.26
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 20m, memory: 32Mi } }
YAML

# 6) Q16 — NetworkPolicy target and traffic probes (pulls busybox early too)
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: cache
  namespace: dev
  labels: { app: cache }
spec:
  containers:
    - name: cache
      image: nginx:1.26
      ports: [{ containerPort: 80 }]
      resources: { requests: { cpu: 15m, memory: 24Mi } }
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: dev
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
  namespace: dev
  labels: { role: outsider }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# 7) Q13 — quota the learner's deployment must fit into
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: batch-quota
  namespace: batch
spec:
  hard:
    pods: "10"
    requests.cpu: "1"
    requests.memory: 1Gi
YAML

# 8) Q8 — container command does not exist -> CrashLoopBackOff
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  namespace: broken
spec:
  replicas: 1
  selector: { matchLabels: { app: orders } }
  template:
    metadata:
      labels: { app: orders }
    spec:
      containers:
        - name: orders
          image: busybox:1.36
          command: ["sh", "-c", "start-order-daemon --queue main"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# 9) Q6 — kustomize base (the learner writes overlays/prod on top of it)
mkdir -p ~/work/kustomize/base
cat > ~/work/kustomize/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-web
  template:
    metadata:
      labels:
        app: hello-web
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports:
            - containerPort: 80
          resources:
            requests: { cpu: 15m, memory: 24Mi }
YAML
cat > ~/work/kustomize/base/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
YAML

# 10) Q9 — manifests written against long-removed API versions
mkdir -p ~/work/legacy
cat > ~/work/legacy/stack.yaml <<'YAML'
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: report-api
  namespace: batch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: report-api
  template:
    metadata:
      labels:
        app: report-api
    spec:
      containers:
        - name: report-api
          image: nginx:1.26
          resources:
            requests: { cpu: 15m, memory: 24Mi }
---
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: report-gen
  namespace: batch
spec:
  schedule: "30 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: gen
              image: busybox:1.36
              command: ["sh", "-c", "echo report generated"]
              resources:
                requests: { cpu: 10m, memory: 16Mi }
YAML

echo "PASS"
