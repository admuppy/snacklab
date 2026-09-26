# 存储 —— PV、PVC 与 StatefulSet

Pod 一旦消失,里面的文件也随之消失(临时的)。持久存储要通过 **PersistentVolumeClaim(PVC)** —
"我需要这么多"的请求 — 来申请 **PersistentVolume(PV)** — 实际的存储空间。
**StorageClass** 会在 PVC 出现时 **动态供应** PV。

这个 k3s 自带默认的 StorageClass `local-path`。该类使用
`volumeBindingMode: WaitForFirstConsumer`,**直到使用该 PVC 的 Pod 被调度时** 才创建并绑定
PV — 所以一开始 PVC 处于 `Pending` 是正常的。

```bash
kubectl get storageclass         # local-path (default)
```

- `storageclass`(缩写 `sc`)— 按需创建 PV 的供应器配置。名称旁标有 `(default)` 的,会在 PVC 未指定类时使用。
- 可以在 `VOLUMEBINDINGMODE` 列看到 `WaitForFirstConsumer`。

> 参考: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. 创建 PVC

创建请求 100Mi 的 PVC `data`,使用默认的 StorageClass。

创建 PVC:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `accessModes: [ReadWriteOnce]` — 只能被单个节点以读写方式挂载(RWO);多节点共享用 `ReadWriteMany`(RWX)。
- `resources.requests.storage: 100Mi` — 请求的容量。省略了 `storageClassName`,因此使用默认类。

查看 PVC 状态:

```bash
kubectl get pvc data       # STATUS 为 Pending(WaitForFirstConsumer)
```

- `pvc` 是 `persistentvolumeclaim` 的缩写。`STATUS` 从 `Pending` 变为 `Bound` 即表示已与 PV 绑定,`VOLUME` 列显示绑定的 PV 名称。

还没有 Pod,所以 `Pending` 是正常的。下一步 Pod 挂载后就会变成 `Bound`。

## 2. 挂载到 Pod、绑定并写入

创建把 PVC `data` 挂载到 `/data` 的 Pod `writer`。Pod 被调度后 PVC 变为 `Bound`,
容器会写入 `/data/marker.txt`。

创建挂载 PVC 的 Pod:

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

- `volumes[].persistentVolumeClaim.claimName: data` — 把 Pod 的卷关联到 PVC `data`。
- `volumeMounts[].mountPath: /data` — 把该卷挂载到容器内的 `/data`。容器一启动就写入一个文件。

等待 Pod Ready:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

- `kubectl wait --for=condition=Ready` — 等待 Pod 变为 Ready。考虑到卷的供应时间,留足 `--timeout=90s`。

查看 PVC 绑定情况:

```bash
kubectl get pvc data                       # 现在是 Bound
```

读取写入的文件:

```bash
kubectl exec writer -- cat /data/marker.txt
```

- `kubectl exec <Pod> -- <命令>` — 在容器中执行命令,这里读取写在 PVC 上的文件。

PVC 变为 `Bound` 且能读取 `/data/marker.txt` 即为成功。删除并重建 Pod(挂载同一个 PVC)后,
确认文件依然存在 — 这就是持久性。

## 3. StatefulSet 与 volumeClaimTemplates

**StatefulSet** 为每个 Pod 提供稳定的名称(web-0、web-1…)和 **专属的 PVC**。
写在 `volumeClaimTemplates` 中,就会为每个 Pod 自动创建 PVC(命名规则:`<模板>-<Pod>`,
这里是 `www-web-0`)。

创建 StatefulSet:

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

- `kind: StatefulSet` — Pod 名称按序号固定为 `web-0`、`web-1` …,并按顺序创建、删除。
- `serviceName: web-h` — 提供按 Pod 的 DNS(`web-0.web-h`)的 Headless Service 名称。
- `volumeClaimTemplates` — 为每个 Pod 生成一个 PVC 的模板。删除 Pod 后 PVC 仍保留,并重新挂到同一个 Pod。

等待发布完成:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

- `kubectl rollout status statefulset/web` — 与 Deployment 一样,也可以等待 StatefulSet 发布完成。
- `--timeout=120s` — 把 PV 供应和镜像拉取时间都考虑进去的等待时间。

查看自动创建的 PVC:

```bash
kubectl get pvc                 # www-web-0 为 Bound
```

- 不带名称的 `kubectl get pvc` — 命名空间中的所有 PVC,包括由模板自动创建的 `www-web-0`。

Pod `web-0` 为 Ready,且自动创建的 PVC `www-web-0` 为 `Bound`,即为成功。

> 参考: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
