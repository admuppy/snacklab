# RBAC —— 最小权限访问控制

**RBAC(Role-Based Access Control)** 决定"谁(subject)能对什么(resource)做什么(verb)"。
**Role** 是命名空间内的一组权限,**ClusterRole** 是集群范围的权限,**RoleBinding/ClusterRoleBinding**
把这些权限绑定到用户、组或 **ServiceAccount** 上。核心原则是 **最小权限** — 只授予确实需要的。

> 参考: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. 创建 ServiceAccount

创建 **ServiceAccount** `deployer` — Pod(应用)向 API 服务器认证时使用的身份。

创建 ServiceAccount:

```bash
kubectl create serviceaccount deployer
```

- `kubectl create serviceaccount <名称>` — 在当前命名空间(`default`)中创建 ServiceAccount。Pod 通过 `spec.serviceAccountName` 使用这个身份。
- 新建的 ServiceAccount 起初没有任何权限 — 权限通过 RoleBinding 授予。

确认已创建:

```bash
kubectl get sa deployer
```

- `sa` 是 `serviceaccount` 的缩写。

## 2. Role 与 RoleBinding

创建只允许 **读取**(get/list/watch)`pods` 的 Role `pod-reader`,再用 RoleBinding
`read-pods` 把它绑定到 `deployer`。

创建 Role 和 RoleBinding:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `---` — 分隔符,用一次 apply 同时创建多个对象(Role、RoleBinding)。
- `rules[].apiGroups: [""]` — 核心 API 组(pods、services、secrets 等)。`resources` — 目标资源,`verbs` — 允许的操作。
- `subjects` — 获得权限的主体(这里是 ServiceAccount),`roleRef` — 要绑定的 Role。`roleRef` 创建后不能修改。

查看 RoleBinding:

```bash
kubectl describe rolebinding read-pods
```

- 一眼看出哪个 Role(`Role:`)绑定到了哪些主体(`Subjects:`)。

## 3. 用 auth can-i 验证

用 `kubectl auth can-i ... --as=<主体>` 测试实际权限。deployer 应该 **能 list** pods(yes),
**不能 delete**(no)。

设置主体变量:

```bash
SA=system:serviceaccount:default:deployer
```

- ServiceAccount 的用户名格式为 `system:serviceaccount:<命名空间>:<名称>`。把这个长名称存进 shell 变量 `SA`。

测试 pods 的 list 权限:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <动词> <资源>` — 以 `yes`/`no` 回答该请求是否被允许。
- `--as=$SA` — 不用管理员权限,而是模拟(impersonate)指定主体来检查。

测试 pods 的 delete 权限:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` 不在 Role 的 `verbs` 中,所以应为 `no`。

测试 secrets 的 list 权限:

```bash
kubectl auth can-i list   secrets --as=$SA  # no(不在 Role 中)
```

- Role 只涉及 `pods`,所以其他资源(`secrets`)无论什么动词都是 `no`。完整权限列表可用 `kubectl auth can-i --list --as=$SA` 查看。

`list pods`→yes、`delete pods`→no,说明最小权限已正确生效。

> 参考: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
