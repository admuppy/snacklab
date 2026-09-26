# 儲存 —— PV、PVC 與 StatefulSet

Pod 一旦消失,裡面的檔案也隨之消失(臨時的)。持久儲存要透過 **PersistentVolumeClaim(PVC)** —
"我需要這麼多"的請求 — 來申請 **PersistentVolume(PV)** — 實際的儲存空間。
**StorageClass** 會在 PVC 出現時 **動態供應** PV。

這個 k3s 自帶預設的 StorageClass `local-path`。該類使用
`volumeBindingMode: WaitForFirstConsumer`,**直到使用該 PVC 的 Pod 被排程時** 才建立並繫結
PV — 所以一開始 PVC 處於 `Pending` 是正常的。

```bash
kubectl get storageclass         # local-path (default)
```

- `storageclass`(縮寫 `sc`)— 按需建立 PV 的供應器配置。名稱旁標有 `(default)` 的,會在 PVC 未指定類時使用。
- 可以在 `VOLUMEBINDINGMODE` 列看到 `WaitForFirstConsumer`。

> 參考: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. 建立 PVC

建立請求 100Mi 的 PVC `data`,使用預設的 StorageClass。

建立 PVC:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `accessModes: [ReadWriteOnce]` — 只能被單個節點以讀寫方式掛載(RWO);多節點共享用 `ReadWriteMany`(RWX)。
- `resources.requests.storage: 100Mi` — 請求的容量。省略了 `storageClassName`,因此使用預設類。

檢視 PVC 狀態:

```bash
kubectl get pvc data       # STATUS 為 Pending(WaitForFirstConsumer)
```

- `pvc` 是 `persistentvolumeclaim` 的縮寫。`STATUS` 從 `Pending` 變為 `Bound` 即表示已與 PV 繫結,`VOLUME` 列顯示繫結的 PV 名稱。

還沒有 Pod,所以 `Pending` 是正常的。下一步 Pod 掛載後就會變成 `Bound`。

## 2. 掛載到 Pod、繫結並寫入

建立把 PVC `data` 掛載到 `/data` 的 Pod `writer`。Pod 被排程後 PVC 變為 `Bound`,
容器會寫入 `/data/marker.txt`。

建立掛載 PVC 的 Pod:

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

- `volumes[].persistentVolumeClaim.claimName: data` — 把 Pod 的卷關聯到 PVC `data`。
- `volumeMounts[].mountPath: /data` — 把該卷掛載到容器內的 `/data`。容器一啟動就寫入一個檔案。

等待 Pod Ready:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

- `kubectl wait --for=condition=Ready` — 等待 Pod 變為 Ready。考慮到卷的供應時間,留足 `--timeout=90s`。

檢視 PVC 繫結情況:

```bash
kubectl get pvc data                       # 現在是 Bound
```

讀取寫入的檔案:

```bash
kubectl exec writer -- cat /data/marker.txt
```

- `kubectl exec <Pod> -- <命令>` — 在容器中執行命令,這裡讀取寫在 PVC 上的檔案。

PVC 變為 `Bound` 且能讀取 `/data/marker.txt` 即為成功。刪除並重建 Pod(掛載同一個 PVC)後,
確認檔案依然存在 — 這就是永續性。

## 3. StatefulSet 與 volumeClaimTemplates

**StatefulSet** 為每個 Pod 提供穩定的名稱(web-0、web-1…)和 **專屬的 PVC**。
寫在 `volumeClaimTemplates` 中,就會為每個 Pod 自動建立 PVC(命名規則:`<模板>-<Pod>`,
這裡是 `www-web-0`)。

建立 StatefulSet:

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

- `kind: StatefulSet` — Pod 名稱按序號固定為 `web-0`、`web-1` …,並按順序建立、刪除。
- `serviceName: web-h` — 提供按 Pod 的 DNS(`web-0.web-h`)的 Headless Service 名稱。
- `volumeClaimTemplates` — 為每個 Pod 生成一個 PVC 的模板。刪除 Pod 後 PVC 仍保留,並重新掛到同一個 Pod。

等待發布完成:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

- `kubectl rollout status statefulset/web` — 與 Deployment 一樣,也可以等待 StatefulSet 發布完成。
- `--timeout=120s` — 把 PV 供應和映像拉取時間都考慮進去的等待時間。

檢視自動建立的 PVC:

```bash
kubectl get pvc                 # www-web-0 為 Bound
```

- 不帶名稱的 `kubectl get pvc` — 名稱空間中的所有 PVC,包括由模板自動建立的 `www-web-0`。

Pod `web-0` 為 Ready,且自動建立的 PVC `www-web-0` 為 `Bound`,即為成功。

> 參考: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
