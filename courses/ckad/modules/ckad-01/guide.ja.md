# CKAD 模擬試験 1回目 (120分 · 16問 · 100点)

Linux Foundation **CKAD(Certified Kubernetes Application Developer)** の実技試験形式をそのまま移した
模擬試験です。問題は本番と同じドメイン配点で配分しています。

| ドメイン | 配点 | 問題 |
|---|---|---|
| アプリケーションの設計とビルド | 20 | Q1 Q2 Q3 |
| アプリケーションのデプロイ | 20 | Q4 Q5 Q6 |
| アプリケーションの可観測性とメンテナンス | 15 | Q7 Q8 Q9 |
| アプリケーションの環境・構成・セキュリティ | 25 | Q10 Q11 Q12 Q13 |
| サービスとネットワーク | 20 | Q14 Q15 Q16 |

**進め方**

- 制限時間は **120分**。残り時間は画面上部に表示されます。
- 問題は **順不同** で解いて構いません。得意なものから片付けるのが本番の戦略です。
- 本番と同じく **解いている間は採点結果が出ません**。解き終えたら下の
  **[提出して採点]** を一度押すと 16 問が一括で採点されます(問題ごとに実クラスタを確認するため
  1〜2 分かかります)。
- **部分点があります。** 問題ごとに採点項目が複数あり、満たした項目の分だけ点が入ります。
  採点が終わると画面上部に合計点と問題別の点数が表示され、
  **下部に間違えた問題の解説** が付きます。
- **合格ラインは 66 点** です。超えればお祝いメッセージと修了バッジがもらえます(満点でなくて構いません)。
- 提出後も残り時間内で修正して **再採点** できます。最高点が記録されます。
- 問題が名前空間を指定している場合は **必ずその名前空間に** 作成してください。

**試験の言語**

本番の CKAD は **英語・日本語・簡体字中国語** のみで提供されます。この模擬試験もその 3 言語
(および韓国語)に対応しているので、実際に受験する言語の文章に慣れたい場合は画面上部の言語切り替えを
**English / 日本語 / 简体中文** にしてもう一周してみてください。

**環境**

