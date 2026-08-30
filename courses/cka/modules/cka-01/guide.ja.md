# CKA 模擬試験 1回目 (120分 · 17問 · 100点)

Linux Foundation **CKA(Certified Kubernetes Administrator)** の実技試験形式をそのまま移した
模擬試験です。問題は本番と同じドメイン配点で配分しています。

| ドメイン | 配点 | 問題 |
|---|---|---|
| クラスタアーキテクチャ・インストール・構成 | 25 | Q1 Q2 Q3 Q4 Q16 Q17 |
| ワークロードとスケジューリング | 15 | Q5 Q6 Q7 |
| サービスとネットワーク | 20 | Q8 Q9 Q10 |
| ストレージ | 10 | Q11 Q12 |
| トラブルシューティング | 30 | Q13 Q14 Q15 |

**進め方**

- 制限時間は **120分**。残り時間は画面上部に表示されます。
- 問題は **順不同** で解いて構いません。得意なものから片付けるのが本番の戦略です。
  ただし **Q9 は Q5 の `web` Pod が動いていないと** 通信で採点できません。
- 本番と同じく **解いている間は採点結果が出ません**。解き終えたら下の
  **[提出して採点]** を一度押すと 17 問が一括で採点されます(問題ごとに実クラスタを確認するため
  1〜2 分かかります)。
- **部分点があります。** 問題ごとに採点項目が複数あり、満たした項目の分だけ点が入ります。
  採点が終わると画面上部に合計点と問題別の点数・採点項目が表示され、
  **下部に間違えた問題の解説** が付きます。
- **合格ラインは 66 点** です。超えればお祝いメッセージと修了バッジがもらえます(満点でなくて構いません)。
- 提出後も残り時間内で修正して **再採点** できます。最高点が記録されます。
- 問題が名前空間を指定している場合は **必ずその名前空間に** 作成してください。

**試験の言語**

本番の CKA は **英語・日本語・簡体字中国語** のみで提供されます。この模擬試験もその 3 言語
(および韓国語)に対応しているので、実際に受験する言語で練習したい場合は画面上部の言語切り替えを
使ってください。

**環境**

