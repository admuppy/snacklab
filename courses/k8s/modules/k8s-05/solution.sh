#!/bin/bash
# k8s-05 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: Guaranteed — cpu·memory 의 requests 와 limits 가 동일
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF

# step2: Burstable — requests < limits
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF

# step3: LimitRange 를 '먼저' 만들고, limits 없는 파드를 생성 → 기본값 주입
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults, namespace: default }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }
      defaultRequest: { memory: "64Mi",  cpu: "100m" }
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: defaulted, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
EOF

kubectl get pod guaranteed burstable defaulted -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
echo "solution applied"
