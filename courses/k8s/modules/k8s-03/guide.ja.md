# ConfigMap と Secret

設定とコードは分けるのが原則です。**ConfigMap** は平文の設定を、**Secret** はパスワードやトークンのような
機密情報を(base64 でエンコードして)保持し、Pod に **環境変数** や **ボリュームのファイル** として注入します。

> 参考: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. ConfigMap の作成

キー `APP_MODE` と `APP_GREETING` を持つ ConfigMap `app-config` を作成します。

ConfigMap の作成:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — ConfigMap `app-config` を命令的に作る。行末の `\` は 1 つのコマンドを複数行に分けて書いたもの。
- `--from-literal=キー=値` — キーと値のペアを直接入れる。何度でも指定でき、空白を含む値はクォートで囲む。
- ファイルから作るときは `--from-file=<パス>`、env ファイルなら `--from-env-file=<パス>` を使う。

内容の確認:

```bash
kubectl get cm app-config -o yaml
```

- `cm` は `configmap` の省略形。`-o yaml` で保存されたオブジェクト(`data:` 以下のキーと値)をそのまま見る。

`kubectl describe cm app-config` で 2 つのキーが入ったことを確認しましょう。

## 2. Secret の作成

キー `DB_PASSWORD` を持つ **Opaque** Secret `app-secret` を作成します。`create secret generic`
は値を自動で base64 エンコードします。

Secret の作成:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — 任意のキーと値用の `Opaque` タイプの Secret を作る(ほかに `tls`、`docker-registry` タイプがある)。
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — 値は保存時に自動で base64 エンコードされる。シングルクォートはシェルによる特殊文字の解釈を防ぐ。

エンコードされた値の確認:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — Secret の `data` のうち 1 つのキーの値(base64 文字列)だけを取り出す。

デコードして確認:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — base64 をデコード(`-d`)して元の値を表示する。つまり Secret を読む権限さえあれば誰でも平文を見られる。

> 注意: Secret の data はエンコードされているだけで暗号化ではありません。本番では etcd の暗号化と RBAC で
> アクセスを制限します — [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. Pod で注入して利用

Pod `app` を作り、**ConfigMap を環境変数(envFrom)** として、**Secret をボリュームのファイル**
(`/etc/app-secret`)として注入します。

Pod の作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      envFrom:
        - configMapRef: { name: app-config }
      volumeMounts:
        - { name: secret-vol, mountPath: /etc/app-secret, readOnly: true }
  volumes:
    - name: secret-vol
      secret: { secretName: app-secret }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `envFrom.configMapRef` — ConfigMap の **すべてのキー** を同じ名前の環境変数として注入する(1 つのキーだけなら `env[].valueFrom.configMapKeyRef`)。
- `volumes[].secret` + `volumeMounts` — Secret の各キーを `/etc/app-secret/<キー>` ファイルとしてマウントする。

Ready になるまで待つ:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — Pod の `Ready` 条件が真になるまで待つ。
- `--timeout=60s` — その時間内にならなければ失敗で終わる。

環境変数の確認:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → 環境変数
```

- `kubectl exec app -- <コマンド>` — 実行中のコンテナ内でコマンドを実行する。`--` の後ろがコンテナで動くコマンド。
- `printenv A B` — 指定した環境変数の値だけを表示する。

Secret ファイルの確認:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → ファイル
```

- ボリュームとしてマウントした Secret は、すでにデコードされた平文ファイルとして見える。キー名がそのままファイル名になる。

環境変数に `APP_MODE`/`APP_GREETING` が見え、`/etc/app-secret/DB_PASSWORD` ファイルがあれば成功です。

> 参考: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
