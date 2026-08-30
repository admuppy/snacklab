#!/bin/bash
# k8s-07 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: PVC (기본 StorageClass local-path)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: default }
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 100Mi } }
EOF

# step2: PVC 를 마운트해 바인딩 유발 + 파일 기록
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: writer, namespace: default }
spec:
  containers:
    - name: app
      image: busybox:1.36
      args: ["/bin/sh","-c","echo 'persisted by writer' > /data/marker.txt; sleep 3600"]
      volumeMounts:
        - { name: vol, mountPath: /data }
  volumes:
    - name: vol
      persistentVolumeClaim: { claimName: data }
EOF
kubectl wait --for=condition=Ready pod/writer --timeout=90s
kubectl exec writer -- cat /data/marker.txt

# step3: StatefulSet + volumeClaimTemplates (파드마다 PVC 자동 생성: www-web-0)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web, namespace: default }
spec:
  serviceName: web-h
  replicas: 1
  selector: { matchLabels: { app: sts-web } }
  template:
    metadata: { labels: { app: sts-web } }
    spec:
      containers:
        - name: app
          image: nginx:1.26
          volumeMounts:
            - { name: www, mountPath: /usr/share/nginx/html }
  volumeClaimTemplates:
    - metadata: { name: www }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 100Mi } }
EOF
kubectl rollout status statefulset/web --timeout=120s
kubectl get pvc
echo "solution applied"
