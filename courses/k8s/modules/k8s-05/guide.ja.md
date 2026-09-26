# リソース要求・制限と QoS

コンテナに **requests**(スケジューラーが確保する最小量)と **limits**(超えると CPU は
スロットリング、メモリは OOM Kill される上限)を設定します。その組み合わせで Pod は 3 つの
**QoS クラス** のいずれかになり、ノードが逼迫したときの **退避(eviction)順序** が決まります:
`BestEffort` → `Burstable` → `Guaranteed` の順に先に追い出されます。

> 参考: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. Guaranteed QoS の Pod

すべてのコンテナに **cpu・memory の requests と limits を同じ値で** 設定すると `Guaranteed` になります。
最も保護されるクラスです。

Pod の作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `resources.requests` — スケジューラーがノード上に確保する最小量、`limits` — 超えられない上限。
- `cpu: "250m"` — ミリコア単位(1000m = CPU 1 個)、`memory: "64Mi"` — 2 進単位のメビバイト。
- requests と limits を同じにすると `Guaranteed` になる。

QoS クラスの確認:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — Pod の status に記録された QoS クラス(`Guaranteed`/`Burstable`/`BestEffort`)だけを取り出す。

## 2. Burstable QoS の Pod

requests はあるが limits の方が大きい、または一部しかない場合は `Burstable` です。普段は requests 分を
使い、余裕があれば limits まで跳ね上がる(burst)ことができます。

Pod の作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF
```

- limits(500m/128Mi)が requests(100m/32Mi)より大きい → 普段は少なく確保し、ノードに余裕があるときだけ limits まで使う(`Burstable`)。

QoS クラスの確認:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — Pod の status に記録された QoS クラス(`Guaranteed`/`Burstable`/`BestEffort`)だけを取り出す。

> requests・limits をまったく設定しないと `BestEffort` になります — 確認: `kubectl run be --image=nginx:1.26`
> の後に `kubectl get pod be -o jsonpath='{.status.qosClass}'`。

## 3. LimitRange のデフォルト値

**LimitRange** はネームスペースにデフォルトの requests/limits を定め、開発者が書き忘れても Pod が
リソース上限を持つようにします。デフォルト値が注入されるには **必ず Pod より先に** 作る必要があります。

LimitRange の作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # limits のデフォルト
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # requests のデフォルト
EOF
```

- `kind: LimitRange` — このネームスペースで作られるコンテナに適用されるリソースのルール。
- `default` — limits を書かなかったコンテナに入れる limits のデフォルト値、`defaultRequest` — requests のデフォルト値。
- デフォルト値は Pod の **作成時** に注入されるので、既存の Pod にはさかのぼって適用されない。

limits を明示しない Pod を作成 — LimitRange がデフォルト値を入れてくれます:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <名前> --image=<イメージ>` — Deployment なしで Pod を 1 つ直接作る。ここではあえて resources を空にしている。

注入された resources の確認:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — 1 つ目のコンテナの resources ブロック全体を JSON で見る。自分で書いていない値が LimitRange によって入っている。

Pod `defaulted` の `resources.limits.memory` が `128Mi` になっていれば成功です。

> 参考: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
