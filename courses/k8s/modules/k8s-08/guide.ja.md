# RBAC — 最小権限のアクセス制御

**RBAC(Role-Based Access Control)** は「誰が(subject)何に(resource)どう(verb)できるか」を
決めます。**Role** はネームスペース内の権限のまとまり、**ClusterRole** はクラスター全体の権限で、
**RoleBinding/ClusterRoleBinding** がその権限をユーザー・グループ・**ServiceAccount** に結び付けます。
基本原則は **最小権限** — 必要なものだけを与えます。

> 参考: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. ServiceAccount の作成

Pod(アプリ)が API サーバーに認証するときに使う ID である **ServiceAccount** `deployer` を作成します。

ServiceAccount の作成:

```bash
kubectl create serviceaccount deployer
```

- `kubectl create serviceaccount <名前>` — 現在のネームスペース(`default`)に ServiceAccount を作る。Pod は `spec.serviceAccountName` でこの ID を使う。
- 新しい ServiceAccount は最初は何の権限も持たない — 権限は RoleBinding で付ける。

作成の確認:

```bash
kubectl get sa deployer
```

- `sa` は `serviceaccount` の省略形。

## 2. Role と RoleBinding

`pods` の **読み取りだけ**(get/list/watch)を許可する Role `pod-reader` を作り、RoleBinding
`read-pods` でそれを `deployer` に結び付けます。

Role と RoleBinding の作成:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: pod-reader, namespace: default }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: read-pods, namespace: default }
subjects:
  - { kind: ServiceAccount, name: deployer, namespace: default }
roleRef:
  { kind: Role, name: pod-reader, apiGroup: rbac.authorization.k8s.io }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 行までの YAML を標準入力で渡して適用する。`-f -` は「ファイルの代わりに stdin」、クォートした `'EOF'` は本文中の `$` をシェルが展開しないようにする。
- `---` — 1 回の apply で複数のオブジェクト(Role、RoleBinding)をまとめて作るための区切り。
- `rules[].apiGroups: [""]` — コア API グループ(pods、services、secrets など)。`resources` — 対象リソース、`verbs` — 許可する動作。
- `subjects` — 権限を受け取る主体(ここでは ServiceAccount)、`roleRef` — 結び付ける Role。`roleRef` は作成後に変更できない。

RoleBinding の確認:

```bash
kubectl describe rolebinding read-pods
```

- どの Role が(`Role:`)どの主体に(`Subjects:`)結び付いているかを一目で表示する。

## 3. auth can-i で検証

`kubectl auth can-i ... --as=<主体>` で実際の権限を試します。deployer は pods を **list でき**(yes)、
**delete はできない**(no)はずです。

主体の変数を設定:

```bash
SA=system:serviceaccount:default:deployer
```

- ServiceAccount のユーザー名は `system:serviceaccount:<ネームスペース>:<名前>` の形式。長い名前をシェル変数 `SA` に入れておく。

pods の list 権限を試す:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <動詞> <リソース>` — そのリクエストが許可されるかを `yes`/`no` で答える。
- `--as=$SA` — 管理者権限ではなく、指定した主体になりすまして(impersonate)検査する。

pods の delete 権限を試す:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` は Role の `verbs` にないので `no` になるはず。

secrets の list 権限を試す:

```bash
kubectl auth can-i list   secrets --as=$SA  # no(Role にない)
```

- Role は `pods` しか扱わないので、ほかのリソース(`secrets`)は動詞に関係なく `no`。権限の一覧全体は `kubectl auth can-i --list --as=$SA` で見られる。

`list pods`→yes、`delete pods`→no になれば最小権限が正しくかかっています。

> 参考: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
