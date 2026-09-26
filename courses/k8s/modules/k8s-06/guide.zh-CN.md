# 调度 —— 亲和性、污点与 DaemonSet

调度器决定 Pod 放到哪个节点上。**nodeAffinity/nodeSelector** 让 Pod *希望* 去某些节点,
**taint/toleration** 让节点 *排斥* 某些 Pod — 二者方向相反。**DaemonSet** 会在每个(符合条件的)
节点上各放一个 Pod。

本集群只有 1 个节点。用下面的命令获取节点名:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — 命令替换。用 `{.items[0].metadata.name}` 取出第一个节点名,存入 shell 变量 `node`。
- `; echo "$node"` — 输出变量的值以便确认。之后的命令都用 `"$node"` 引用这个名称。

> 参考: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. 节点标签与 nodeAffinity

给节点加上 `disktype=ssd` 标签,再创建 Pod `affine`,通过 `requiredDuringScheduling`
nodeAffinity 让它只落在带该标签的节点上。

给节点加标签:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <资源> <名称> 键=值` — 添加标签。要修改已有的键用 `--overwrite`,要删除用 `键-` 的形式。

创建带 nodeAffinity 的 Pod:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `requiredDuringSchedulingIgnoredDuringExecution` — 调度时 **必须** 满足;已在运行的 Pod 即使之后标签改变也不会被赶走。
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — 只有 `disktype` 标签值为 `ssd` 的节点才是候选(还有 `NotIn`、`Exists` 等运算符)。

查看 Pod 的调度位置:

```bash
kubectl get pod affine -o wide      # NODE 列显示我们的节点
```

- 通过 `-o wide` 的 `NODE` 列确认 Pod 被调度到了哪个节点。

删除标签后(`kubectl label node "$node" disktype-`),新建的此类 Pod 会处于 `Pending` — 可以亲自
试一试。

## 2. 污点与容忍

给节点加上 `lab=demo:NoSchedule` **污点(taint)** 后,不 **容忍(tolerate)** 该污点的 Pod
将无法被调度。只有带容忍的 `tolerant` 能落地。

给节点设置污点:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <节点> 键=值:效果` — 给节点加污点。效果有 `NoSchedule`(拒绝新 Pod)、`PreferNoSchedule`(尽量避免)、`NoExecute`(连已运行的 Pod 也驱逐)。
- 解除时在末尾加 `-`:`kubectl taint nodes "$node" lab=demo:NoSchedule-`

没有容忍的 Pod 会 Pending(演示用):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — 前一条命令结束后接着执行后一条。创建 Pod 后立即查看其状态。
- 因为没有容忍,`STATUS` 一直停在 `Pending`。`kubectl describe pod notol` 的 Events 里可以看到 `untolerated taint`。

删除演示用 Pod:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <名称>` — 删除 Pod。演示用 Pod 留着会干扰后续检查。

创建带容忍的 Pod:

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

- `tolerations` — 此 Pod 能容忍的污点列表。`key`、`value`、`effect` 必须与节点的污点一致。
- `operator: Equal` 会连值一起比较,`Exists` 只要键存在就容忍。

查看 Pod 状态:

```bash
kubectl get pod tolerant -o wide     # Running
```

- 因为有容忍,它也能被调度到带污点的节点上,变为 `Running`。

> `NoSchedule` 只阻止新 Pod,已有 Pod 保持不变;而 `NoExecute` 还会驱逐不容忍该污点的已有 Pod。

## 3. DaemonSet

**DaemonSet** 在每个节点上保持一个 Pod(日志采集器、节点代理等)。由于我们给节点加了 `lab` 污点,
DaemonSet 的 Pod 也 **必须带有容忍** 才能落到节点上。

创建 DaemonSet:

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

- `kind: DaemonSet` — 没有 `replicas`;在每个符合条件的节点上恰好保持一个 Pod。
- `selector.matchLabels` 必须与 `template.metadata.labels` 一致。
- 由于节点上有 `lab` 污点,这里也需要同样的 `tolerations`。

查看 DaemonSet 状态:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` 是 `daemonset` 的缩写。`DESIRED` — 应运行 Pod 的节点数,`CURRENT` — 已创建数,`READY` — 就绪数。

`DESIRED`、`READY` 等于节点数(1)即为成功。

> 参考: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
