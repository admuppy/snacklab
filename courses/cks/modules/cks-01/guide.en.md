# CKS Practice Exam #1 (120 min · 16 tasks · 100 pts)

A mock exam modelled on the Linux Foundation **CKS (Certified Kubernetes Security
Specialist)** performance test, with tasks weighted like the real exam domains.

| Domain | Points | Tasks |
|---|---|---|
| Cluster Setup | 15 | Q1 Q2 Q3 |
| Cluster Hardening | 15 | Q4 Q5 Q6 |
| System Hardening | 10 | Q7 Q8 |
| Minimize Microservice Vulnerabilities | 20 | Q9 Q10 Q11 |
| Supply Chain Security | 20 | Q12 Q13 Q14 |
| Monitoring, Logging & Runtime Security | 20 | Q15 Q16 |

**How it works**

- Time limit is **120 minutes**. The remaining time is shown at the top of the screen.
- Solve the tasks **in any order** — starting with what you know best is real exam strategy.
- As in the real exam, **there is no feedback while you solve**. When you are done, press
  **[Submit for grading]** once: all 16 tasks are graded together (each task inspects the
  live cluster, so it takes 1–2 minutes).
- **Partial credit applies.** Each task has several graded items and you earn the ones you got
  right. After grading, the total and per-task breakdown appear at the top, and
  **explanations for missed tasks** appear below.
- **The pass mark is 67 points** (same as the real CKS). Passing earns the module badge.
- You may keep fixing and **resubmit** within the remaining time. Your best score is kept.
- When a task names a namespace, the resource **must be created in that namespace**.
- When a task asks for an answer file, write it to **exactly the given path** (`~/answers/…`).

**Environment**

