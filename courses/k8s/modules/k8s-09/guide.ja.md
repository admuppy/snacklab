# NetworkPolicy — マイクロセグメンテーション

デフォルトでは、クラスター内のすべての Pod は互いに通信できます。**NetworkPolicy** は Pod 単位の
ファイアウォールで、ラベルで選んだ Pod に対して **どの送信元(from)/宛先(to)** のトラフィックを許可するかを
決めます。ルールは **許可(allow)リスト** です — ポリシーがある Pod を「選択」した瞬間から、その Pod は
明示的に許可されたトラフィックしか受け付けません(それ以外は拒否)。

このラボにはサーバー `web`(+Service `web`)とクライアント Pod `client`(ラベル `app=client`)が
すでに動いています。k3s は NetworkPolicy を実際に強制します。

web Pod の確認:

```bash
kubectl get pod -l app=web -o wide
```

- `-l app=web` でサーバー Pod を、`-o wide` でその IP を見る。NetworkPolicy もこのラベルで Pod を選ぶ。

client Pod の確認:

```bash
kubectl get pod client -o wide
```

- クライアント Pod。`kubectl get pod client --show-labels` で `app=client` ラベルを確認しておこう — ステップ 3 の許可ルールの基準になる。

> 参考: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. 基本の接続確認

ポリシーがない状態で client から web に接続できることを確認し、その結果をベースラインとして
`~/work/baseline.txt` に残します(ステップ 2・3 の遮断・許可と比べる根拠)。

client → web の接続確認:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx の応答
```

- `kubectl exec client -- …` — client Pod の **中から** リクエストを送る(送信元が client になるように)。
- `wget -q -T 3 -O- http://web` — 3 秒のタイムアウト(`-T 3`)で `web` Service にリクエストし、応答を標準出力(`-O-`)に出す。
- `| head -1` — 応答の 1 行目だけを見る。

記録用ディレクトリの作成:

```bash
mkdir -p ~/work
```

- `mkdir -p` — 途中のディレクトリまで作り、すでにあってもエラーにしない。

ベースラインの応答を保存:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> ファイル` — コマンドの標準出力をファイルに保存(上書き)する。`kubectl exec` の出力は自分のターミナル側に来るので、ファイルもローカルにできる。

保存内容の確認:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <ファイル>` — ファイルの 1 行目だけを表示する。

nginx の HTML の 1 行目(`<!DOCTYPE html>`)が出れば開いている状態です。

## 2. デフォルト拒否(default-deny)

`web` Pod を選択しつつ **ingress ルールを 1 つも持たない** ポリシーを作ります。選択された Pod への
インバウンドはすべて遮断されます。

default-deny ポリシーの作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `podSelector` — ポリシーを適用する対象 Pod(`app=web`)。空のセレクター `{}` ならネームスペースのすべての Pod。
- `policyTypes: [Ingress]` なのに `ingress:` ルールがない → 選択された Pod に入るトラフィックをすべて拒否。

遮断の確認(タイムアウトを想定):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # タイムアウト(遮断)
```

- `-t 1` — 試行は 1 回だけ。遮断されていると 3 秒後に `timed out` で終わる(拒否パケットなしで黙って捨てられる)。

`wget` がタイムアウトで失敗すれば、ポリシーがトラフィックを止めたということです。

## 3. 送信元に基づく許可

次に、`app=client` ラベルを持つ Pod からの 80 番ポートだけを許可するポリシーを追加します。ポリシーは
累積するので、default-deny の上にこの許可が重なり、client だけが通れます。

許可ポリシーの作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
```

- `ingress[].from[].podSelector` — 同じネームスペースで `app=client` ラベルを持つ Pod だけを送信元として許可する。
- `ports` — 許可するポート/プロトコル(TCP 80)。`from` と `ports` が 1 つの項目内にあれば両方を満たす必要がある。
- ポリシーは OR で合算されるので、default-deny があってもこの許可が追加で適用される。

client → web の再確認:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # 再び成功
```

client → web が再び開けば成功です。`app=client` ラベルのない別の Pod から試すと依然として遮断されます —
それがマイクロセグメンテーションです。

> 参考: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
