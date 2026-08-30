# 解説

提出後、満点を取れなかった問題についてのみ以下の解説が表示されます。
正解は一つではありません — 採点は「結果が仕様どおりか」を見るので、以下は最短の基準解です。

## Q1 サイドカーコンテナ — ログストリーミング

1 つの Pod、2 つのコンテナ、1 つの emptyDir。要点は **両方のコンテナが同じボリュームを
同じパスにマウントする** ことです。

```yaml
apiVersion: v1
kind: Pod
metadata: { name: logger, namespace: dev }
spec:
  volumes: [{ name: logs, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: streamer
      image: busybox:1.36
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

よくある間違い

- サイドカーの volumeMount を忘れると `tail` は空のファイルすら見つけられません — ログの採点項目
  (2 点)を落とします。
- `tail -F`(大文字)はファイルが現れるまで待ちますが、`-f` はファイルがまだ無いと終了し、
  コンテナが CrashLoop に陥ることがあります。
- 採点は `kubectl logs logger -c streamer` に `tick` が実際に流れているかを見ます —
  形だけ正しくてもコマンドが違えばその項目は 0 点です。

## Q2 Job と CronJob

Job は命令型で作り、completions/parallelism は YAML で足すのが最速です。

```bash
kubectl create job pi -n batch --image=busybox:1.36 --dry-run=client -o yaml -- sh -c "echo 3.14159" > job.yaml
# spec: の下に completions: 3 と parallelism: 2 を追記してから
kubectl apply -f job.yaml
kubectl create cronjob cleanup -n batch --image=busybox:1.36 --schedule="0 3 * * *" \
  --dry-run=client -o yaml -- sh -c "echo cleaned" > cj.yaml
# spec: の下に concurrencyPolicy: Forbid と successfulJobsHistoryLimit: 1 を追記してから
kubectl apply -f cj.yaml
```

よくある間違い

- `completions`/`parallelism` は **Job の spec** 直下です。template.spec ではありません。
- CronJob の `concurrencyPolicy` と `successfulJobsHistoryLimit` も **CronJob の spec** レベルです
  (jobTemplate.spec ではありません)。
- `restartPolicy: Never` を省くと Job の作成自体が失敗します(デフォルト値はありません)。

## Q3 init コンテナによるコンテンツ準備

メインコンテナは init コンテナが完了してから起動します。準備したファイルは emptyDir 経由で
引き渡します。

```yaml
spec:
  volumes: [{ name: web, emptyDir: {} }]
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo ready-to-serve > /work/index.html"]
      volumeMounts: [{ name: web, mountPath: /work }]
  containers:
    - name: web
      image: nginx:1.26
      volumeMounts: [{ name: web, mountPath: /usr/share/nginx/html }]
```

よくある間違い

- メイン側のマウントパスが nginx のドキュメントルート(`/usr/share/nginx/html`)でないと
  HTTP の採点項目(2 点)を落とします。
- ボリューム名が違うと、init コンテナが書いたファイルはメインコンテナに届きません。

## Q4 ローリングアップデート — 無停止戦略

戦略が先、イメージが後です。逆の順序だと最初のロールアウトが既定戦略(25%)で走ります。

```bash
kubectl patch deploy api -n prod --type merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image deploy/api -n prod api=nginx:1.26
kubectl rollout status deploy/api -n prod
```

よくある間違い

- `kubectl edit` でも同じです — 採点はフィールドの値だけを読みます。
- `maxUnavailable: 0` と `maxSurge: 0` を同時に設定するとロールアウトが永久にデッドロックします。
- 提出前に `rollout status` で完了を確認してください。さもないと「2 レプリカが新バージョンで
  Ready」の項目(2 点)がまだ満たされていないことがあります。

## Q5 カナリアデプロイ — トラフィックの 25%

サービスのセレクター(`app: shop`)はそのままにします。**同じ app ラベル + 異なる track ラベル**
を持つ 2 つ目の Deployment — それがラベルベースのカナリアのすべてです。

```bash
kubectl create deploy shop-canary -n prod --image=nginx:1.26 --replicas=1 --dry-run=client -o yaml > canary.yaml
# Pod テンプレートのラベルを app: shop, track: canary に直し(selector も合わせる)、apply する
kubectl scale deploy shop -n prod --replicas=3
```

よくある間違い

- `kubectl create deploy` はラベル `app: shop-canary` を生成します — **必ず `app: shop` に
  変更** しないとサービスがカナリアを拾いません(2 点のエンドポイント項目がここに掛かっています)。
- selector とテンプレートのラベルが食い違うと apply 自体が拒否されます。
- stable を 3 に縮小し忘れると 4:1 になります — それは 25% ではありません。

## Q6 Kustomize オーバーレイ

オーバーレイは base を参照する kustomization.yaml 1 枚で完成します。

```yaml
# ~/work/kustomize/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources: [../../base]
replicas: [{ name: hello-web, count: 2 }]
images: [{ name: nginx, newTag: "1.26" }]
```

```bash
kubectl apply -k ~/work/kustomize/overlays/prod
```

よくある間違い

- `resources` の相対パスは **オーバーレイのディレクトリ基準**(`../../base`)です。
- `images.name` は base が使う **イメージ名**(nginx)です。コンテナ名(web)ではありません。
- `newTag` は文字列です — `"1.26"` と引用符で囲むのが安全な習慣です。
- ファイルを書いても `apply -k` を忘れるとクラスタ側の 5 点をすべて失います。

## Q7 プローブ — 自己修復とトラフィックゲーティング

問題の数値をそのまま写します。プローブはコンテナレベルのフィールドです。

```yaml
containers:
  - name: web
    image: nginx:1.26
    readinessProbe:
      httpGet: { path: /, port: 80 }
      initialDelaySeconds: 3
      periodSeconds: 5
    livenessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 10
