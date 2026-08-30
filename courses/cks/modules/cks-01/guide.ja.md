# CKS 模擬試験 1回目 (120分 · 16問 · 100点)

Linux Foundation **CKS(Certified Kubernetes Security Specialist)** の実技試験形式をそのまま移した
模擬試験です。問題は本番と同じドメイン配点で配分しています。

| ドメイン | 配点 | 問題 |
|---|---|---|
| クラスタセットアップ | 15 | Q1 Q2 Q3 |
| クラスタハードニング | 15 | Q4 Q5 Q6 |
| システムハードニング | 10 | Q7 Q8 |
| マイクロサービスの脆弱性最小化 | 20 | Q9 Q10 Q11 |
| サプライチェーンセキュリティ | 20 | Q12 Q13 Q14 |
| モニタリング・ロギング・ランタイムセキュリティ | 20 | Q15 Q16 |

**進め方**

- 制限時間は **120分**。残り時間は画面上部に表示されます。
- 問題は **順不同** で解いて構いません。得意なものから片付けるのが本番の戦略です。
- 本番と同じく **解いている間は採点結果が出ません**。解き終えたら下の
  **[提出して採点]** を一度押すと 16 問が一括で採点されます(問題ごとに実クラスタを確認するため
  1〜2 分かかります)。
- **部分点があります。** 問題ごとに採点項目が複数あり、満たした項目の分だけ点が入ります。
  採点が終わると画面上部に合計点と問題別の点数・採点項目が表示され、
  **下部に間違えた問題の解説** が付きます。
- **合格ラインは 67 点** です(本番の CKS と同じ)。超えればお祝いメッセージと修了バッジがもらえます。
- 提出後も残り時間内で修正して **再採点** できます。最高点が記録されます。
- 問題が名前空間を指定している場合は **必ずその名前空間に** 作成してください。
- 答案ファイルを要求する問題は **正確に指定されたパス**(`~/answers/…`)に書かないと採点されません。

**環境**

