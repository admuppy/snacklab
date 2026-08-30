#!/bin/bash
# ckad-01 model answers — the reference solution that scores 100/100.
# Used by the E2E regression run; never served to learners.
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/answers

# ── Q1 sidecar ─────────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: dev
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"]
      volumeMounts:
        - { name: logs, mountPath: /var/log/app }
      resources: { requests: { cpu: 10m, memory: 16Mi } }
    - name: streamer
      image: busybox:1.36
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts:
        - { name: logs, mountPath: /var/log/app }
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q2 Job + CronJob ───────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
  namespace: batch
spec:
  completions: 3
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pi
          image: busybox:1.36
          command: ["sh", "-c", "echo 3.14159"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup
  namespace: batch
spec:
  schedule: "0 3 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: cleanup
              image: busybox:1.36
              command: ["sh", "-c", "echo cleaned"]
              resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q3 init container ──────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: web-init
  namespace: dev
spec:
  volumes:
    - name: web
      emptyDir: {}
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo ready-to-serve > /work/index.html"]
      volumeMounts:
        - { name: web, mountPath: /work }
  containers:
    - name: web
      image: nginx:1.26
      volumeMounts:
        - { name: web, mountPath: /usr/share/nginx/html }
      resources: { requests: { cpu: 15m, memory: 24Mi } }
YAML

# ── Q4 rolling update ──────────────────────────────────────
kubectl patch deploy api -n prod --type merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image deploy/api -n prod api=nginx:1.26

# ── Q5 canary ──────────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-canary
  namespace: prod
spec:
  replicas: 1
  selector: { matchLabels: { app: shop, track: canary } }
  template:
    metadata:
      labels: { app: shop, track: canary }
    spec:
      containers:
        - name: shop
          image: nginx:1.26
          ports: [{ containerPort: 80 }]
          resources: { requests: { cpu: 15m, memory: 24Mi } }
YAML
kubectl scale deploy shop -n prod --replicas=3

# ── Q6 kustomize overlay ───────────────────────────────────
mkdir -p ~/work/kustomize/overlays/prod
cat > ~/work/kustomize/overlays/prod/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
  - ../../base
replicas:
  - name: hello-web
    count: 2
images:
  - name: nginx
    newTag: "1.26"
YAML
kubectl apply -k ~/work/kustomize/overlays/prod

# ── Q7 probes ──────────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: probe-pod
  namespace: dev
spec:
  containers:
    - name: web
      image: nginx:1.26
      ports: [{ containerPort: 80 }]
      readinessProbe:
        httpGet: { path: /, port: 80 }
        initialDelaySeconds: 3
        periodSeconds: 5
      livenessProbe:
        httpGet: { path: /, port: 80 }
        periodSeconds: 10
      resources: { requests: { cpu: 15m, memory: 24Mi } }
YAML

# ── Q8 CrashLoopBackOff ────────────────────────────────────
# a single grab can race the restart cycle and miss the error line — retry
for i in $(seq 1 10); do
  kubectl logs deploy/orders -n broken > ~/answers/q8.txt 2>&1 || true
  grep -Eq "not found|start-order-daemon" ~/answers/q8.txt && break
  sleep 3
done
kubectl patch deploy orders -n broken --type json -p \
  '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","while true; do date; sleep 5; done"]}]'

# ── Q9 removed API versions ────────────────────────────────
sed -i -e 's|^apiVersion: apps/v1beta1$|apiVersion: apps/v1|' \
       -e 's|^apiVersion: batch/v1beta1$|apiVersion: batch/v1|' ~/work/legacy/stack.yaml
kubectl apply -f ~/work/legacy/stack.yaml

# ── Q10 ConfigMap + Secret ─────────────────────────────────
kubectl create configmap app-config -n dev \
  --from-literal=mode=production --from-literal=timeout=30 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic db-cred -n dev \
  --from-literal=user=admin --from-literal=pass=S3cret1 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  namespace: dev
spec:
  volumes:
    - name: creds
      secret: { secretName: db-cred }
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef: { name: app-config, key: mode }
      volumeMounts:
        - { name: creds, mountPath: /etc/creds, readOnly: true }
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q11 SecurityContext ────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: dev
spec:
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
  volumes:
    - name: tmp
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      volumeMounts:
        - { name: tmp, mountPath: /tmp }
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q12 ServiceAccount ─────────────────────────────────────
kubectl create serviceaccount app-sa -n dev --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: sa-pod
  namespace: dev
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q13 requests/limits under quota ────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: batch
spec:
  replicas: 2
  selector: { matchLabels: { app: worker } }
  template:
    metadata:
      labels: { app: worker }
    spec:
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits: { cpu: 200m, memory: 128Mi }
YAML

# ── Q14 services ───────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: prod
spec:
  type: ClusterIP
  selector: { app: frontend }
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-np
  namespace: prod
spec:
  type: NodePort
  selector: { app: frontend }
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
YAML

# ── Q15 Ingress ────────────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ing
  namespace: prod
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: frontend-svc, port: { number: 80 } }
          - path: /shop
            pathType: Prefix
            backend:
              service: { name: shop-svc, port: { number: 80 } }
YAML

# ── Q16 NetworkPolicy ──────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cache-guard
  namespace: dev
spec:
  podSelector:
    matchLabels: { app: cache }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: client }
      ports:
        - protocol: TCP
          port: 80
YAML

# ── convergence: wait for everything the checks look at ────
kubectl rollout status deploy/api -n prod --timeout=180s
kubectl rollout status deploy/shop -n prod --timeout=120s
kubectl rollout status deploy/shop-canary -n prod --timeout=120s
kubectl rollout status deploy/hello-web -n prod --timeout=120s
kubectl rollout status deploy/orders -n broken --timeout=120s
kubectl rollout status deploy/report-api -n batch --timeout=120s
kubectl rollout status deploy/worker -n batch --timeout=120s
kubectl wait --for=condition=complete job/pi -n batch --timeout=120s
for p in logger web-init probe-pod webapp secure-app sa-pod; do
  kubectl wait --for=condition=Ready "pod/$p" -n dev --timeout=120s
done
# give the sidecar a moment to emit its first tick lines
sleep 4
echo "PASS"
