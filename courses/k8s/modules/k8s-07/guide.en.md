# Storage — PV, PVC, StatefulSet

When a Pod dies its files go with it. For durable storage you request a
**PersistentVolume (PV)** — the real backing storage — via a **PersistentVolumeClaim (PVC)** — a
request for "this much". A **StorageClass** **dynamically provisions** a PV when a PVC appears.

This k3s ships a default StorageClass `local-path`. It uses
`volumeBindingMode: WaitForFirstConsumer`, so a PV is created and bound only **when a Pod that
consumes the PVC is scheduled** — the PVC is `Pending` at first, which is expected.

```bash
kubectl get storageclass         # local-path (default)
```

> Reference: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. Create a PVC

Create a PVC `data` requesting 100Mi. It uses the default StorageClass.

Create the PVC:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 100Mi } }
EOF
```

Check PVC status:

```bash
kubectl get pvc data       # STATUS is Pending (WaitForFirstConsumer)
```

`Pending` is correct with no consuming Pod yet. It binds once a Pod mounts it in the next step.

## 2. Mount, bind, and write

Create Pod `writer` that mounts PVC `data` at `/data`. Once the Pod is scheduled the PVC turns
`Bound` and the container writes `/data/marker.txt`.

Create the Pod mounting the PVC:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox:1.36
      args: ["/bin/sh","-c","echo 'persisted by writer' > /data/marker.txt; sleep 3600"]
      volumeMounts: [{ name: vol, mountPath: /data }]
  volumes:
    - name: vol
      persistentVolumeClaim: { claimName: data }
EOF
```

Wait for the Pod to be Ready:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

Check the PVC is bound:

```bash
kubectl get pvc data                       # now Bound
```

Read the written file:

```bash
kubectl exec writer -- cat /data/marker.txt
```

Success when the PVC is `Bound` and `/data/marker.txt` is readable. Delete and recreate the Pod
(mounting the same PVC) and confirm the file survives — that is persistence.

## 3. StatefulSet with volumeClaimTemplates

A **StatefulSet** gives each Pod a stable name (web-0, web-1…) and its own **dedicated PVC**.
Declared in `volumeClaimTemplates`, a PVC is auto-created per Pod (naming: `<template>-<pod>`,
here `www-web-0`).

Create the StatefulSet:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
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
          volumeMounts: [{ name: www, mountPath: /usr/share/nginx/html }]
  volumeClaimTemplates:
    - metadata: { name: www }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 100Mi } }
EOF
```

Wait for the rollout:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

Check the auto-created PVC:

```bash
kubectl get pvc                 # www-web-0 is Bound
```

Success when Pod `web-0` is Ready and the auto-created PVC `www-web-0` is `Bound`.

> Reference: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
