# Service とクラスターネットワーキング

Pod はいつでも落ち、新しい IP で立ち上がり直します。**Service** はラベルで Pod 群を選び、
安定した仮想 IP・DNS 名・負荷分散を提供します。このラボでは、すでに動いている Deployment `web`
(ラベル `app=web`、2 レプリカ)を 3 種類の Service タイプで公開します。

Deployment の確認:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — これから公開する Deployment が存在し、Pod がすべて `READY` かを確認する。

バックエンド Pod の確認:

```bash
kubectl get pods -l app=web -o wide     # バックエンド Pod の IP を確認
```

- `-l app=web` — Service のセレクターが選ぶのと同じラベルで Pod を参照する。
- `-o wide` — Pod IP 列が表示される。あとで Service のエンドポイントと見比べよう。

> 参考: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. ClusterIP で公開

デフォルトのタイプ **ClusterIP** は、クラスター内部からのみアクセスできる仮想 IP を作ります。
Service 名は `web`、ポートは 80 です。

Service の作成:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — Deployment の Pod セレクター(`app=web`)をそのまま使って Service を作る。
- `--name=web` — 作成する Service の名前。この名前がそのまま DNS 名になる。
- `--port=80` — Service が受けるポート、`--target-port=80` — トラフィックを転送するコンテナのポート。
- `--type` を省略するとデフォルトの `ClusterIP` になる。

Service の確認:

```bash
kubectl get svc web
```

- `svc` は `service` の省略形。`CLUSTER-IP` 列がクラスター内部だけで使われる仮想 IP。

エンドポイントの確認:

```bash
kubectl get endpoints web           # セレクターが選んだ Pod の IP:ポート一覧
```

- `endpoints` — Service が実際にトラフィックを送るバックエンド(Pod IP:ポート)の一覧。セレクターに一致する **Ready** な Pod だけが入る。

クラスター内部からアクセステスト:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — テスト用の使い捨て Pod `t` を起動する。
- `--restart=Never --rm -it` — 再起動なしで 1 回だけ実行し、ターミナルをつないで(`-it`)結果を見たあと、終了したら Pod を削除する(`--rm`)。
- `--` の後ろはコンテナ内で実行するコマンド。行末の `\` は次の行に続く 1 つのコマンドという意味。
- `wget -qO- <URL>` — 静かに(`-q`)取得し、ファイルではなく標準出力(`-O-`)に表示する。
- `web.default.svc.cluster.local` — `<サービス>.<ネームスペース>.svc.cluster.local` 形式の Service DNS 名。

`kubectl get endpoints web` に Pod の IP が入っていればルーティングが成立しています。エンドポイントが
空なら、セレクター(`app=web`)が Pod のラベルと合っていません。

## 2. NodePort で外部公開

**NodePort** はすべてのノードの固定ポート(デフォルト 30000–32767)を開き、クラスターの外からも
アクセスできるようにします。Service `web-np` を作成します。

NodePort Service の作成:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — ClusterIP に加えて **すべてのノードの同じポート**(30000–32767 から自動割り当て)を開き、クラスター外からアクセスできるようにする。
- `--name=web-np` — 先の `web` Service と重ならないよう別の名前を付ける。

割り当てられたポートの確認:

```bash
kubectl get svc web-np                          # PORT(S) 列の 80:3xxxx/TCP
```

- `PORT(S)` の `80:3xxxx/TCP` — 前が Service のポート、後ろがノードに開いた nodePort。

nodePort の値を変数に保存:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — コマンド置換。括弧内のコマンドの出力をシェル変数 `np` に入れる。
- `{.spec.ports[0].nodePort}` — 1 つ目のポート項目の nodePort 値だけを取り出す JSONPath。

ノードから直接アクセス:

```bash
curl -s http://127.0.0.1:$np | head -1          # ノード(=この Pod)から直接アクセス
```

- `curl -s` — 進捗表示なしで(silent)HTTP リクエストを送る。`$np` には先ほど保存した nodePort が入る。
- `127.0.0.1` — このラボではターミナル自体がノードなので、ノード自身のアドレスでアクセスする。
- `| head -1` — レスポンスの 1 行目だけを見る。

`80:3xxxx/TCP` のように nodePort が割り当てられ、curl が nginx の応答を返せば成功です。

## 3. Headless Service と DNS

`clusterIP: None` の **Headless Service** は仮想 IP もプロキシも持たず、DNS 問い合わせに
**各 Pod の IP** をそのまま A レコードとして返します。StatefulSet の Pod ごとのアクセスなどに使われます。

Headless Service の作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: web-h, namespace: default }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `clusterIP: None` — 仮想 IP を作らない Headless Service の宣言。`selector` で選んだ Pod の IP がそのまま DNS に載る。

CLUSTER-IP の確認:

```bash
kubectl get svc web-h                 # CLUSTER-IP が None
```

- `CLUSTER-IP` が `None` なら Headless。kube-proxy の負荷分散の対象ではない。

DNS 問い合わせテスト:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # Pod の数だけ A レコード
```

- `kubectl run t --image=busybox:1.36` — テスト用の使い捨て Pod `t` を起動する。
- `--restart=Never --rm -it` — 再起動なしで 1 回だけ実行し、ターミナルをつないで(`-it`)結果を見たあと、終了したら Pod を削除する(`--rm`)。
- `--` の後ろはコンテナ内で実行するコマンド。行末の `\` は次の行に続く 1 つのコマンドという意味。
- `nslookup <名前>` — DNS に名前を問い合わせ、A レコード(IP)を表示する。Headless なら Pod の数だけ IP が返る。

`CLUSTER-IP` が `None` で、nslookup が Pod の数だけ IP を返せば成功です。

> 参考: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
