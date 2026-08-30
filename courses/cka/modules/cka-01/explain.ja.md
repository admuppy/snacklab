# 解説

提出後、満点を取れなかった問題についてのみ以下の解説が表示されます。
正解は一つではありません — 採点は「結果が仕様どおりか」を見るので、以下は最短の基準解です。

## Q1 RBAC — ServiceAccount・Role・RoleBinding

読み取り専用の ID は命令型のコマンド 3 行で作れます。試験で YAML を手書きすると時間を失います。

```bash
kubectl create serviceaccount deploy-bot -n app-prod
kubectl create role pod-reader -n app-prod --verb=get,list,watch --resource=pods,deployments.apps
kubectl create rolebinding deploy-bot-rb -n app-prod --role=pod-reader --serviceaccount=app-prod:deploy-bot
```

よくある間違い

- `--resource=deployments` だけだと apiGroup が core になります。`deployments.apps` と書きます。
- `ClusterRole`/`ClusterRoleBinding` で作ると権限が他の名前空間まで漏れて減点されます。
- `--serviceaccount=` は **名前空間:名前** の形式です。

採点は `kubectl auth can-i --as=system:serviceaccount:app-prod:deploy-bot` の結果で行うので、
ルールの書き方に関わらず **実際に付与された権限** だけが問われます。

## Q2 CSR の承認とユーザー権限の付与

```bash
kubectl certificate approve dev-user
kubectl create rolebinding dev-user-view -n app-prod --clusterrole=view --user=dev-user
```

よくある間違い

- `--serviceaccount=` でバインドすると User `dev-user` ではなく SA に権限が付きます。**`--user=`** です。
- `edit`/`admin` をバインドすると削除までできてしまい減点です。読み取り専用は組み込み ClusterRole `view`。
- 承認後に `kubectl get csr dev-user -o jsonpath='{.status.certificate}'` が空でないことを確認します。
  拒否(`deny`)した CSR は元に戻せないので、その場合はラボを再開してください。

## Q3 静的 Pod(static pod)の作成

静的 Pod は API サーバーではなく **kubelet がディスク上のマニフェストディレクトリから** 読んで起動します。
k3s のパスは `/var/lib/rancher/k3s/agent/pod-manifests/` です。

```bash
kubectl run ops-static --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sh -c "sleep 86400" > /tmp/ops-static.yaml
sudo cp /tmp/ops-static.yaml /var/lib/rancher/k3s/agent/pod-manifests/
```

よくある間違い

- `kubectl apply` で作ると普通の Pod です。採点は `kubernetes.io/config.source=file` アノテーションを見ます。
- ミラー Pod の名前にはマニフェストの名前の後ろに **ノード名が付きます**(`ops-static-<node>`)。そのままで構いません。
- ファイルを置いてから kubelet が拾うまで数秒かかります。

## Q4 ResourceQuota・LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: ops-quota, namespace: ops }
spec:
  hard:
    pods: "5"
    requests.cpu: "1"
    requests.memory: 1Gi
---
apiVersion: v1
kind: LimitRange
metadata: { name: ops-limits, namespace: ops }
spec:
  limits:
    - type: Container
      defaultRequest: { cpu: 100m, memory: 128Mi }
      default: { cpu: 200m, memory: 256Mi }
```

よくある間違い

- `pods: 5` と数値で書くとパースエラーです — クォータ値は **文字列**(`"5"`)にします。
- LimitRange の `default` は limit、`defaultRequest` は request です。取り違えやすい点です。
- `type: Container` である必要があります(`Pod` は意味が異なります)。

## Q5 Deployment とロールアウト戦略

```bash
kubectl create deploy web -n app-prod --image=nginx:1.26 --replicas=3 --dry-run=client -o yaml > web.yaml
```
で雛形を作り、`strategy` と `resources.requests` だけ埋めるのが最短です。

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 50m, memory: 64Mi } }
```

よくある間違い

- `maxUnavailable: 0` を書き忘れると既定の 25% が適用され減点されます。
- `resources.limits` ではなく **`requests`** です。
- この問題の `web` Pod は Q8・Q9 の採点対象でもあります。まず 3 つが Ready か確認してください。

