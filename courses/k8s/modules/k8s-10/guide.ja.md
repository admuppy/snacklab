# 総合 — 壊れたデプロイを復旧する

EC アプリ 2 つ(`shop`、`cart`)がデプロイされましたが、**何も起動していません。** 3 か所に種類の異なる
障害が仕込まれています。この総合演習は新しい概念を学ぶものではなく、これまでに身につけた診断ツール
—`kubectl get`、`describe`、`logs`、`get events`— で **自分で原因を見つけて直す** 訓練です。

まず全体を見渡しましょう:

全リソースを見渡す:

```bash
kubectl get deploy,pods,svc
```

- カンマ区切りで複数のリソース種類を一度に参照する。Deployment の `READY`、Pod の `STATUS`、Service 一覧を合わせて見て、おかしなところを探す。

最近のイベントの確認:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — ネームスペースで起きたイベント(スケジュール、イメージの pull、失敗など)。
- `--sort-by=.lastTimestamp` — 最後に発生した時刻順に並べ、`| tail -20` — 最新の 20 行だけ。

> 参考: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. イメージ pull 失敗の修理

`shop` の Pod が `ImagePullBackOff`/`ErrImagePull` になっています。原因を確認します。

shop Pod の状態確認:

```bash
kubectl get pods -l app=shop
```

- `STATUS` 列の `ImagePullBackOff`/`ErrImagePull` — ノードがイメージを取得できず、再試行の間隔を延ばしながら待っているという意味。

イベントで原因を確認:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # "not found" のタグが見える
```

- `describe` の一番下の `Events` が失敗原因を最も直接的に教えてくれる。`grep -A5 -i events` でその部分だけを見る。

現在のイメージタグの確認:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — Deployment が Pod を作るときに使うイメージ名:タグ。

存在しないイメージタグが問題です。有効なタグに直します:

イメージタグの変更:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — コンテナ名 `web` のイメージを差し替える。テンプレートが変わるので新しい Pod がロールアウトされる。

ロールアウト完了を待つ:

```bash
kubectl rollout status deploy/shop
```

- 新しい Pod がすべて Ready になるまで待つ。終わらなければ `Ctrl+C` してもう一度 `describe` で原因を見る。

`shop` が 2/2 Ready になれば ① 解決です。

## 2. Service セレクターの修理

Pod は起動しましたが、Service `shop` がトラフィックを送れません。エンドポイントが空かどうかを見ます。

エンドポイントの確認:

```bash
kubectl get endpoints shop            # <none> — どの Pod も付いていない
```

- `ENDPOINTS` が `<none>` なら、Service のセレクターに合う Ready な Pod が 1 つもないという意味。

Service セレクターの確認:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX(タイプミス)
```

- `{.spec.selector}` — Service が Pod を選ぶラベル条件を JSON で見る。

実際の Pod ラベルの確認:

```bash
kubectl get pods -l app=shop --show-labels                  # 実際のラベルは app=shop
```

- `--show-labels` — 各 Pod に付いたラベル全体を `LABELS` 列で表示する。セレクターと 1 文字ずつ比べてみよう。

Service のセレクターが Pod のラベルと合っていません。セレクターを直します:

セレクターの修正:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — リソースの一部のフィールドだけをその場で直す。
- `--type=merge` — `-p` で渡した JSON を既存のオブジェクトにマージする(JSON merge patch)。
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — 変えたい部分だけを書いたパッチ。シェルに解釈されないようシングルクォートで囲む。

エンドポイントの再確認:

```bash
kubectl get endpoints shop            # 今度は Pod の IP が入る
```

エンドポイントが埋まれば ② 解決です。

## 3. 欠けている ConfigMap の修理

`cart` の Pod は `CreateContainerConfigError` で止まっています。理由を見ます。

cart Pod の状態確認:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — イメージは取得できたが、コンテナの設定(参照する ConfigMap/Secret など)を作れない状態。

イベントで原因を確認:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- Events でどのオブジェクトがないのか(`configmap "cart-config" not found`)、名前まで確認できる。

参照している envFrom の確認:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — コンテナが環境変数としてまるごと取り込む ConfigMap/Secret の参照一覧。

存在しない ConfigMap `cart-config` を参照しています。作ってあげれば kubelet が Pod を正常に起動します:

ConfigMap の作成:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- `--from-literal=キー=値` を 2 回指定してキー 2 つの ConfigMap を作る。作成されると kubelet が再試行の中でコンテナを起動する。

ロールアウト完了を待つ:

```bash
kubectl rollout status deploy/cart
```

`cart` が 1/1 Ready になれば ③ 解決 — 3 つの障害をすべて復旧しました。

```bash
kubectl get deploy,svc,endpoints      # 最終確認
```

- 3 つの障害がすべて解消したかを、Deployment の READY、Service、エンドポイントで一度に確認する。
