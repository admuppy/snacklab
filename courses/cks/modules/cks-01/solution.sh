#!/bin/bash
# cks-01 reference solution — passes all 16 tasks. Used for E2E regression.
# (Never exposed to learners; the portal does not serve solution.sh.)
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/answers

# ── Q1 NetworkPolicy ───────────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend, namespace: prod }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - { protocol: TCP, port: 80 }
YAML

# ── Q2 TLS secret + Ingress ────────────────────────────────
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /tmp/web.key -out /tmp/web.crt -subj "/CN=web.snacklab.local" 2>/dev/null
kubectl create secret tls web-cert -n prod \
  --cert=/tmp/web.crt --key=/tmp/web.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-tls, namespace: prod }
spec:
  tls:
    - hosts: ["web.snacklab.local"]
      secretName: web-cert
  rules:
    - host: web.snacklab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: web-svc, port: { number: 80 } }
YAML

# ── Q3 binary verification ─────────────────────────────────
(cd ~/work/binaries && sha512sum -c checksums.txt 2>/dev/null || true) \
  | awk -F: '/FAILED/{print $1}' > ~/answers/q3.txt

# ── Q4 RBAC least privilege ────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ci-role, namespace: apps }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update"]
YAML
kubectl delete rolebinding ci-bot-rb -n apps --ignore-not-found
kubectl create rolebinding ci-bot-rb -n apps \
  --role=ci-role --serviceaccount=apps:ci-bot

# ── Q5 SA token automount off ──────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata: { name: web-sa, namespace: apps }
automountServiceAccountToken: false
YAML
kubectl patch deploy web -n apps -p '{"spec":{"template":{"spec":{"serviceAccountName":"web-sa"}}}}'

# ── Q6 dangerous CRB ───────────────────────────────────────
echo debug-admin-binding > ~/answers/q6.txt
kubectl delete clusterrolebinding debug-admin-binding --ignore-not-found

# ── Q7 seccomp RuntimeDefault ──────────────────────────────
kubectl patch deploy runner -n sys-hard -p \
  '{"spec":{"template":{"spec":{"securityContext":{"seccompProfile":{"type":"RuntimeDefault"}}}}}}'

# ── Q8 remove host access ──────────────────────────────────
kubectl apply -f - <<'YAML'
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
      containers:
        - name: tool
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q9 hardened deployment ─────────────────────────────────
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: apps
spec:
  replicas: 1
  selector: { matchLabels: { app: secure-app } }
  template:
    metadata:
      labels: { app: secure-app }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q10 PSA restricted ─────────────────────────────────────
kubectl label ns restricted-ns pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl apply -f - <<'YAML'
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
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: legacy
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
          resources: { requests: { cpu: 10m, memory: 16Mi } }
YAML

# ── Q11 secrets ────────────────────────────────────────────
kubectl get secret db-creds -n apps -o jsonpath='{.data.password}' | base64 -d > ~/answers/q11.txt
kubectl create secret generic api-token -n apps --from-literal=token=cks-2026 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: secret-user
  namespace: apps
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      volumeMounts:
        - { name: creds, mountPath: /etc/creds, readOnly: true }
      resources: { requests: { cpu: 10m, memory: 16Mi } }
  volumes:
    - name: creds
      secret: { secretName: db-creds }
YAML

# ── Q12 Dockerfile fixes ───────────────────────────────────
cat > ~/work/audit/Dockerfile <<'DOCKER'
FROM nginx:1.26
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
USER nginx
CMD ["nginx", "-g", "daemon off;"]
DOCKER

# ── Q13 vulnerable-image triage ────────────────────────────
printf 'frontend-app\nreport-app\n' > ~/answers/q13.txt
kubectl scale deploy frontend-app report-app -n supply --replicas=0

# ── Q14 digest pinning ─────────────────────────────────────
for i in $(seq 1 30); do
  digest=$(kubectl get pod -n supply -l app=pinned \
    -o jsonpath='{.items[0].status.containerStatuses[0].imageID}' 2>/dev/null | sed 's/.*@/@/')
  [ -n "$digest" ] && break
  sleep 2
done
kubectl set image deploy/pinned -n supply web="nginx${digest}"

# ── Q15 audit logging ──────────────────────────────────────
sudo mkdir -p /var/lib/rancher/k3s/server/logs
sudo tee /var/lib/rancher/k3s/server/audit-policy.yaml >/dev/null <<'YAML'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: None
YAML
sudo tee /etc/rancher/k3s/config.yaml >/dev/null <<'YAML'
kube-apiserver-arg:
  - audit-policy-file=/var/lib/rancher/k3s/server/audit-policy.yaml
  - audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
  - audit-log-maxage=7
  - audit-log-maxbackup=2
YAML
sudo systemctl restart k3s
for i in $(seq 1 60); do
  kubectl get nodes >/dev/null 2>&1 && break
  sleep 2
done

# ── Q16 runtime forensics ──────────────────────────────────
echo logshipper > ~/answers/q16.txt
kubectl scale deploy logshipper -n runtime --replicas=0

# ── wait for every rollout so checks see the final state ───
kubectl rollout status deploy/web        -n apps          --timeout=180s
kubectl rollout status deploy/secure-app -n apps          --timeout=180s
kubectl rollout status deploy/runner     -n sys-hard      --timeout=180s
kubectl rollout status deploy/node-tool  -n sys-hard      --timeout=180s
kubectl rollout status deploy/legacy     -n restricted-ns --timeout=180s
kubectl rollout status deploy/pinned     -n supply        --timeout=180s
kubectl wait --for=condition=Ready pod/secret-user -n apps --timeout=180s

echo "SOLUTION DONE"
