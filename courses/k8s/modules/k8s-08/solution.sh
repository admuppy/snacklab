#!/bin/bash
# k8s-08 모범답안 — 멱등
set -e
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# step1: ServiceAccount
kubectl create serviceaccount deployer -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# step2: Role(pods 읽기) + RoleBinding(→ deployer)
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: pod-reader, namespace: default }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: read-pods, namespace: default }
subjects:
  - kind: ServiceAccount
    name: deployer
    namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# step3: 검증
SA=system:serviceaccount:default:deployer
echo "list pods : $(kubectl auth can-i list pods --as=$SA -n default)"     # yes
echo "delete pods: $(kubectl auth can-i delete pods --as=$SA -n default)"  # no
echo "solution applied"