Pod の中で動く **シングルノード k3s v1.36** クラスタで、あなた専用です。`kubectl`(別名 `k`)と
`KUBECONFIG` は設定済みで、`sudo` はパスワード不要です。`jq`、`openssl`、`sha512sum`、
`vi`/`nano` が使えます。本番と同様に [Kubernetes 公式ドキュメント](https://kubernetes.io/docs/) を
参照して構いません。

```bash
kubectl get nodes
kubectl get ns    # prod, apps, sys-hard, restricted-ns, supply, runtime が用意されています
ls ~/work         # 問題が参照するファイル群
```

**本番と異なる点** (環境上の制約でやむを得ない部分)

- **AppArmor, Falco, gVisor(RuntimeClass)** の問題は入れていません。Pod の中のクラスタでは
  ホストカーネル機能を保証できないためです。この領域は別途学習してください。
- **trivy バイナリがありません。** Q13 はあらかじめ用意したスキャンレポート(`~/work/scans/`)を
  読んで判断します(本番では `trivy image <イメージ>` を直接実行します)。
- Ingress コントローラがないため **Q2 はリソースの記述までを採点** します(実際の TLS 終端は確認しません)。
- ImagePolicyWebhook / OPA Gatekeeper は構成要素の持ち込みの都合で除外しました。

> 時間節約のコツ: `kubectl create ... --dry-run=client -o yaml > q.yaml` で雛形を作り、
> 既存リソースは `kubectl get ... -o yaml > q.yaml` で取得して直してから apply してください。
> `kubectl explain pod.spec.securityContext` もすぐ使えます。

## 1. Q1 (7点) NetworkPolicy — 既定拒否と選別許可

名前空間 `prod` には `backend`(nginx, `app=backend`)と発信用の `frontend`(`app=frontend`)、
`other`(`app=other`)の Pod が動いています。既定で拒否したうえで、指定した経路だけ許可してください。

1. `deny-all` — `prod` の **すべての Pod** に対して **Ingress を全面拒否**
   (`podSelector: {}`, `policyTypes: ["Ingress"]`)
2. `allow-frontend` — `app=backend` の Pod に対して、**`app=frontend` の Pod からの TCP 80** のみ許可

採点は実際の通信で行います — `frontend` は `backend` に到達でき、`other` は遮断されなければなりません。

```bash
kubectl exec -n prod frontend -- wget -T3 -qO- http://<backend パドの IP>/
kubectl exec -n prod other    -- wget -T3 -qO- http://<backend パドの IP>/   # 遮断されるのが正解
```

> 参考: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 2. Q2 (4点) TLS Secret と TLS Ingress

名前空間 `prod` のウェブサービスに TLS を被せてください。

1. `openssl` で **自己署名証明書** を作成してください — CN は `web.snacklab.local`
2. その証明書・鍵から **TLS タイプの Secret** `web-cert` を `prod` に作成してください
3. Ingress `web-tls`(`prod`) — host `web.snacklab.local`、path `/`(Prefix)、
   バックエンド `web-svc:80`、**`tls` セクションで `web-cert` を参照**

この環境には Ingress コントローラがないため **リソース定義のみを採点** します。

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
```

> 参考: [Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) ·
> [TLS Secret](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## 3. Q3 (4点) プラットフォームバイナリの完全性検証

`~/work/binaries/` にリリースバイナリ 3 つ(`kube-apiserver`, `kubelet`, `kube-proxy`)と、
配布元が公開したチェックサムファイル `checksums.txt` があります。

1. **SHA-512 チェックサムを照合** して改竄されたバイナリを見つけてください。
2. 改竄されたバイナリの **ファイル名 1 行** を `~/answers/q3.txt` に書いてください。例: `kube-proxy`

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
```

> 参考: [リリースバイナリの検証](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/)

## 4. Q4 (6点) RBAC を最小権限まで絞る

名前空間 `apps` の ServiceAccount `ci-bot` は CI パイプライン用ですが、いまは
RoleBinding `ci-bot-rb` が ClusterRole `admin` を丸ごと付与していて **権限が過剰** です。

`ci-bot` がちょうど次だけできるように直してください。

- `pods` — `get`, `list`
- `deployments`(apps グループ) — `get`, `list`, `update`

Role 名は `ci-role`、バインディング名は `ci-bot-rb` を **そのまま維持** してください(作り直しは自由)。
Secret の参照や Pod の削除がまだできると減点です。

```bash
kubectl auth can-i list secrets -n apps --as=system:serviceaccount:apps:ci-bot   # no でなければなりません
```

> 参考: [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 5. Q5 (5点) ServiceAccount トークンの自動マウント遮断

名前空間 `apps` の Deployment `web` は API を使う必要がないのに **既定 SA トークンが
コンテナにマウント** されています — 侵害されると API アクセスの通り道になります。

1. ServiceAccount `web-sa` を `apps` に作成し、**`automountServiceAccountToken: false`** を設定
2. Deployment `web` が `web-sa` を使うように修正
3. 新しい Pod の中に `/var/run/secrets/kubernetes.io/serviceaccount` が **マウントされていない** こと

```bash
kubectl exec -n apps deploy/web -- ls /var/run/secrets/kubernetes.io/serviceaccount  # 失敗するのが正解
```

> 参考: [SA トークンの自動マウント](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting)

## 6. Q6 (4点) 危険な ClusterRoleBinding の削除

誰かがデバッグと称して **認証済みの全ユーザー(`system:authenticated`)に `cluster-admin`** を
付与する ClusterRoleBinding を残していきました。

1. その ClusterRoleBinding を見つけて **名前 1 行** を `~/answers/q6.txt` に書いてください。
2. そのバインディングを **削除** してください。既定の `cluster-admin` バインディング(対象 `system:masters`)は触ってはいけません。

```bash
kubectl get clusterrolebindings -o wide | grep cluster-admin
```

> 参考: [RBAC のベストプラクティス](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)

## 7. Q7 (5点) seccomp RuntimeDefault の適用

名前空間 `sys-hard` の Deployment `runner` は seccomp なしで動いています。
**Pod のセキュリティコンテキスト** に `seccompProfile: { type: RuntimeDefault }` を適用し、
Pod 2 つがすべて Ready になるようにしてください。

> 参考: [seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)

## 8. Q8 (5点) ホストアクセスの除去 — privileged・hostPID・hostPath

名前空間 `sys-hard` の Deployment `node-tool` はノードを丸ごと掌握しています:
`privileged: true`, `hostPID: true`, `hostNetwork: true`, hostPath `/` のマウント。

**4 種類のホストアクセスをすべて除去** し、名前・名前空間・イメージを維持したまま
Pod が引き続き Running であるようにしてください。

> 参考: [Pod セキュリティコンテキスト](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 9. Q9 (7点) SecurityContext でコンテナを強化

名前空間 `apps` に Deployment `secure-app` を作成してください。

- イメージ `busybox:1.36`、動き続けるコマンド(例: `sleep 86400`)、レプリカ 1
- コンテナのセキュリティコンテキスト:

| 項目 | 値 |
|---|---|
| `runAsNonRoot` | `true` |
| `runAsUser` | `10001` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |
| `readOnlyRootFilesystem` | `true` |

Pod が Ready になっていれば合格です。

> 参考: [SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 10. Q10 (7点) Pod Security Admission — restricted の適用

名前空間 `restricted-ns` には `privileged` で動く Deployment `legacy` があります。

1. 名前空間に **`restricted` プロファイルを enforce** ラベルで掛けてください
   (`pod-security.kubernetes.io/enforce=restricted`)
2. Deployment `legacy` を **restricted 基準に合わせて修正** し、新しい Pod が正常に起動するようにしてください
   (privileged 除去、`runAsNonRoot`、`allowPrivilegeEscalation: false`、
   `capabilities.drop: ["ALL"]`、`seccompProfile: RuntimeDefault` — busybox は
   `runAsUser` も指定しないと起動しません)

ラベルを掛けるだけでは **既存の Pod は残ります** — Deployment を直してロールアウトされて初めて新しい Pod が審査を通過します。

> 参考: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) ·
> [名前空間ラベルによる PSA の適用](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

## 11. Q11 (6点) Secret の扱い — 抽出・作成・マウント

名前空間 `apps` の Secret `db-creds` を扱います。

1. `db-creds` の **`password` 値をデコード** して `~/answers/q11.txt` に 1 行で書いてください。
2. 新しい Secret `api-token` を `apps` に作成してください — キー `token`、値 `cks-2026`
3. Pod `secret-user`(`apps`, `busybox:1.36`, 動き続ける) — `db-creds` を
   **読み取り専用ボリューム** として `/etc/creds` にマウントし Running

> 参考: [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 12. Q12 (7点) Dockerfile のセキュリティ欠陥の修正

`~/work/audit/Dockerfile` はセキュリティ欠陥を抱えたままレビューに上がってきました。**ファイルを直接直してください。**

1. ベースイメージが `latest` です — **`nginx:1.26`** に固定してください。
2. クレデンシャル(`ENV API_KEY=…`)がイメージに埋め込まれています — **その行を削除** してください。
3. `USER root` で終わっています — **`nginx` ユーザー** で実行されるように変えてください。

残りの行(COPY・CMD など)は維持してください。採点はファイルの内容で行います。

> 参考: [Dockerfile のベストプラクティス](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)

## 13. Q13 (7点) 脆弱なイメージの特定と隔離

名前空間 `supply` に Deployment `frontend-app`, `report-app`, `batch-app` が動いています。
各イメージの脆弱性スキャンレポートが `~/work/scans/` に用意されています
(本番では `trivy image` を直接実行します)。

1. レポートを読んで **CRITICAL 脆弱性があるイメージ** を使う Deployment をすべて見つけてください。
2. その Deployment 名を `~/answers/q13.txt` に **1 行に 1 つずつ** 書いてください。
3. 該当する Deployment を **replicas 0 にスケール** して隔離してください。
   脆弱性のないワークロードは触ってはいけません。

> 参考: [サプライチェーンセキュリティの概要](https://kubernetes.io/docs/concepts/security/supply-chain-security/)

## 14. Q14 (6点) イメージダイジェストの固定

タグは再プッシュですり替えられ得ます。名前空間 `supply` の Deployment `pinned` が
`nginx:1.26` を **タグではなくダイジェストで** 参照するように変えてください
(`nginx@sha256:<64桁>`)。Pod は引き続き Ready でなければなりません。

いま動いている Pod からダイジェストを取得できます:

```bash
kubectl get pod -n supply -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
```

> 参考: [イメージダイジェスト](https://kubernetes.io/docs/concepts/containers/images/#image-names)

## 15. Q15 (8点) API サーバーの監査ロギング(audit logging)の構成

API サーバーに監査ロギングを有効化してください。k3s は `/etc/rancher/k3s/config.yaml` の
`kube-apiserver-arg` で apiserver フラグを受け取ります。

1. 監査ポリシー `/var/lib/rancher/k3s/server/audit-policy.yaml` —
   **`secrets` リソースは `Metadata` レベル** で記録し、それ以外は記録しない(`None`)
2. apiserver 引数 — `audit-policy-file=<上記パス>`、
   `audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log`、
   `audit-log-maxage=7`、`audit-log-maxbackup=2`
3. ログディレクトリを作成し `sudo systemctl restart k3s` で反映してください。
   再起動後は **`kubectl get nodes` でクラスタが正常か必ず確認** してください —
   引数を誤ると apiserver が起動せず、他の問題まで採点が止まります。

採点は Secret を一度参照したあと、監査ログにその記録が残るかを見ます。

> 参考: [監査(Auditing)](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)

## 16. Q16 (12点) ランタイムフォレンジック — 侵害された Pod の割り出しと隔離

セキュリティチームが名前空間 `runtime` で **暗号通貨マイニングが疑われる通信** を検知しました。
ワークロードは `web`, `metrics`, `logshipper` の 3 つです。

1. 各 Pod の **実行中のプロセスを調査** し(`kubectl exec <pod> -- ps` または
   `crictl`)、侵害された Pod を見つけてください。マイニングプールのアドレスや `xmrig` のような痕跡が見えます。
2. 侵害された Pod を管理する **Deployment 名 1 行** を `~/answers/q16.txt` に書いてください。
3. その Deployment を **replicas 0 にスケール** して隔離してください。
   残り 2 つのワークロードは引き続き Running でなければなりません。

> 参考: [セキュリティチェックリスト](https://kubernetes.io/docs/concepts/security/security-checklist/)
