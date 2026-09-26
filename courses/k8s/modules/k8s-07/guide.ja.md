# ストレージ — PV・PVC・StatefulSet

Pod が消えるとファイルも消えます(一時的)。永続ストレージは **PersistentVolume(PV)** — 実際の保存領域 —
を **PersistentVolumeClaim(PVC)** — 「これだけ必要」という要求 — で求めて手に入れます。
**StorageClass** は PVC が来ると PV を **動的プロビジョニング** します。

この k3s はデフォルトの StorageClass `local-path` を提供しています。このクラスは
`volumeBindingMode: WaitForFirstConsumer` なので、**PVC を使う Pod がスケジュールされたとき** に初めて
PV を作ってバインドします — そのため最初は PVC が `Pending` なのが正常です。

```bash
kubectl get storageclass         # local-path (default)
```

- `storageclass`(省略形 `sc`)— PV を動的に作ってくれるプロビジョナーの設定。名前の横に `(default)` が付いたものが、PVC でクラスを指定しないときに使われる。
- `VOLUMEBINDINGMODE` 列で `WaitForFirstConsumer` を確認できる。

> 参考: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. PVC の作成

100Mi を要求する PVC `data` を作成します。デフォルトの StorageClass が使われます。

PVC の作成:

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

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `accessModes: [ReadWriteOnce]` — 1 つのノードからだけ読み書きでマウント(RWO)。複数ノードで共有するなら `ReadWriteMany`(RWX)。
- `resources.requests.storage: 100Mi` — 要求する容量。`storageClassName` を省略したのでデフォルトのクラスが使われる。

PVC の状態確認:

```bash
kubectl get pvc data       # STATUS は Pending(WaitForFirstConsumer)
```

- `pvc` は `persistentvolumeclaim` の省略形。`STATUS` が `Pending` → `Bound` に変われば PV と結び付いたということで、`VOLUME` 列に結び付いた PV の名前が出る。

まだ Pod がないので `Pending` が正常です。次のステップで Pod がマウントすると `Bound` になります。

## 2. Pod へのマウント・バインド・書き込み

PVC `data` を `/data` にマウントする Pod `writer` を作ります。Pod がスケジュールされると PVC が
`Bound` に変わり、コンテナが `/data/marker.txt` を書き込みます。

PVC をマウントする Pod の作成:

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

- `volumes[].persistentVolumeClaim.claimName: data` — Pod のボリュームを PVC `data` に結び付ける。
- `volumeMounts[].mountPath: /data` — そのボリュームをコンテナ内の `/data` にマウントする。コンテナは起動するとすぐにファイルを 1 つ書く。

Pod が Ready になるまで待つ:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

- `kubectl wait --for=condition=Ready` — Pod が Ready になるまで待つ。ボリュームのプロビジョニング時間があるので余裕をもって `--timeout=90s`。

PVC のバインド確認:

```bash
kubectl get pvc data                       # 今度は Bound
```

書き込まれたファイルを読む:

```bash
kubectl exec writer -- cat /data/marker.txt
```

- `kubectl exec <Pod> -- <コマンド>` — コンテナ内でコマンドを実行する。PVC 上に書かれたファイルを読んでみる。

PVC が `Bound` になり `/data/marker.txt` を読めれば成功です。Pod を削除して作り直しても(同じ PVC を
マウント)ファイルが残っていることを確かめてみましょう — それが永続性です。

## 3. StatefulSet と volumeClaimTemplates

**StatefulSet** は Pod ごとに安定した名前(web-0、web-1…)と **専用の PVC** を与えます。
`volumeClaimTemplates` に書くと Pod ごとに PVC が自動作成されます(命名規則: `<テンプレート>-<Pod>`、
ここでは `www-web-0`)。

StatefulSet の作成:

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

- `kind: StatefulSet` — Pod 名が `web-0`、`web-1` … のように連番で固定され、順番に作成・削除される。
- `serviceName: web-h` — Pod ごとの DNS(`web-0.web-h`)を提供する Headless Service の名前。
- `volumeClaimTemplates` — Pod ごとに PVC を 1 つずつ作る型。Pod を消しても PVC は残り、同じ Pod に再び付く。

ロールアウト完了を待つ:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

- `kubectl rollout status statefulset/web` — Deployment と同じく StatefulSet のロールアウト完了も待てる。
- `--timeout=120s` — PV のプロビジョニングやイメージの pull まで考えた待ち時間。

自動作成された PVC の確認:

```bash
kubectl get pvc                 # www-web-0 が Bound
```

- 引数なしの `kubectl get pvc` — ネームスペースのすべての PVC。テンプレートから自動作成された `www-web-0` が見える。

Pod `web-0` が Ready で、自動作成された PVC `www-web-0` が `Bound` なら成功です。

> 参考: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
