# Deployment とロールアウト

**Deployment** は Pod 群のあるべき状態(レプリカ数・イメージ)を宣言すると、コントローラーがその状態へ
収束させ、イメージ変更時の **無停止ローリングアップデート** と **ロールバック** を管理してくれるワークロードです。

このラボは Pod の中で動く **あなた専用のシングルノード k3s クラスター** で進めます。ターミナルからすぐに
`kubectl` を使え(`k` エイリアスと補完も設定済み)、`KUBECONFIG` もすでに設定されています。

ノードの確認:

```bash
kubectl get nodes          # Ready のノードが 1 台
```

- `kubectl get <リソース>` — リソースの一覧を表で表示する、最も基本的な参照コマンド。
- `nodes` — クラスターに参加しているマシン。`STATUS` が `Ready` でないと Pod は配置されない。

現在のコンテキストの確認:

```bash
kubectl config current-context
```

- `kubectl config` — kubeconfig ファイル(接続先クラスターとユーザー情報)を扱うサブコマンド。
- `current-context` — kubectl が今コマンドを送っているコンテキスト(クラスター+ユーザー+ネームスペースの組)の名前を表示する。

> 参考: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Deployment の作成(3 レプリカ)

`nginx:1.25` イメージで 3 レプリカの Deployment `web` を作成します。

Deployment の作成:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — YAML なしで命令的に `web` Deployment を作る。Pod には `app=web` ラベルが自動で付く。
- `--image=nginx:1.25` — Pod テンプレートのコンテナイメージ(`名前:タグ`)。
- `--replicas=3` — 常に維持する Pod の数(`spec.replicas`)。

ロールアウト完了を待つ:

```bash
kubectl rollout status deploy/web            # すべて Ready になるまで待つ
```

- `kubectl rollout status` — ロールアウトが終わる(新しい Pod がすべて Ready になる)まで待ち、進行状況を表示する。
- `deploy/web` — `<種類>/<名前>` 形式のリソース指定。`deploy` は `deployment` の省略形。

Deployment の状態確認:

```bash
kubectl get deploy web
```

- `READY` — 準備済み/望ましい Pod 数、`UP-TO-DATE` — 最新テンプレートで作られた Pod 数、`AVAILABLE` — サービス提供可能な Pod 数。

Pod 一覧の確認:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — ラベルセレクター。`app=web` ラベルが付いた Pod だけを選ぶ。
- `-o wide` — Pod IP や配置先ノードなどの追加列も表示する。

`kubectl get deploy web` の `READY` 列が `3/3` なら成功です。ReplicaSet が Pod を 3 つ作ったことを
`kubectl get rs` でも確認してみましょう。

## 2. ローリングアップデート

イメージを `nginx:1.26` に上げます。Deployment は新しい ReplicaSet を作り、Pod を数個ずつ
入れ替えながら(デフォルト `maxUnavailable=25%`, `maxSurge=25%`)サービスを止めずに更新します。

イメージの変更:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # すべてのコンテナのイメージを変更
```

- `kubectl set image deploy/web <コンテナ>=<イメージ>` — Pod テンプレートのイメージだけを変える。テンプレートが変わると新しいロールアウトが始まる。
- `'*=nginx:1.26'` — `*` はすべてのコンテナを意味する。シェルが `*` をファイル名に展開しないようシングルクォートで囲んでいる。

ロールアウト完了を待つ:

```bash
kubectl rollout status deploy/web             # ロールアウト完了まで待つ
```

イベントで入れ替えの過程を確認:

```bash
kubectl describe deploy web | grep -A2 Events # イベントで入れ替え過程を確認
```

- `kubectl describe` — リソースの詳細情報と最近のイベントを人が読みやすい形で表示する。
- `| grep -A2 Events` — 出力のうち `Events` の行とその後(After)2 行だけを見る。新旧 ReplicaSet のスケール調整の記録が見える。

ReplicaSet の確認:

```bash
kubectl get rs                                # 新旧 ReplicaSet が共存 → 新しい方だけ 3
```

- `rs` — ReplicaSet の省略形。Deployment はイメージ(テンプレート)が変わるたびに新しい ReplicaSet を作り、古い ReplicaSet は 0 に縮めてロールバック用に残す。

`kubectl rollout status` が `successfully rolled out` を表示すれば完了です。

> 参考: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. ロールバック

今のリリースに問題があったと仮定して、**直前のリビジョンに戻します。** Deployment はリビジョン
履歴を保持しているので、すぐにロールバックできます。

リビジョン一覧の確認:

```bash
kubectl rollout history deploy/web           # リビジョン一覧
```

- `kubectl rollout history` — Deployment が保持しているリビジョン(テンプレート変更履歴)の一覧を表示する。
- 特定リビジョンの内容は `--revision=<N>` を付けて確認する。

直前のリビジョンへロールバック:

```bash
kubectl rollout undo deploy/web              # 直前のリビジョン(nginx:1.25)へ戻す
```

- `kubectl rollout undo` — 直前のリビジョンの Pod テンプレートへ戻す新しいロールアウトを開始する。ロールバック自体も新しいリビジョンとして記録される。

ロールアウト完了を待つ:

```bash
kubectl rollout status deploy/web
```

現在のイメージの確認:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — 出力のうち必要なフィールドだけを JSONPath 式で取り出す。`{.spec.template.spec.containers[0].image}` は 1 つ目のコンテナのイメージ。
- `; echo` — jsonpath の出力には改行がないので、プロンプトがくっつかないよう改行を足す。

イメージが `nginx:1.25` に戻り、リビジョンがもう 1 つ増えていれば成功です。特定のリビジョンに
戻すには `kubectl rollout undo deploy/web --to-revision=<N>` を使います。

> 参考: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
