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

Confirm it exists:

```bash
kubectl get sa deployer
```

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

Inspect the RoleBinding:

```bash
kubectl describe rolebinding read-pods
```

## 3. Verify with auth can-i

Use `kubectl auth can-i ... --as=<subject>` to test the effective permissions. `deployer` should
be able to **list** pods (yes) but not **delete** them (no).

Set the subject variable:

```bash
SA=system:serviceaccount:default:deployer
```

Test listing pods:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

Test deleting pods:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

Test listing secrets:

```bash
kubectl auth can-i list   secrets --as=$SA  # no (not in the Role)
```

Success when `list pods`→yes and `delete pods`→no, confirming least privilege.

> Reference: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