A **single-node k3s v1.36** cluster running inside a pod, dedicated to you. `kubectl`
(alias `k`) and `KUBECONFIG` are preconfigured, `sudo` needs no password, and `jq`,
`openssl`, `sha512sum`, `vi`/`nano` are available. As in the real exam, you may consult the
[official Kubernetes docs](https://kubernetes.io/docs/).

```bash
kubectl get nodes
kubectl get ns    # prod, apps, sys-hard, restricted-ns, supply, runtime are ready
ls ~/work         # files referenced by the tasks
```

**Differences from the real exam** (unavoidable in this environment)

- No **AppArmor, Falco, or gVisor (RuntimeClass)** tasks — a cluster inside a pod cannot
  guarantee host-kernel features. Study those areas separately.
- **No trivy binary.** Q13 uses pre-computed scan reports in `~/work/scans/`
  (in the real exam you run `trivy image <image>` yourself).
- There is no Ingress controller, so **Q2 grades the resources only** (no live TLS check).
- ImagePolicyWebhook / OPA Gatekeeper are excluded.

> Time-saving habit: scaffold with `kubectl create ... --dry-run=client -o yaml > q.yaml`,
> and edit existing resources via `kubectl get ... -o yaml > q.yaml`.
> `kubectl explain pod.spec.securityContext` is always at hand.

## 1. Q1 (7 pts) NetworkPolicy — default deny, selective allow

Namespace `prod` runs `backend` (nginx, `app=backend`) plus the client pods
`frontend` (`app=frontend`) and `other` (`app=other`). Lock it down, then allow one path.

1. `deny-all` — **block all Ingress** to **every pod** in `prod`
   (`podSelector: {}`, `policyTypes: ["Ingress"]`)
2. `allow-frontend` — for `app=backend` pods, allow **TCP 80 from `app=frontend` pods only**

Grading uses real traffic — `frontend` must reach `backend`, `other` must be blocked.

```bash
kubectl exec -n prod frontend -- wget -T3 -qO- http://<backend-pod-IP>/
kubectl exec -n prod other    -- wget -T3 -qO- http://<backend-pod-IP>/   # must fail
```

> Ref: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 2. Q2 (4 pts) TLS Secret and TLS Ingress

Put TLS in front of the web service in namespace `prod`.

1. Generate a **self-signed certificate** with `openssl` — CN `web.snacklab.local`
2. Create a **TLS-type Secret** `web-cert` in `prod` from that cert and key
3. Ingress `web-tls` (`prod`) — host `web.snacklab.local`, path `/` (Prefix),
   backend `web-svc:80`, and a **`tls` section referencing `web-cert`**

There is no Ingress controller here, so **only the resources are graded**.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
```

> Ref: [Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) ·
> [TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## 3. Q3 (4 pts) Verify platform binaries

`~/work/binaries/` holds three release binaries (`kube-apiserver`, `kubelet`,
`kube-proxy`) and the vendor-published checksum file `checksums.txt`.

1. **Verify the SHA-512 checksums** and find the tampered binary.
2. Write the **file name of the tampered binary** as a single line to `~/answers/q3.txt`.
   Example: `kube-proxy`

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
```

> Ref: [Verify release artifacts](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/)

## 4. Q4 (6 pts) Tighten RBAC to least privilege

ServiceAccount `ci-bot` in namespace `apps` belongs to a CI pipeline, but RoleBinding
`ci-bot-rb` currently hands it the whole ClusterRole `admin` — **far too much**.

Restrict `ci-bot` to exactly:

- `pods` — `get`, `list`
- `deployments` (apps group) — `get`, `list`, `update`

Name the Role `ci-role` and **keep the binding name `ci-bot-rb`** (recreating it is fine).
If it can still read Secrets or delete pods, you lose points.

```bash
kubectl auth can-i list secrets -n apps --as=system:serviceaccount:apps:ci-bot   # must be no
```

> Ref: [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 5. Q5 (5 pts) Stop ServiceAccount token automount

Deployment `web` in namespace `apps` never talks to the API, yet the **default SA token is
mounted into the container** — an API access path if the pod is compromised.

1. Create ServiceAccount `web-sa` in `apps` with **`automountServiceAccountToken: false`**
2. Point Deployment `web` at `web-sa`
3. New pods must have **no mount** at `/var/run/secrets/kubernetes.io/serviceaccount`

```bash
kubectl exec -n apps deploy/web -- ls /var/run/secrets/kubernetes.io/serviceaccount  # must fail
```

> Ref: [Opt out of token automounting](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting)

## 6. Q6 (4 pts) Remove a dangerous ClusterRoleBinding

Someone left a ClusterRoleBinding that grants **`cluster-admin` to every authenticated
user (`system:authenticated`)** "for debugging".

1. Find it and write its **name** as a single line to `~/answers/q6.txt`.
2. **Delete** the binding. Do not touch the default `cluster-admin` binding
   (subject `system:masters`).

```bash
kubectl get clusterrolebindings -o wide | grep cluster-admin
```

> Ref: [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)

## 7. Q7 (5 pts) Apply the RuntimeDefault seccomp profile

Deployment `runner` in namespace `sys-hard` runs without seccomp. Add
`seccompProfile: { type: RuntimeDefault }` to the **pod security context** and make sure
both pods are Ready again.

> Ref: [seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)

## 8. Q8 (5 pts) Remove host access — privileged, hostPID, hostPath

Deployment `node-tool` in namespace `sys-hard` owns the node outright:
`privileged: true`, `hostPID: true`, `hostNetwork: true`, and a hostPath mount of `/`.

**Remove all four kinds of host access**, keeping the name, namespace and image, with the
pod still Running.

> Ref: [Pod security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 9. Q9 (7 pts) Harden a container with SecurityContext

Create Deployment `secure-app` in namespace `apps`.

- Image `busybox:1.36`, a long-running command (e.g. `sleep 86400`), 1 replica
- Container security context:

| Setting | Value |
|---|---|
| `runAsNonRoot` | `true` |
| `runAsUser` | `10001` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |
| `readOnlyRootFilesystem` | `true` |

The pod must be Ready to pass.

> Ref: [SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 10. Q10 (7 pts) Pod Security Admission — enforce restricted

Namespace `restricted-ns` runs Deployment `legacy` as `privileged`.

1. Label the namespace to **enforce the `restricted` profile**
   (`pod-security.kubernetes.io/enforce=restricted`)
2. **Fix Deployment `legacy` to satisfy restricted** so its new pods start:
   drop privileged, set `runAsNonRoot`, `allowPrivilegeEscalation: false`,
   `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault` — with busybox you
   also need a `runAsUser`.

The label alone **leaves old pods running** — the Deployment must roll out compliant pods.

> Ref: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) ·
> [Enforce standards with namespace labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

## 11. Q11 (6 pts) Working with Secrets — extract, create, mount

All in namespace `apps`, around Secret `db-creds`.

1. **Decode the `password` value** of `db-creds` and write it as one line to
   `~/answers/q11.txt`.
2. Create a new Secret `api-token` in `apps` — key `token`, value `cks-2026`
3. Pod `secret-user` (`apps`, `busybox:1.36`, long-running) — mount `db-creds` as a
   **read-only volume** at `/etc/creds`, Running

> Ref: [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 12. Q12 (7 pts) Fix security defects in a Dockerfile

`~/work/audit/Dockerfile` arrived for review with security defects. **Fix the file in place.**

1. The base image is `latest` — **pin it to `nginx:1.26`**.
2. A credential is baked in (`ENV API_KEY=…`) — **remove that line**.
3. It ends as `USER root` — make it run as the **`nginx` user** instead.

Keep the remaining lines (COPY, CMD, …). Grading reads the file.

> Ref: [Dockerfile best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)

## 13. Q13 (7 pts) Identify and quarantine vulnerable images

Namespace `supply` runs Deployments `frontend-app`, `report-app` and `batch-app`.
Vulnerability scan reports for their images are prepared in `~/work/scans/`
(in the real exam you would run `trivy image` yourself).

1. Read the reports and find every Deployment whose image has **CRITICAL** vulnerabilities.
2. Write those Deployment names to `~/answers/q13.txt`, **one per line**.
3. **Scale those Deployments to 0 replicas** to quarantine them.
   Leave the clean workload untouched.

> Ref: [Supply chain security](https://kubernetes.io/docs/concepts/security/supply-chain-security/)

## 14. Q14 (6 pts) Pin an image by digest

Tags can be silently re-pushed. Change Deployment `pinned` in namespace `supply` to
reference `nginx:1.26` **by digest instead of by tag** (`nginx@sha256:<64 hex>`).
Pods must stay Ready.

You can read the digest off the running pod:

```bash
kubectl get pod -n supply -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
```

> Ref: [Image digests](https://kubernetes.io/docs/concepts/containers/images/#image-names)

## 15. Q15 (8 pts) Configure API server audit logging

Enable audit logging on the API server. k3s passes apiserver flags via
`kube-apiserver-arg` in `/etc/rancher/k3s/config.yaml`.

1. Audit policy `/var/lib/rancher/k3s/server/audit-policy.yaml` — log **`secrets` at
   `Metadata` level**, and nothing else (`None`).
2. apiserver args — `audit-policy-file=<path above>`,
   `audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log`,
   `audit-log-maxage=7`, `audit-log-maxbackup=2`
3. Create the log directory and apply with `sudo systemctl restart k3s`.
   After the restart, **verify the cluster with `kubectl get nodes`** — a bad flag keeps
   the apiserver down and blocks grading of every other task.

Grading reads a Secret once and then expects a matching entry in the audit log.

> Ref: [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)

## 16. Q16 (12 pts) Runtime forensics — find and quarantine a compromised pod

The security team detected **suspected crypto-mining traffic** from namespace `runtime`.
Its workloads are `web`, `metrics` and `logshipper`.

1. **Inspect the running processes** of each pod (`kubectl exec <pod> -- ps` or
   `crictl`) and find the compromised one. Look for a mining-pool address or `xmrig`.
2. Write the **name of the Deployment** managing the compromised pod as one line to
   `~/answers/q16.txt`.
3. **Scale that Deployment to 0 replicas** to quarantine it.
   The other two workloads must stay Running.

> Ref: [Security checklist](https://kubernetes.io/docs/concepts/security/security-checklist/)