Pod の中で動く **シングルノード k3s v1.36** クラスタで、あなた専用です。`kubectl`(別名 `k`)と
`KUBECONFIG` は設定済みで、`sudo` はパスワード不要です。`jq` と `vi`/`nano` が使えます。
本番と同様に [Kubernetes 公式ドキュメント](https://kubernetes.io/docs/) を参照して構いません —
むしろドキュメントの YAML 例を写して直すのが試験の定石です。

```bash
kubectl get nodes
kubectl get ns          # dev, prod, batch, broken が用意されています
```

**本番と異なる点** (環境上の制約)

- **Helm の問題はありません**(環境に helm バイナリがないため)。Kustomize は `kubectl apply -k` で扱います。
- Ingress コントローラがないため **Q15 はリソースの記述までを採点** します(実際のルーティングは確認しません)。
- コンテナイメージのビルド(Dockerfile の作成、docker build)は別途学習してください。

> 時間節約のコツ: `kubectl create ... --dry-run=client -o yaml > q.yaml` で雛形を作ってから
> 編集する習慣が最も効きます。`kubectl explain <リソース>.<フィールド>` もすぐ使えます。

## 1. Q1 (7点) サイドカーコンテナ — ログストリーミング

名前空間 `dev` に Pod `logger` を作成してください。2 つのコンテナが **emptyDir ボリューム `logs`** を共有します。

- メインコンテナ `app` — イメージ `busybox:1.36`、コマンド:
  `sh -c "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"`
  ボリュームを `/var/log/app` にマウントします。
- サイドカーコンテナ `streamer` — イメージ `busybox:1.36`、コマンド:
  `sh -c "tail -F /var/log/app/app.log"`。同じパスにボリュームをマウントします。

採点は Pod の構成(2 コンテナ、emptyDir の共有)と、
**`kubectl logs logger -c streamer` に `tick` の行が実際に流れているか** を確認します。

> 参考: [サイドカーコンテナ](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

## 2. Q2 (7点) Job と CronJob

名前空間 `batch` に:

1. Job `pi` — イメージ `busybox:1.36`、コマンド `sh -c "echo 3.14159"`、
   **completions 3 · parallelism 2**、`restartPolicy: Never`。3 回すべて成功する必要があります。
2. CronJob `cleanup` — イメージ `busybox:1.36`、コマンド `sh -c "echo cleaned"`、
   スケジュールは **毎日 03:00**(`0 3 * * *`)、**concurrencyPolicy Forbid**、
   **successfulJobsHistoryLimit 1**、`restartPolicy: Never`。

採点は Job のスペック、**`status.succeeded` が 3 に達したか**、および
CronJob のスケジュールとポリシーのフィールドを確認します。

> 参考: [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) ·
> [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-job/)

## 3. Q3 (6点) init コンテナによるコンテンツ準備

名前空間 `dev` に Pod `web-init` を作成してください。

- init コンテナ `setup` — イメージ `busybox:1.36`、emptyDir ボリューム `web` を `/work` にマウントし、
  `sh -c "echo ready-to-serve > /work/index.html"` を実行します。
- メインコンテナ `web` — イメージ `nginx:1.26`、同じボリュームを `/usr/share/nginx/html` にマウントします。

採点は init コンテナの構成と、**Pod IP への HTTP リクエストが `ready-to-serve` を返すか**
を確認します。

> 参考: [Init コンテナ](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

## 4. Q4 (7点) ローリングアップデート — 無停止戦略

名前空間 `prod` には Deployment `api`(nginx:1.25、replicas 2)が用意されています。

1. 更新戦略を **maxSurge 1 · maxUnavailable 0**(無停止の条件)に設定してください。
2. コンテナイメージを **`nginx:1.26`** にロールしてください。
3. 更新は完了している必要があります: **2 つのレプリカが新バージョンで Ready** であること。

採点は戦略のフィールド、新しいイメージ、ロールアウトの完了(リビジョンの増加、全 Pod Ready)を
確認します。

> 参考: [Deployment の更新](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 5. Q5 (6点) カナリアデプロイ — トラフィックの 25%

名前空間 `prod` には Deployment `shop`(track=stable、replicas 4)と Service `shop-svc`
(セレクター `app: shop`)があります。**トラフィックの 25% を新バージョンのカナリアへ** 送ってください。

1. Deployment `shop-canary` を作成 — イメージ **`nginx:1.26`**、replicas **1**、
   Pod ラベルは **`app: shop` + `track: canary`**(サービスがカナリアも拾うようにするためです)。
2. 既存の `shop` を replicas **3** に縮小し、サービスの背後の Pod を
   **stable 3 : canary 1** にしてください。

採点はカナリア Deployment のスペック、サービスのエンドポイントにカナリア Pod が含まれること、
そして 3:1 の比率を確認します。

> 参考: [カナリアデプロイ](https://kubernetes.io/docs/concepts/workloads/management/#canary-deployments)

## 6. Q6 (7点) Kustomize オーバーレイ

`~/work/kustomize/base` に Deployment `hello-web`(nginx:1.25、replicas 1)の base があります。

1. **`~/work/kustomize/overlays/prod`** にオーバーレイを作成してください。base を参照し、
   - **名前空間を `prod`** に設定、
   - **replicas を 2** に設定、
   - **イメージタグを `nginx:1.26`** に変更します。
2. `kubectl apply -k ~/work/kustomize/overlays/prod` で適用してください。

採点はオーバーレイの kustomization(ファイル)と、**クラスタに適用された結果**
(prod の hello-web、replicas 2、nginx:1.26、Ready)を確認します。

> 参考: [Kustomize によるオブジェクト管理](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

## 7. Q7 (5点) プローブ — 自己修復とトラフィックゲーティング

名前空間 `dev` に Pod `probe-pod`(イメージ `nginx:1.26`)を作成し、2 つのプローブを設定してください。

- **readinessProbe** — `httpGet` path `/` port `80`、`initialDelaySeconds: 3`、`periodSeconds: 5`
- **livenessProbe** — `httpGet` path `/` port `80`、`periodSeconds: 10`

採点は両プローブのフィールドと、Pod が **Ready** であることを確認します。

> 参考: [プローブの設定](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 8. Q8 (5点) 障害診断 — CrashLoopBackOff

名前空間 `broken` の Deployment `orders` が CrashLoopBackOff になっています。

1. ログから原因を突き止め、**失敗ログ(エラーメッセージを含む出力)を `~/answers/q8.txt` に保存**
   してください(`kubectl logs` の出力をリダイレクトすれば十分です)。
2. コンテナのコマンドを `sh -c "while true; do date; sleep 5; done"` に直し、
   **Deployment を Available** にしてください。

採点は答案ファイルに実際のエラー文字列が含まれていることと、Deployment が Available で
あることを確認します。

> 参考: [実行中の Pod のデバッグ](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

## 9. Q9 (5点) 廃止された API バージョンの修正

`~/work/legacy/stack.yaml` は古いクラスタ由来で、**削除済みの apiVersion** を使っているため
`kubectl apply` が失敗します。

1. **ファイルの apiVersion をこのクラスタが対応するものに修正** してください(kind・名前・スペックは
   そのままにします)。
2. 修正したファイルを適用し、名前空間 `batch` に Deployment `report-api` と CronJob `report-gen`
   を作成してください。

採点は両リソースの存在と、ファイルの apiVersion が正しいことを確認します。

> 参考: [非推奨 API の移行ガイド](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

## 10. Q10 (7点) ConfigMap と Secret の利用

名前空間 `dev` に:

1. ConfigMap `app-config` — キー `mode=production`、`timeout=30`。
2. Secret `db-cred` — キー `user=admin`、`pass=S3cret1`。
3. Pod `webapp` — イメージ `busybox:1.36`、コマンド `sh -c "sleep 86400"`。
   - 環境変数 **`APP_MODE`** を ConfigMap の `mode` キーから注入(`configMapKeyRef`)。
   - Secret 全体を読み取り専用ボリュームとして **`/etc/creds`** にマウント。

採点はリソースの値と、**Pod の中で** 実際に `APP_MODE=production` 変数と
`/etc/creds/user` ファイルの内容を確認します。

> 参考: [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 11. Q11 (6点) SecurityContext — 非 root・読み取り専用

名前空間 `dev` に Pod `secure-app` を作成してください。イメージ `busybox:1.36`、
コマンド `sh -c "sleep 86400"`、そして:

- `runAsUser: 1000`、`runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- capabilities — **すべて drop**(`drop: ["ALL"]`)
- emptyDir ボリュームを `/tmp` にマウント(読み取り専用ルート下の書き込み可能な領域)

採点はすべてのセキュリティフィールド、Pod が Running であること、そして **実際に
uid 1000 で動いているか**(`id -u`)を確認します。

> 参考: [Pod の SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 12. Q12 (6点) ServiceAccount とトークン自動マウント

名前空間 `dev` に:

1. ServiceAccount `app-sa` を作成してください。
2. Pod `sa-pod` — イメージ `busybox:1.36`、コマンド `sh -c "sleep 86400"`、
   **`serviceAccountName: app-sa`**、そして Pod スペックで
   **`automountServiceAccountToken: false`** を設定してトークンの自動マウントを無効化してください。

採点は SA、Pod の SA 割り当て、そして **Pod の中にトークンディレクトリが実際に存在しないこと**
を確認します。

> 参考: [Pod への ServiceAccount の設定](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

## 13. Q13 (6点) リソース要求・上限 — Quota の範囲内で

名前空間 `batch` には ResourceQuota `batch-quota`(requests.cpu 1、requests.memory 1Gi)が
設定されています。Deployment `worker` を作成してください。

- イメージ `busybox:1.36`、コマンド `sh -c "sleep 86400"`、replicas **2**
- コンテナの resources: requests **cpu 100m · memory 64Mi**、limits **cpu 200m · memory 128Mi**

採点は requests/limits の値と、**2 つのレプリカが実際に Ready であること** を確認します
(クォータのある名前空間では requests のない Pod は即座に拒否される — それを体験するための問題です)。

> 参考: [コンテナのリソース管理](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

## 14. Q14 (7点) Service — ClusterIP と NodePort

名前空間 `prod` には Deployment `frontend`(nginx:1.26)が用意されています。

1. ClusterIP Service **`frontend-svc`** — port 80 → targetPort 80、セレクター `app: frontend`。
2. NodePort Service **`frontend-np`** — port 80、**nodePort 30080**、同じセレクター。

採点は両サービスのタイプ・ポート・セレクター、エンドポイントが空でないこと、そして
**実際の通信**(クラスタ内からのサービス DNS、ノードの 30080 ポート)を確認します。

> 参考: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 15. Q15 (6点) Ingress リソースの作成

名前空間 `prod` に、ホスト **`shop.example.com`** 用の Ingress **`web-ing`** を作成してください。

- path **`/`**(Prefix)→ Service `frontend-svc` のポート 80
- path **`/shop`**(Prefix)→ Service `shop-svc` のポート 80

この環境には Ingress コントローラがないため **リソース定義のみを採点** します(実際のルーティングは
確認しません)。

> 参考: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 16. Q16 (7点) NetworkPolicy — 指定クライアントのみ許可

名前空間 `dev` には Pod `cache`(app=cache)と、検証用の Pod `client`(role=client)・
`intruder` が用意されています。

NetworkPolicy **`cache-guard`** を作成してください。

- 対象: ラベル **`app: cache`** の Pod
- ラベル **`role: client`** の Pod からの **TCP 80** の Ingress のみ許可(それ以外はすべて遮断)

採点はポリシーのスペックと **実際の通信** を確認します — client → cache は通り、
intruder → cache は遮断されなければなりません。

> 参考: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