```

よくある間違い

- readiness と liveness のブロックは似ていて入れ替えやすいですが、別々に採点されます。
- ポートを間違える(たとえば 8080)とスペックの項目に加えて Ready の項目(1 点)も落とします。

## Q8 障害診断 — CrashLoopBackOff

調査(ログの保存)→ 修復(コマンドの差し替え)の順です。

```bash
kubectl logs deploy/orders -n broken > ~/answers/q8.txt 2>&1   # "not found" を捕捉
kubectl patch deploy orders -n broken --type json -p \
  '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","while true; do date; sleep 5; done"]}]'
```

よくある間違い

- CrashLoop 中の Pod のログは `--previous` なしでも直前の実行の出力を表示します。空なら
  `kubectl logs <pod> -n broken --previous` を使ってください。
- 答案ファイルには **エラーを含む実際の出力** が必要です — 手書きの要約は認められません。
- `kubectl edit deploy orders -n broken` でコマンドを直しても同じく正解です。

## Q9 廃止された API バージョンの修正

`apps/v1beta1` と `batch/v1beta1` はとうに削除されています。現行バージョンは `apps/v1` と
`batch/v1` です。

```bash
sed -i -e 's|apps/v1beta1|apps/v1|' -e 's|batch/v1beta1|batch/v1|' ~/work/legacy/stack.yaml
kubectl apply -f ~/work/legacy/stack.yaml
```

よくある間違い

- 現行バージョンが分からないときは `kubectl api-resources | grep -i cronjob` か
  `kubectl explain cronjob` が実際の group/version を表示します。
- **ファイル自体** が採点対象(2 点)です — 別の場所に新しい YAML を書いてファイルを放置すると
  その項目を落とします。
- 適用後に report-api が Ready か確認してください。最後の 1 点を取りこぼすことがあります。

## Q10 ConfigMap と Secret の利用

作成は命令型 2 行、利用は YAML で。

```bash
kubectl create configmap app-config -n dev --from-literal=mode=production --from-literal=timeout=30
kubectl create secret generic db-cred -n dev --from-literal=user=admin --from-literal=pass=S3cret1
```

```yaml
spec:
  volumes: [{ name: creds, secret: { secretName: db-cred } }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef: { name: app-config, key: mode }
      volumeMounts: [{ name: creds, mountPath: /etc/creds, readOnly: true }]
```

よくある間違い

- リテラルの `env: [{name: APP_MODE, value: production}]` は **認められません** — 採点は
  `configMapKeyRef` による参照を確認します。
- Secret ボリュームはキーごとに 1 ファイルになります(`/etc/creds/user`、`/etc/creds/pass`)。
- Pod 作成後に ConfigMap を編集しても環境変数は変わりません — 値を間違えたら Pod を作り直します。

## Q11 SecurityContext — 非 root・読み取り専用

runAsUser/runAsNonRoot は Pod レベルでも構いませんが、残りの 3 つは **コンテナレベル** です。

```yaml
spec:
  securityContext: { runAsUser: 1000, runAsNonRoot: true }
  volumes: [{ name: tmp, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      volumeMounts: [{ name: tmp, mountPath: /tmp }]
```

よくある間違い

- `allowPrivilegeEscalation`・`readOnlyRootFilesystem`・`capabilities` を Pod レベルに書くと
  **スキーマエラー** です — コンテナの securityContext にしか存在しません。
- ルートが読み取り専用だと、書き込み領域なしでは起動に失敗するイメージがあります — `/tmp` の
  emptyDir はそのための備えです。
- uid が実際に効いているか確認します: `kubectl exec secure-app -n dev -- id -u`。

## Q12 ServiceAccount とトークン自動マウント

```bash
kubectl create serviceaccount app-sa -n dev
```

```yaml
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
```

よくある間違い

- `automountServiceAccountToken` は **Pod スペックレベル** のフィールドです(コンテナの下ではありません)。
- SA 側に設定しても効果は同じですが、問題は「Pod スペックで無効化する」と指定しているので、
  スペックの採点項目(1 点)は Pod 側の設定を要求します。
- `kubectl exec sa-pod -n dev -- ls /var/run/secrets/kubernetes.io/serviceaccount` で確認します
  — 「No such file or directory」が正しい状態です。

## Q13 リソース要求・上限 — Quota の範囲内で

```bash
kubectl create deploy worker -n batch --image=busybox:1.36 --replicas=2 --dry-run=client -o yaml > worker.yaml
# command と resources を埋めてから apply する
```

```yaml
resources:
  requests: { cpu: 100m, memory: 64Mi }
  limits: { cpu: 200m, memory: 128Mi }
```

よくある間違い

- **この問題の存在理由**: ResourceQuota のある名前空間では requests のない Pod は即座に
  拒否されます。Deployment は作成されても Pod は 0 個 —
  `kubectl get events -n batch` に `failed quota` が出ます。
- 問題の表記をそのまま使ってください。Kubernetes は `0.1` と `100m` を同じに扱いますが、
  採点は正規化された文字列(100m)を比較するので、問題の形式を写すのが安全です。

## Q14 Service — ClusterIP と NodePort

```bash
kubectl expose deploy frontend -n prod --name=frontend-svc --port=80 --target-port=80
kubectl expose deploy frontend -n prod --name=frontend-np --port=80 --target-port=80 --type=NodePort \
  --dry-run=client -o yaml > np.yaml
# ports[0] に nodePort: 30080 を追記してから apply する
```

よくある間違い

- `expose` では nodePort の値を指定できません — dry-run の YAML に `nodePort: 30080` を手で足します。
- 手書きのセレクターが `app: frontend` でないとエンドポイントが空になり、通信の 3 点が
  まとめて落ちます。
- クラスタ内の確認: `kubectl exec client -n dev -- wget -qO- http://frontend-svc.prod.svc.cluster.local`。

## Q15 Ingress リソースの作成

コントローラがなくても、リソースは仕様どおりに書きます。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: frontend-svc, port: { number: 80 } } }
          - path: /shop
            pathType: Prefix
            backend: { service: { name: shop-svc, port: { number: 80 } } }
```

よくある間違い

- `pathType` は必須です — 省くと apply が拒否されます。問題は Prefix を指定しています。
- `port: { number: 80 }` を `port: 80` と略すとスキーマエラーです。
- 2 つの path は **同じ host ルールの下** に置きます。host エントリを 2 つに分けても採点は
  通りますが、1 つのルールが基準形です。

## Q16 NetworkPolicy — 指定クライアントのみ許可

まず対象 Pod を選び(podSelector、from ではありません)、次に from の下に許可する相手を列挙します。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: cache-guard, namespace: dev }
spec:
  podSelector:
    matchLabels: { app: cache }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: client }
      ports:
        - { protocol: TCP, port: 80 }
```

よくある間違い

- `podSelector`(対象)と `from.podSelector`(許可する送信元)を取り違えると正反対の
  ポリシーになります。
- 選択された Pod に対して NetworkPolicy は **明示的に許可していないものをすべて遮断** します —
  別の deny ルールは不要です。
- このクラスタはポリシーを実際に強制します(kube-router)。提出前に
  `kubectl exec intruder -n dev -- wget -T2 -qO- http://<cache の IP>` が **失敗する** ことを
  確認してください。