Pod の中で動く **シングルノード k3s v1.36** クラスタで、あなた専用です。`kubectl`(別名 `k`)と
`KUBECONFIG` は設定済みで、`sudo` はパスワード不要です。`jq` と `vi`/`nano` が使えます。
本番と同様に [Kubernetes 公式ドキュメント](https://kubernetes.io/docs/) を参照して構いません —
むしろドキュメントの YAML 例を写して直すのが試験の定石です。

```bash
kubectl get nodes       # lab(コントロールプレーン) + worker-1・worker-2(仮想ワーカー)
kubectl get ns          # app-prod, ops, broken, maint が用意されています
```

**本番と異なる点** (環境上の制約)

- **kubeadm でのクラスタアップグレード** は出題していません。k3s ベースのため kubeadm の
  手順は再現できません — この領域は別途学習してください。
- **Q16 の etcd リストアはオフライン段階まで** を採点します(`--data-dir` リストア)。復元
  データへの本番クラスタの切り替えは k3s 固有の手順のため範囲外です。
- **worker-1・worker-2 は KWOK 仮想ワーカー** です。スケジュール・退避・drain は本物と同じに
  動作しますが、その上の Pod が実プロセスを実行することはありません(Q17 の採点に影響は
  ありません)。
- Ingress コントローラがないため **Q10 はリソースの記述までを採点** します(実際のルーティングは
  確認しません)。

> 時間節約のコツ: `kubectl create ... --dry-run=client -o yaml > q.yaml` で雛形を作ってから
> 編集する習慣が最も効きます。`kubectl explain <リソース>.<フィールド>` もすぐ使えます。

## 1. Q1 (5点) RBAC — ServiceAccount・Role・RoleBinding

名前空間 `app-prod` に、デプロイツール用の **読み取り専用** の ID を作成してください。

- ServiceAccount `deploy-bot`
- Role `pod-reader` — `pods` と `deployments`(apps グループ)に対して **`get`, `list`, `watch` のみ**
- RoleBinding `deploy-bot-rb` — その Role を `deploy-bot` に紐付ける

権限は `app-prod` の中だけで有効でなければなりません。他の名前空間の Pod が一覧できたり、
Pod を作成・削除できたりすると不正解です。

```bash
kubectl auth can-i list pods -n app-prod --as=system:serviceaccount:app-prod:deploy-bot
```

> 参考: [RBAC 認可](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 2. Q2 (4点) CSR の承認とユーザー権限の付与

新しい開発者 `dev-user` のクライアント証明書署名要求が **承認待ち** になっています。

```bash
kubectl get csr
```

1. CSR `dev-user` を **承認** して証明書が発行されるようにしてください。
2. ユーザー(User) `dev-user` が `app-prod` を **閲覧のみ** できるよう、組み込み ClusterRole
   `view` を使う RoleBinding `dev-user-view` を `app-prod` に作成してください。

`edit` や `admin` をバインドすると不正解です。確認:

```bash
kubectl auth can-i list pods   -n app-prod --as=dev-user   # yes
kubectl auth can-i delete pods -n app-prod --as=dev-user   # no
```

> 参考: [証明書と CSR](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)

## 3. Q3 (4点) 静的 Pod(static pod)の作成

ノードの kubelet が **直接** 管理する静的 Pod を作成してください。API サーバー経由で作ってはいけません。

- 名前 `ops-static`、名前空間 `default`
- イメージ `busybox:1.36`、動き続けるコマンド(例: `sleep 86400`)

この環境(k3s)のマニフェストディレクトリは次のとおりです。

```bash
ls /var/lib/rancher/k3s/agent/pod-manifests/
```

静的 Pod は API サーバー上に **ミラー Pod** として現れ、名前の後ろにノード名が付きます
(`ops-static-<ノード名>`)。ファイルを置いて数秒待ってから `kubectl get pod` で確認してください。

> 参考: [静的 Pod](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

## 4. Q4 (3点) ResourceQuota・LimitRange

名前空間 `ops` の使用量を制限してください。

ResourceQuota `ops-quota`:

| 項目 | 値 |
|---|---|
| `pods` | 5 |
| `requests.cpu` | 1 |
| `requests.memory` | 1Gi |

LimitRange `ops-limits` (`type: Container`):

| 項目 | 値 |
|---|---|
| `defaultRequest.cpu` | 100m |
| `defaultRequest.memory` | 128Mi |
| `default.cpu` | 200m |
| `default.memory` | 256Mi |

クォータが `requests.*` を制限すると、その名前空間の **すべての Pod が requests を宣言** しなければ
ならなくなります — LimitRange の既定値がその代わりを務めます。

> 参考: [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/) ·
> [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)

## 5. Q5 (6点) Deployment とロールアウト戦略

名前空間 `app-prod` に Deployment `web` を作成してください。

- レプリカ **3**、イメージ `nginx:1.26`
- コンテナの requests は `cpu: 50m`、`memory: 64Mi`
- ロールアウト戦略は `RollingUpdate` で **無停止**: `maxSurge: 1`、`maxUnavailable: 0`
- Pod ラベルは `app=web`(後の問題がこのラベルを使います)

3 つすべてが Ready になっている必要があります。

> 参考: [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 6. Q6 (4点) DaemonSet のデプロイ

名前空間 `ops` に DaemonSet `node-agent` をデプロイしてください。

- イメージ `busybox:1.36`、動き続けるコマンド
- **requests を明示** すること(例: `cpu: 10m`、`memory: 16Mi`) — `ops` にはクォータがあります
- すべてのノードで Pod が Ready であること

> 参考: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)

## 7. Q7 (5点) サイドカーコンテナと共有ボリューム

名前空間 `app-prod` に Pod `logger` を作成してください。**2 つ**のコンテナが 1 つの `emptyDir`
ボリュームを **同じパス `/var/log/app`** で共有する必要があります。

- コンテナ `app` — 定期的に `/var/log/app/app.log` へ追記する
- コンテナ `sidecar` — 同じファイルを読む(例: `tail -f`)

採点は **sidecar の中からそのログファイルが実際に読めるか** で行います。マウントしただけで
何も書かなければ通りません。

> 参考: [ロギングアーキテクチャ — サイドカー](https://kubernetes.io/docs/concepts/cluster-administration/logging/#sidecar-container-with-logging-agent)

## 8. Q8 (7点) Service — ClusterIP と NodePort

Q5 の `web` Pod を 2 通りで公開してください。どちらも名前空間 `app-prod` です。

| 名前 | タイプ | ポート |
|---|---|---|
| `web-svc` | ClusterIP | `80` → コンテナ `80` |
| `web-np` | NodePort | `80` → コンテナ `80`、nodePort **30080** |

どちらの Service もエンドポイントが **3 件** あり、クラスタ内から DNS 名
`web-svc.app-prod.svc.cluster.local` で実際に応答が返る必要があります。

> 参考: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 9. Q9 (7点) NetworkPolicy による通信制限

名前空間 `app-prod` を既定拒否にしたうえで、指定したクライアントだけを通してください。

1. `default-deny` — `app-prod` の **すべての Pod** に対して **Ingress を全面拒否**
   (`podSelector: {}`、`policyTypes: ["Ingress"]`)
2. `allow-client` — `app=web` の Pod に対して、**`role=client` ラベルを持つ Pod** からの
   **TCP 80** のみ許可

名前空間にはすでに `client`(`role=client`)と `intruder`(`role=outsider`)の Pod があります。
採点は実際の通信で行います — `client` は `web` に到達でき、`intruder` は遮断されなければなりません。

```bash
kubectl exec -n app-prod client   -- wget -T3 -qO- http://<web Pod の IP>/
kubectl exec -n app-prod intruder -- wget -T3 -qO- http://<web Pod の IP>/   # 失敗するのが正解
```

> 参考: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 10. Q10 (6点) Ingress リソースの作成

名前空間 `app-prod` に Ingress `web-ing` を作成してください。

- host `shop.example.com`
- path `/`、`pathType: Prefix`
- バックエンドは Service `web-svc` のポート `80`

この環境には Ingress コントローラがないため **リソース定義のみを採点** します(実際のルーティングは
確認しません)。

> 参考: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 11. Q11 (5点) PV・PVC の静的バインド

静的に用意したボリュームを Pod に接続してください。

1. PersistentVolume `pv-data` — 容量 `1Gi`、`ReadWriteOnce`、
   `storageClassName: manual`、hostPath `/mnt/data`
2. PersistentVolumeClaim `pvc-data`(`app-prod`) — `1Gi`、`ReadWriteOnce`、
   同じ `storageClassName` で **`pv-data` にバインド** されること
3. Pod `data-user`(`app-prod`) — その PVC を `/data` にマウントして Running

`storageClassName` を空にすると既定の StorageClass が動的に別のボリュームを作って結び付きます。
その場合 `Bound` にはなっても `pv-data` ではないので不正解です。

> 参考: [PV・PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## 12. Q12 (5点) 動的プロビジョニングとデータ書き込み

既定の StorageClass でボリュームを **動的に作成** して使ってください。

1. PVC `pvc-dyn`(`app-prod`) — `storageClassName: local-path`、`500Mi`、`ReadWriteOnce`
2. Pod `writer`(`app-prod`) — その PVC を `/data` にマウントし、
   `/data/hello.txt` に `cka` と書いたうえで動き続ける

`local-path` は `WaitForFirstConsumer` なので、**Pod が使うまで PVC は Pending のまま** です。
それが正常です — Pod を作ってください。

```bash
kubectl get sc
```

> 参考: [StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 13. Q13 (10点) 障害対応 — 起動しない Deployment

名前空間 `broken` の Deployment `api` が **いつまでも Ready になりません。** 原因を突き止めて
直してください。名前・名前空間・レプリカ数(**2**)はそのままにすること。

```bash
kubectl get pods -n broken
kubectl describe pod -n broken <pod>      # Events を読む
```

2 つの Pod が Running かつ Ready で、失敗した Pod が残っていない状態にしてください。

> 参考: [アプリケーションのトラブルシューティング](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 14. Q14 (10点) 障害対応 — エンドポイントが空の Service

名前空間 `broken` の Service `cache-svc` が応答しません。バックエンドの Deployment `cache`
自体は正常です。

```bash
kubectl get endpoints cache-svc -n broken
kubectl get pods -n broken --show-labels
kubectl describe svc cache-svc -n broken
```

**誤りは 2 か所** です。サービスの `port` は `80` のまま、エンドポイントが埋まり実際に HTTP 応答が
返るように直してください。

> 参考: [Service のデバッグ](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

## 15. Q15 (10点) 障害対応 — CrashLoopBackOff と原因報告

名前空間 `broken` の Deployment `worker` が `CrashLoopBackOff` で再起動を繰り返しています。

```bash
kubectl logs -n broken deploy/worker
kubectl describe pod -n broken <pod>
```

1. 原因を取り除いて Pod が **安定して** 動くようにしてください(再起動ループが止まること)。
2. 原因となったリソースを `~/answers/q15.txt` に **小文字 1 行、`<kind>/<name>` 形式** で
   書いてください(例: `deployment/foo`)。

採点はコンテナが再起動なしで 20 秒以上動いていることを条件にします。直した直後に提出すると
届かないことがあるので、少し待ってから提出してください。

> 参考: [Pod のデバッグ](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

## 16. Q16 (6点) etcd のバックアップとオフラインリストア

このクラスタのデータストアは **組み込み etcd** です。以下の接続情報で作業してください
(証明書は root 所有のため `sudo` が必要です)。

- エンドポイント: `https://127.0.0.1:2379`
- CA: `/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt`
- 証明書: `/var/lib/rancher/k3s/server/tls/etcd/server-client.crt`
- キー: `/var/lib/rancher/k3s/server/tls/etcd/server-client.key`

1. `etcdctl` でスナップショットを **`~/backup/etcd-snap.db`** に保存してください。
2. そのスナップショットを `etcdutl` で **`~/backup/restored`** ディレクトリに
   **オフラインでリストア** してください(`--data-dir` を使用。対象ディレクトリが
   既に存在すると失敗します)。

**注意**: 復元データへ稼働中クラスタを切り替える手順は本試験の範囲外です。
`k3s server --cluster-reset` などを実行すると他の問題のリソースが消えることがあります。

> 参考: [etcd クラスタの運用](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

## 17. Q17 (3点) ノードの drain — worker-1 のメンテナンス

ワーカーノード `worker-1` がカーネルパッチのため間もなく停止します。名前空間 `maint` の
Deployment `payments`(レプリカ 4)が worker-1/worker-2 にまたがって動いています。

1. `worker-1` を **安全に空にしてください** — スケジュール不可の状態を維持し、DaemonSet は
   無視します。
2. 作業後も `payments` は **4 個すべて稼働** していなければなりません(worker-2 へ移動します)。

```bash
kubectl get pods -n maint -o wide
```

> 参考: [ノードを安全にドレインする](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
