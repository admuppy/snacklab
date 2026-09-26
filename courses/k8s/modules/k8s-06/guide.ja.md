# スケジューリング — アフィニティ・テイント・DaemonSet

スケジューラーは Pod をどのノードに置くかを決めます。**nodeAffinity/nodeSelector** は Pod が特定の
ノードを *望む* ようにし、**taint/toleration** はノードが特定の Pod を *はじく* ようにします。両者は
逆方向の道具です。**DaemonSet** は(条件に合う)すべてのノードに Pod を 1 つずつ配置します。

このクラスターのノードは 1 台です。ノード名は次で確認します:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — コマンド置換。`{.items[0].metadata.name}` で最初のノード名を取り出し、シェル変数 `node` に入れる。
- `; echo "$node"` — 入った値を表示して確認する。以降のコマンドは `"$node"` でこの名前を使う。

> 参考: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. ノードラベルと nodeAffinity

ノードに `disktype=ssd` ラベルを付け、`requiredDuringScheduling` の nodeAffinity でそのラベルが
あるノードにだけ乗る Pod `affine` を作ります。

ノードにラベルを付与:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <リソース> <名前> キー=値` — ラベルを付ける。既存のキーを変えるには `--overwrite`、消すには `キー-` の形を使う。

nodeAffinity 付き Pod の作成:

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

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `requiredDuringSchedulingIgnoredDuringExecution` — スケジュール時には **必ず** 満たす必要があり、すでに実行中の Pod は後でラベルが変わっても追い出さない。
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — `disktype` ラベルの値が `ssd` のノードだけが候補になる(`NotIn`、`Exists` などの演算子もある)。

Pod の配置確認:

```bash
kubectl get pod affine -o wide      # NODE 列に私たちのノード
```

- `-o wide` の `NODE` 列で、Pod がどのノードに配置されたかを確認する。

ラベルを消すと(`kubectl label node "$node" disktype-`)新しい Pod は `Pending` になります — 実際に
確かめてみましょう。

## 2. テイントとトレレーション

ノードに `lab=demo:NoSchedule` の **テイント** を付けると、そのテイントを **許容(toleration)** しない
Pod はスケジュールされません。トレレーションを持つ `tolerant` だけが乗れます。

ノードにテイントを設定:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <ノード> キー=値:効果` — ノードにテイントを付ける。効果は `NoSchedule`(新しい Pod を拒否)、`PreferNoSchedule`(できるだけ避ける)、`NoExecute`(既存の Pod も退避)。
- 解除は末尾に `-` を付ける: `kubectl taint nodes "$node" lab=demo:NoSchedule-`

トレレーションのない Pod は Pending(確認用):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — 前のコマンドが終わると後ろのコマンドを続けて実行する。Pod を作った直後の状態を参照する。
- トレレーションがないので `STATUS` は `Pending` のまま。`kubectl describe pod notol` の Events に `untolerated taint` が見える。

確認用 Pod の削除:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <名前>` — Pod を削除する。確認用 Pod が残っていると後のチェックの邪魔になる。

トレレーションを持つ Pod の作成:

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

- `tolerations` — この Pod が許容できるテイントの一覧。`key`・`value`・`effect` がノードのテイントと一致する必要がある。
- `operator: Equal` は値まで比較し、`Exists` はキーさえあれば許容する。

Pod の状態確認:

```bash
kubectl get pod tolerant -o wide     # Running
```

- トレレーションがあるのでテイントの付いたノードにも配置され、`Running` になる。

> `NoSchedule` は新しい Pod だけを止めて既存の Pod はそのままにしますが、`NoExecute` は許容しない既存の
> Pod まで退避させます。

## 3. DaemonSet

**DaemonSet** はすべてのノードに Pod を 1 つずつ維持します(ログ収集エージェント、ノードエージェントなど)。
ノードに `lab` テイントを付けてあるので、DaemonSet の Pod も **トレレーションがないと** ノードに乗れません。

DaemonSet の作成:

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

- `kind: DaemonSet` — `replicas` がない。条件に合うノードごとに Pod をちょうど 1 つ維持する。
- `selector.matchLabels` は `template.metadata.labels` と同じでなければならない。
- ノードに付いた `lab` テイントのため、ここにも同じ `tolerations` が必要。

DaemonSet の状態確認:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` は `daemonset` の省略形。`DESIRED` — Pod があるべきノード数、`CURRENT` — 作られた数、`READY` — 準備済みの数。

`DESIRED`・`READY` がノード数(1)と同じになれば成功です。

> 参考: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
