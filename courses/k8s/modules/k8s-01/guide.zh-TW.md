# Deployment 與滾動發布

**Deployment** 是一種工作負載:你宣告一組 Pod 的期望狀態(副本數、映像),控制器就會讓叢集收斂到該狀態,
並在映像變更時管理 **零停機滾動更新** 和 **回滾**。

本實驗在 Pod 內執行的 **你專屬的單節點 k3s 叢集** 中進行。終端裡可以直接使用 `kubectl`
(已配置 `k` 別名和自動補全),`KUBECONFIG` 也已設定好。

檢視節點:

```bash
kubectl get nodes          # 1 個 Ready 節點
```

- `kubectl get <資源>` — 以表格形式列出資源,是最基本的查詢命令。
- `nodes` — 加入叢集的機器。`STATUS` 必須是 `Ready`,Pod 才能排程到上面。

檢視當前上下文:

```bash
kubectl config current-context
```

- `kubectl config` — 操作 kubeconfig 檔案(要連線的叢集和使用者資訊)的子命令。
- `current-context` — 輸出 kubectl 當前傳送命令所用的上下文(叢集 + 使用者 + 名稱空間的組合)名稱。

> 參考: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. 建立 Deployment(3 個副本)

用 `nginx:1.25` 映像建立一個 3 副本的 Deployment `web`。

建立 Deployment:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — 不寫 YAML,以命令式方式建立 `web` Deployment。Pod 會自動帶上 `app=web` 標籤。
- `--image=nginx:1.25` — Pod 模板的容器映像(`名稱:標籤`)。
- `--replicas=3` — 始終保持的 Pod 數量(`spec.replicas`)。

等待發布完成:

```bash
kubectl rollout status deploy/web            # 等到全部 Ready
```

- `kubectl rollout status` — 等待發布完成(新 Pod 全部 Ready),並輸出進度。
- `deploy/web` — `<型別>/<名稱>` 形式的資源指定。`deploy` 是 `deployment` 的縮寫。

檢視 Deployment 狀態:

```bash
kubectl get deploy web
```

- `READY` — 就緒/期望的 Pod 數,`UP-TO-DATE` — 用最新模板建立的 Pod 數,`AVAILABLE` — 可對外服務的 Pod 數。

檢視 Pod 列表:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — 標籤選擇器,只選出帶 `app=web` 標籤的 Pod。
- `-o wide` — 額外顯示 Pod IP、所在節點等列。

`kubectl get deploy web` 的 `READY` 列顯示 `3/3` 即為成功。也可以用 `kubectl get rs`
確認 ReplicaSet 是否建立了 3 個 Pod。

## 2. 滾動更新

把映像升級到 `nginx:1.26`。Deployment 會建立新的 ReplicaSet,每次替換幾個 Pod
(預設 `maxUnavailable=25%`、`maxSurge=25%`),在不中斷服務的情況下完成更新。

更換映像:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # 更換所有容器的映像
```

- `kubectl set image deploy/web <容器>=<映像>` — 只修改 Pod 模板中的映像。模板一變就會開始新的發布。
- `'*=nginx:1.26'` — `*` 表示所有容器。用單引號包起來,防止 shell 把 `*` 展開成檔名。

等待發布完成:

```bash
kubectl rollout status deploy/web             # 等待發布完成
```

透過事件檢視替換過程:

```bash
kubectl describe deploy web | grep -A2 Events # 透過事件檢視替換過程
```

- `kubectl describe` — 以便於閱讀的形式輸出資源的詳細資訊和最近事件。
- `| grep -A2 Events` — 只看輸出中的 `Events` 行及其後(After)2 行,可以看到新舊 ReplicaSet 的擴縮記錄。

檢視 ReplicaSet:

```bash
kubectl get rs                                # 新舊 ReplicaSet 並存 → 只有新的是 3 個
```

- `rs` — ReplicaSet 的縮寫。每次映像(模板)變更,Deployment 都會建立新的 ReplicaSet,並把舊的縮到 0,留作回滾之用。

`kubectl rollout status` 輸出 `successfully rolled out` 即完成。

> 參考: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. 回滾

假設剛才的發布有問題,**回退到上一個版本(revision)。** Deployment 儲存著版本歷史,
所以可以立即回滾。

檢視版本列表:

```bash
kubectl rollout history deploy/web           # 版本列表
```

- `kubectl rollout history` — 列出 Deployment 儲存的版本(模板變更歷史)。
- 要檢視某個版本的具體內容,加上 `--revision=<N>`。

回滾到上一個版本:

```bash
kubectl rollout undo deploy/web              # 回滾到上一個版本(nginx:1.25)
```

- `kubectl rollout undo` — 發起一次新的發布,回到上一個版本的 Pod 模板。回滾本身也會被記錄為一個新版本。

等待發布完成:

```bash
kubectl rollout status deploy/web
```

檢視當前映像:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — 用 JSONPath 表示式只取出需要的欄位。`{.spec.template.spec.containers[0].image}` 是第一個容器的映像。
- `; echo` — jsonpath 輸出末尾沒有換行,補一個換行以擴音示符粘在後面。

映像回到 `nginx:1.25`、並且多了一個版本,即為成功。要回滾到指定版本,
使用 `kubectl rollout undo deploy/web --to-revision=<N>`。

> 參考: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
