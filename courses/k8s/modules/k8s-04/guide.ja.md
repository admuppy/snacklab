# プローブと自己修復

kubelet は 3 種類のプローブでコンテナの状態を監視します。**livenessProbe** が失敗すると
コンテナを **再起動**(自己修復)し、**readinessProbe** が失敗すると Pod を Service の
エンドポイントから **一時的に外して** トラフィックを送らなくします。(startupProbe は起動の遅いアプリの保護用。)

このラボのコンテナは起動時に `/tmp/healthy` を作り、**30 秒後に削除します。** 両方のプローブが
そのファイルを確認するので、30 秒後に liveness が失敗して自動再起動が起こる様子を観察します。

> 参考: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. livenessProbe の定義

下の Deployment `web` を適用します。`livenessProbe` は `cat /tmp/healthy` を 5 秒ごとに実行し、
1 回失敗するとコンテナを再起動します。

Deployment の適用:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `livenessProbe.exec.command` — コンテナ内でこのコマンドを実行し、終了コード 0 なら正常とみなす(`httpGet`、`tcpSocket` 方式もある)。
- `initialDelaySeconds` — 最初の検査までの待ち時間、`periodSeconds` — 検査間隔、`failureThreshold: 1` — 1 回の失敗ですぐ再起動。
- `args` のシェルスクリプトが 30 秒後に `/tmp/healthy` を消して、わざと障害を起こす。

Pod の確認:

```bash
kubectl get pod -l app=web
```

- `READY` は readiness の結果、`RESTARTS` は liveness の失敗による再起動回数を示す。

## 2. readinessProbe の定義

上のマニフェストには `readinessProbe` も含まれています。Pod の準備ができると `READY 1/1` になります。

Pod の状態確認:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — Pod IP、ノード、readiness gate などの追加列も表示する。

readiness プローブ設定の確認:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — ラベルで選んだ Pod の詳細情報(プローブ設定を含む)を表示する。
- `grep -A3 -i readiness` — 大文字小文字を無視して(`-i`)`readiness` の行とその後 3 行を見る。

readiness プローブが通っている間 Pod は Ready で、失敗すると(ファイルが消えたあと)一時的に
`READY 0/1` に落ち、再起動後にまた Ready に戻ります。

## 3. 障害を起こす → 自動再起動

ファイルが消える 30 秒後から liveness が失敗し始めます。Pod を見ていると `RESTARTS` が増えていきます。

Pod の観察:

```bash
kubectl get pod -l app=web -w        # RESTARTS が 0 → 1 に(Ctrl+C で終了)
```

- `-w`(`--watch`)— 1 回表示して終わるのではなく、変化があるたびに新しい行を表示する。`Ctrl+C` で抜ける。

プローブのイベント確認:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` は基本正規表現の OR。プローブ失敗(`Liveness`)、コンテナ停止(`Killing`)、再起動(`Started`)のイベントをまとめて見る。

`RESTARTS` が 1 以上になれば自己修復が動いたということです。すぐに起こしたいなら
`kubectl exec deploy/web -- rm -f /tmp/healthy` でファイルを消しても構いません。

> 参考: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
