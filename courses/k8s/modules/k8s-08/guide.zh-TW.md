# RBAC —— 最小權限存取控制

**RBAC(Role-Based Access Control)** 決定"誰(subject)能對什麼(resource)做什麼(verb)"。
**Role** 是名稱空間內的一組權限,**ClusterRole** 是叢集範圍的權限,**RoleBinding/ClusterRoleBinding**
把這些權限繫結到使用者、組或 **ServiceAccount** 上。核心原則是 **最小權限** — 只授予確實需要的。

> 參考: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. 建立 ServiceAccount

建立 **ServiceAccount** `deployer` — Pod(應用)向 API 伺服器認證時使用的身份。

建立 ServiceAccount:

```bash
kubectl create serviceaccount deployer
```

- `kubectl create serviceaccount <名稱>` — 在當前名稱空間(`default`)中建立 ServiceAccount。Pod 透過 `spec.serviceAccountName` 使用這個身份。
- 新建的 ServiceAccount 起初沒有任何權限 — 權限透過 RoleBinding 授予。

確認已建立:

```bash
kubectl get sa deployer
```

- `sa` 是 `serviceaccount` 的縮寫。

## 2. Role 與 RoleBinding

建立只允許 **讀取**(get/list/watch)`pods` 的 Role `pod-reader`,再用 RoleBinding
`read-pods` 把它繫結到 `deployer`。

建立 Role 和 RoleBinding:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `---` — 分隔符,用一次 apply 同時建立多個物件(Role、RoleBinding)。
- `rules[].apiGroups: [""]` — 核心 API 組(pods、services、secrets 等)。`resources` — 目標資源,`verbs` — 允許的操作。
- `subjects` — 獲得權限的主體(這裡是 ServiceAccount),`roleRef` — 要繫結的 Role。`roleRef` 建立後不能修改。

檢視 RoleBinding:

```bash
kubectl describe rolebinding read-pods
```

- 一眼看出哪個 Role(`Role:`)繫結到了哪些主體(`Subjects:`)。

## 3. 用 auth can-i 驗證

用 `kubectl auth can-i ... --as=<主體>` 測試實際權限。deployer 應該 **能 list** pods(yes),
**不能 delete**(no)。

設定主體變數:

```bash
SA=system:serviceaccount:default:deployer
```

- ServiceAccount 的使用者名稱格式為 `system:serviceaccount:<名稱空間>:<名稱>`。把這個長名稱存進 shell 變數 `SA`。

測試 pods 的 list 權限:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <動詞> <資源>` — 以 `yes`/`no` 回答該請求是否被允許。
- `--as=$SA` — 不用管理員權限,而是模擬(impersonate)指定主體來檢查。

測試 pods 的 delete 權限:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` 不在 Role 的 `verbs` 中,所以應為 `no`。

測試 secrets 的 list 權限:

```bash
kubectl auth can-i list   secrets --as=$SA  # no(不在 Role 中)
```

- Role 只涉及 `pods`,所以其他資源(`secrets`)無論什麼動詞都是 `no`。完整權限列表可用 `kubectl auth can-i --list --as=$SA` 檢視。

`list pods`→yes、`delete pods`→no,說明最小權限已正確生效。

> 參考: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
