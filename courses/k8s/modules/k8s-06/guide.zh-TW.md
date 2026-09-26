# 排程 —— 親和性、汙點與 DaemonSet

排程器決定 Pod 放到哪個節點上。**nodeAffinity/nodeSelector** 讓 Pod *希望* 去某些節點,
**taint/toleration** 讓節點 *排斥* 某些 Pod — 二者方向相反。**DaemonSet** 會在每個(符合條件的)
節點上各放一個 Pod。

本叢集只有 1 個節點。用下面的命令獲取節點名:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — 命令替換。用 `{.items[0].metadata.name}` 取出第一個節點名,存入 shell 變數 `node`。
- `; echo "$node"` — 輸出變數的值以便確認。之後的命令都用 `"$node"` 引用這個名稱。

> 參考: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. 節點標籤與 nodeAffinity

給節點加上 `disktype=ssd` 標籤,再建立 Pod `affine`,透過 `requiredDuringScheduling`
nodeAffinity 讓它只落在帶該標籤的節點上。

給節點加標籤:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <資源> <名稱> 鍵=值` — 新增標籤。要修改已有的鍵用 `--overwrite`,要刪除用 `鍵-` 的形式。

建立帶 nodeAffinity 的 Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: affine }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disktype, operator: In, values: ["ssd"] }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `requiredDuringSchedulingIgnoredDuringExecution` — 排程時 **必須** 滿足;已在執行的 Pod 即使之後標籤改變也不會被趕走。
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — 只有 `disktype` 標籤值為 `ssd` 的節點才是候選(還有 `NotIn`、`Exists` 等運算子)。

檢視 Pod 的排程位置:

```bash
kubectl get pod affine -o wide      # NODE 列顯示我們的節點
```

- 透過 `-o wide` 的 `NODE` 列確認 Pod 被排程到了哪個節點。

刪除標籤後(`kubectl label node "$node" disktype-`),新建的此類 Pod 會處於 `Pending` — 可以親自
試一試。

## 2. 汙點與容忍

給節點加上 `lab=demo:NoSchedule` **汙點(taint)** 後,不 **容忍(tolerate)** 該汙點的 Pod
將無法被排程。只有帶容忍的 `tolerant` 能落地。

給節點設定汙點:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <節點> 鍵=值:效果` — 給節點加汙點。效果有 `NoSchedule`(拒絕新 Pod)、`PreferNoSchedule`(儘量避免)、`NoExecute`(連已執行的 Pod 也驅逐)。
- 解除時在末尾加 `-`:`kubectl taint nodes "$node" lab=demo:NoSchedule-`

沒有容忍的 Pod 會 Pending(演示用):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — 前一條命令結束後接著執行後一條。建立 Pod 後立即檢視其狀態。
- 因為沒有容忍,`STATUS` 一直停在 `Pending`。`kubectl describe pod notol` 的 Events 裡可以看到 `untolerated taint`。

刪除演示用 Pod:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <名稱>` — 刪除 Pod。演示用 Pod 留著會干擾後續檢查。

建立帶容忍的 Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: tolerant }
spec:
  tolerations:
    - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `tolerations` — 此 Pod 能容忍的汙點列表。`key`、`value`、`effect` 必須與節點的汙點一致。
- `operator: Equal` 會連值一起比較,`Exists` 只要鍵存在就容忍。

檢視 Pod 狀態:

```bash
kubectl get pod tolerant -o wide     # Running
```

- 因為有容忍,它也能被排程到帶汙點的節點上,變為 `Running`。

> `NoSchedule` 只阻止新 Pod,已有 Pod 保持不變;而 `NoExecute` 還會驅逐不容忍該汙點的已有 Pod。

## 3. DaemonSet

**DaemonSet** 在每個節點上保持一個 Pod(日誌採集器、節點代理等)。由於我們給節點加了 `lab` 汙點,
DaemonSet 的 Pod 也 **必須帶有容忍** 才能落到節點上。

建立 DaemonSet:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent }
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
```

- `kind: DaemonSet` — 沒有 `replicas`;在每個符合條件的節點上恰好保持一個 Pod。
- `selector.matchLabels` 必須與 `template.metadata.labels` 一致。
- 由於節點上有 `lab` 汙點,這裡也需要同樣的 `tolerations`。

檢視 DaemonSet 狀態:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` 是 `daemonset` 的縮寫。`DESIRED` — 應執行 Pod 的節點數,`CURRENT` — 已建立數,`READY` — 就緒數。

`DESIRED`、`READY` 等於節點數(1)即為成功。

> 參考: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
