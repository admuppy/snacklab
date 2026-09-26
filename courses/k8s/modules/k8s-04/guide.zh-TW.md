# 探測器與自我修復

kubelet 用三種探針監視容器狀態。**livenessProbe** 失敗時會 **重啟** 容器(自愈);
**readinessProbe** 失敗時會把 Pod **暫時移出** Service 端點,不再向它傳送流量。
(startupProbe 用於保護啟動較慢的應用。)

本實驗的容器啟動時建立 `/tmp/healthy`,並在 **30 秒後刪除它。** 兩種探針都檢查這個檔案,
因此 30 秒後 liveness 會失敗,你可以觀察到自動重啟。

> 參考: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. 定義 livenessProbe

應用下面的 Deployment `web`。其 `livenessProbe` 每 5 秒執行一次 `cat /tmp/healthy`,
失敗 1 次就重啟容器。

應用 Deployment:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `livenessProbe.exec.command` — 在容器內執行該命令,退出碼為 0 視為健康(也有 `httpGet`、`tcpSocket` 方式)。
- `initialDelaySeconds` — 首次檢查前的等待時間,`periodSeconds` — 檢查間隔,`failureThreshold: 1` — 失敗 1 次即重啟。
- `args` 中的 shell 腳本會在 30 秒後刪除 `/tmp/healthy`,故意製造故障。

檢視 Pod:

```bash
kubectl get pod -l app=web
```

- `READY` 反映 readiness 結果,`RESTARTS` 是因 liveness 失敗而重啟的次數。

## 2. 定義 readinessProbe

上面的清單裡也包含了 `readinessProbe`。Pod 就緒後顯示 `READY 1/1`。

檢視 Pod 狀態:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — 額外顯示 Pod IP、節點、readiness gate 等列。

檢視 readiness 探針配置:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — 輸出按標籤選中的 Pod 的詳細資訊(含探針配置)。
- `grep -A3 -i readiness` — 忽略大小寫(`-i`)匹配 `readiness` 行及其後 3 行。

readiness 探針透過期間 Pod 處於 Ready;失敗後(檔案被刪除之後)會短暫變成 `READY 0/1`,
重啟後又回到 Ready。

## 3. 製造故障 → 自動重啟

檔案在 30 秒後消失,liveness 開始失敗。觀察 Pod,會看到 `RESTARTS` 增加。

觀察 Pod:

```bash
kubectl get pod -l app=web -w        # RESTARTS 從 0 → 1(Ctrl+C 退出)
```

- `-w`(`--watch`)— 不是輸出一次就結束,而是每當有變化就輸出新的一行。按 `Ctrl+C` 退出。

檢視探針事件:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` 是基本正則中的"或"。一次檢視探針失敗(`Liveness`)、容器終止(`Killing`)、重新啟動(`Started`)事件。

`RESTARTS` 達到 1 及以上,說明自愈已經生效。想立即觸發的話,也可以用
`kubectl exec deploy/web -- rm -f /tmp/healthy` 刪掉檔案。

> 參考: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