## Q6 DaemonSet のデプロイ

DaemonSet は `kubectl create` では作れません。Deployment の雛形を出して `kind` を変え、
`replicas`・`strategy` を消すのが試験場の定石です。

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: ops }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
```

よくある間違い

- `replicas` を残すと DaemonSet のスキーマにないフィールドとして拒否されます。
- busybox は既定のコマンドがすぐ終わるため CrashLoop に陥ります。必ず `sleep` 系のコマンドを与えます。
- `resources.requests` の cpu・memory を **両方** 書く必要があります。

## Q7 サイドカーコンテナと共有ボリューム

要点は **同じボリュームを 2 つのコンテナが同じパスにマウントする** ことです。

```yaml
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "tail -f /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

よくある間違い

- ボリュームを 2 つ作ると仕様上は正しく見えても実際には共有されません。採点は sidecar から
  `/var/log/app/app.log` を **実際に読んで** 確認します。
- コンテナ名は `app`、`sidecar` と指定されています。

## Q8 Service — ClusterIP と NodePort

```bash
kubectl expose deploy web -n app-prod --name=web-svc --port=80 --target-port=80
kubectl expose deploy web -n app-prod --name=web-np --type=NodePort --port=80 --target-port=80
kubectl patch svc web-np -n app-prod --type=merge -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'
```

よくある間違い

- `nodePort` は `expose` では指定できません — 作成後に patch するか YAML で作ります。
- エンドポイントが空ならセレクターが Pod ラベル(`app=web`)と一致していません。
  `kubectl get endpoints web-svc -n app-prod` で確認します。
- 採点は `client` Pod から `web-svc.app-prod.svc.cluster.local` への **実際の HTTP 応答** まで見ます。

## Q9 NetworkPolicy による通信制限

2 枚必要です — 全面拒否(default deny)と、例外を許可するもの。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: app-prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client, namespace: app-prod }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { role: client } }
      ports: [{ protocol: TCP, port: 80 }]
```

よくある間違い

- `podSelector: {}` が「名前空間の全 Pod」という意味です。空にするのと省略するのは違います。
- `from` の **同じ項目の中に** `podSelector:` と `namespaceSelector:` を並べると AND になります。
  別項目(`-` を 2 つ)にすると OR です。
- 採点はポリシーの形だけでなく、`client` は通り `intruder` は遮断されるかを実通信で判定します。
  そのためには Q5 の `web` Pod が動いている必要があります。

## Q10 Ingress リソースの作成

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: app-prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
```

よくある間違い

- `pathType` は必須フィールドです。抜けると作成自体が拒否されます。
- `extensions/v1beta1` はとうに削除されています — `networking.k8s.io/v1` です。
- バックエンドは旧形式の `serviceName`/`servicePort` ではなく `service.name`/`service.port.number` です。

## Q11 PV・PVC の静的バインド

静的バインドは **PV と PVC の storageClassName・accessModes・容量が揃って初めて** 結び付きます。

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 1Gi }
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  hostPath: { path: /mnt/data, type: DirectoryOrCreate }
```
PVC も同じ `storageClassName: manual`、`ReadWriteOnce`、1Gi で作り、Pod で `/data` にマウントします。

よくある間違い

- PVC に `storageClassName` を書かないと既定 SC(local-path)で **動的生成** され、pv-data 以外の
  ボリュームに結び付きます。採点は `spec.volumeName == pv-data` まで見ます。
- 誤ってバインド済みの PVC は修正できません。削除して作り直してください。

## Q12 動的プロビジョニングとデータ書き込み

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-dyn, namespace: app-prod }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources: { requests: { storage: 500Mi } }
```

よくある間違い

- local-path は `WaitForFirstConsumer` です — **Pod が使うまで Pending が正常** です。PVC だけ作って
  Bound を待つのは時間の無駄です。
- 容量の単位は `500Mi`(`500M` ではない)です。
- 採点はボリュームの `/data/hello.txt` の内容まで確認します。Pod に書かせても、
  `kubectl exec writer -- sh -c 'echo cka > /data/hello.txt'` で直接書いても構いません。

