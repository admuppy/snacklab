# RBAC — Least-Privilege Access Control

**RBAC (Role-Based Access Control)** decides "who (subject) can do what (verb) to which
resource". A **Role** is a bundle of permissions within a namespace, a **ClusterRole** is
cluster-wide, and a **RoleBinding/ClusterRoleBinding** attaches those permissions to a user,
group, or **ServiceAccount**. The guiding rule is **least privilege** — grant only what's needed.

> Reference: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. Create a ServiceAccount

Create a **ServiceAccount** `deployer` — the identity a Pod (app) uses to authenticate to the
API server.

Create the ServiceAccount:

```bash
kubectl create serviceaccount deployer
```

- `kubectl create serviceaccount <name>` — creates a ServiceAccount in the current namespace (`default`). Pods use it via `spec.serviceAccountName`.
- A new ServiceAccount has no permissions; they are granted with a RoleBinding.

Confirm it exists:

```bash
kubectl get sa deployer
```

- `sa` is short for `serviceaccount`.

## 2. Role and RoleBinding

Create a Role `pod-reader` that allows **read-only** access (get/list/watch) to `pods`, and a
RoleBinding `read-pods` that attaches it to `deployer`.

Create the Role and RoleBinding:

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

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `---` — separates several objects (Role, RoleBinding) created by one apply.
- `rules[].apiGroups: [""]` — the core API group (pods, services, secrets, …). `resources` — targets, `verbs` — allowed actions.
- `subjects` — who receives the permissions (a ServiceAccount here); `roleRef` — which Role. `roleRef` cannot be changed after creation.

Inspect the RoleBinding:

```bash
kubectl describe rolebinding read-pods
```

- Shows at a glance which Role (`Role:`) is bound to which subjects (`Subjects:`).

## 3. Verify with auth can-i

Use `kubectl auth can-i ... --as=<subject>` to test the effective permissions. `deployer` should
be able to **list** pods (yes) but not **delete** them (no).

Set the subject variable:

```bash
SA=system:serviceaccount:default:deployer
```

- A ServiceAccount's user name has the form `system:serviceaccount:<namespace>:<name>`; the shell variable `SA` saves typing it.

Test listing pods:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <verb> <resource>` — answers `yes`/`no` for whether that request is allowed.
- `--as=$SA` — checks while impersonating that subject instead of using your admin rights.

Test deleting pods:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` is not in the Role's `verbs`, so this must be `no`.

Test listing secrets:

```bash
kubectl auth can-i list   secrets --as=$SA  # no (not in the Role)
```

- The Role only covers `pods`, so any other resource (`secrets`) is `no` regardless of verb. See the whole list with `kubectl auth can-i --list --as=$SA`.

Success when `list pods`→yes and `delete pods`→no, confirming least privilege.

> Reference: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
