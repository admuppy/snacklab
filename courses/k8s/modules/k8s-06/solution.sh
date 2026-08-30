#!/bin/bash
# k8s-06 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# step1: 노드 레이블 + nodeAffinity 파드
kubectl label node "$node" disktype=ssd --overwrite
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: affine, namespace: default }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disktype, operator: In, values: ["ssd"] }
  containers:
    - name: app
      image: nginx:1.26
EOF

# step2: 노드 테인트 + 톨러레이션 파드
kubectl taint nodes "$node" lab=demo:NoSchedule --overwrite
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: tolerant, namespace: default }
spec:
  tolerations:
    - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
  containers:
    - name: app
      image: nginx:1.26
EOF

# step3: DaemonSet (커스텀 테인트를 톨러레이트해야 노드에 착지)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: default }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
        - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
      containers:
        - name: agent
          image: busybox:1.36
          args: ["/bin/sh","-c","sleep 3600"]
          resources: { requests: { cpu: "10m", memory: "16Mi" } }
EOF

kubectl wait --for=condition=Ready pod/affine pod/tolerant --timeout=60s
kubectl rollout status ds/node-agent --timeout=60s
echo "solution applied"