## Q13 障害対応 — 起動しない Deployment

```bash
kubectl -n broken describe pod -l app=api | tail -20   # ErrImagePull / InvalidImageName
kubectl -n broken set image deploy/api api=nginx:1.26
kubectl -n broken rollout status deploy/api
```

よくある間違い

- まず Pending なのかイメージ取得失敗なのかを切り分けます。`describe` の Events が答えを教えてくれます。
- Deployment を削除して作り直しても認められますが、**名前・名前空間・replicas(2)** はそのままにします。
- 直した後に旧 ReplicaSet の失敗 Pod が残っていると減点です。`rollout status` で収束を確認してください。

## Q14 障害対応 — エンドポイントが空の Service

セレクターと targetPort の **2 か所** がずれています。Pod のラベルとコンテナポートから確認します。

```bash
kubectl -n broken get pod --show-labels
kubectl -n broken get svc cache-svc -o yaml | head -30
kubectl -n broken patch svc cache-svc --type=merge \
  -p '{"spec":{"selector":{"app":"cache"},"ports":[{"port":80,"targetPort":80}]}}'
kubectl -n broken get endpoints cache-svc
```

よくある間違い

- `port` は Service が公開するポート、`targetPort` はコンテナのポートです。Service の 80 は 80 のままに。
- エンドポイントが埋まっても targetPort が違えば応答は返りません。採点は実際の HTTP 応答まで見ます。
- `kubectl edit svc` でも直せますが、試験では patch のほうが速く間違いも少ないです。

## Q15 障害対応 — CrashLoopBackOff と原因報告

```bash
kubectl -n broken logs deploy/worker --previous     # 設定ファイル/キーが見つからないログ
kubectl -n broken describe pod -l app=worker        # マウントした ConfigMap のキーを確認
kubectl -n broken get cm worker-config -o yaml
```

コンテナが期待するキーと ConfigMap のキーがずれています。ConfigMap を直してロールアウトし直します。

```bash
kubectl -n broken rollout restart deploy/worker
echo "configmap/worker-config" > ~/answers/q15.txt
```

よくある間違い

- 報告ファイル `~/answers/q15.txt` は **`configmap/worker-config`** の 1 行である必要があります
  (大文字小文字と空白は無視されます)。
- ConfigMap を直しても **起動済みの Pod は更新されません**。`rollout restart` が必要です。
- 採点は Pod が再起動なしで 20 秒以上動いていることを見ます — 直した直後に提出すると届かないことがあります。

## Q16 etcd のバックアップとオフラインリストア

バックアップは `etcdctl`、オフラインリストアは `etcdutl` — 本番試験と同じツールです。
証明書が root 所有のため、どちらも `sudo` が要ります。

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  snapshot save ~/backup/etcd-snap.db
sudo etcdutl snapshot restore ~/backup/etcd-snap.db --data-dir ~/backup/restored
sudo etcdutl snapshot status ~/backup/etcd-snap.db   # 検証の習慣を
```

よくある間違い

- `--cacert`/`--cert`/`--key` のどれかが欠けると TLS ハンドシェイクで失敗します。
- `--data-dir` が既に存在すると restore は拒否します — 新しいディレクトリ名を指定してください。
- `etcdctl snapshot restore` も動きますが deprecated です。試験では `etcdutl` を使いましょう。
- 採点はスナップショットのリビジョンとリストア先の `member/snap/db` を見ます — 空ファイルや
  手作りディレクトリでは点になりません。

## Q17 ノードの drain — worker-1 のメンテナンス

1 行で済みます。drain は cordon を含みます。

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n maint -o wide   # 4 個すべて worker-2 で Running なら完了
```

よくある間違い

- `--ignore-daemonsets` なしでは DaemonSet Pod のせいで drain が拒否されることがあります。
- `cordon` だけでは新規スケジュールを止めるだけで既存 Pod は残ります — 退避してこそ drain です。
- 作業後に `uncordon` すると減点です。メンテナンスのシナリオなのでスケジュール不可を
  維持してください。
