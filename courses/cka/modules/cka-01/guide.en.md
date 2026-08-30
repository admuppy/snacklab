# CKA Practice Exam #1 (120 min · 17 tasks · 100 pts)

A mock exam modelled on the Linux Foundation **CKA (Certified Kubernetes Administrator)**
performance test. Tasks are weighted like the real exam.

| Domain | Weight | Tasks |
|---|---|---|
| Cluster Architecture, Installation & Configuration | 25 | Q1 Q2 Q3 Q4 Q16 Q17 |
| Workloads & Scheduling | 15 | Q5 Q6 Q7 |
| Services & Networking | 20 | Q8 Q9 Q10 |
| Storage | 10 | Q11 Q12 |
| Troubleshooting | 30 | Q13 Q14 Q15 |

**How it works**

- Time limit **120 minutes**; the remaining time is shown at the top of the screen.
- Solve tasks **in any order** — starting with the ones you know is real exam strategy.
  The one exception: **Q9 needs the `web` pods from Q5** to be running, because it is graded
  with live traffic.
- As in the real exam, **there is no feedback while you work**. When you are done, press
  **[Submit and grade]** once and all 17 tasks are graded together (each task is verified against
  the live cluster, so it takes a minute or two).
- **Partial credit applies.** Every task has several grading criteria and you earn points for the
  ones you meet. After grading, the total and the per-task breakdown appear at the top of the pane,
  and **explanations for the tasks you missed** are appended at the bottom.
- **The pass mark is 66 points.** Reach it and you get a congratulations message and the module
  badge — a perfect score is not required.
- You may keep fixing things and **grade again** while time remains; your best score is kept.
- When a task names a namespace, the object **must** be created in that namespace.

**Exam languages**

The real CKA is offered in **English, Japanese and Simplified Chinese** only. This mock exam is
available in those three languages (plus Korean); use the language selector at the top if you
want to practise in the language you will actually sit the exam in.

**Environment**

A single-node **k3s v1.36** cluster running inside your pod — it is yours alone. `kubectl`
(aliased to `k`) and `KUBECONFIG` are already set up, and `sudo` needs no password. `jq`,
`vi` and `nano` are available. As in the real exam you may consult the
[Kubernetes documentation](https://kubernetes.io/docs/) — in fact, copying a YAML example from
the docs and editing it is the intended technique.

```bash
kubectl get nodes       # lab (control plane) + worker-1/worker-2 (virtual workers)
kubectl get ns          # app-prod, ops, broken and maint are prepared for you
```

**How this differs from the real exam** (environment limits)

- No **kubeadm cluster upgrade** task. This is k3s-based, so the kubeadm procedure cannot be
  reproduced; study that area separately.
- **Q16 grades the etcd restore up to the offline step** (`--data-dir` restore). The final
  cut-over of the running cluster is a k3s-specific procedure and is out of scope.
- **worker-1 and worker-2 are KWOK virtual workers.** Scheduling, eviction and drain behave
  exactly like the real thing, but pods on them do not run real processes (this does not
  affect Q17 grading).
- There is no Ingress controller, so **Q10 is graded on the resource definition only** — no
  actual routing is checked.

> Time saver: build a skeleton with `kubectl create ... --dry-run=client -o yaml > q.yaml` and
> edit it. `kubectl explain <resource>.<field>` is available offline too.

## 1. Q1 (5 pts) RBAC — ServiceAccount, Role, RoleBinding

In namespace `app-prod`, create a **read-only** identity for a deployment tool.

- ServiceAccount `deploy-bot`
- Role `pod-reader` — **only `get`, `list`, `watch`** on `pods` and `deployments` (apps group)
- RoleBinding `deploy-bot-rb` — bind that Role to `deploy-bot`

The permission must be scoped to `app-prod`. It is wrong if pods in other namespaces are
listable, or if the identity can create or delete pods.

```bash
kubectl auth can-i list pods -n app-prod --as=system:serviceaccount:app-prod:deploy-bot
```

> Reference: [RBAC authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 2. Q2 (4 pts) Approve a CSR and grant user access

A client certificate signing request for a new developer, `dev-user`, is **pending approval**.

```bash
kubectl get csr
```

1. **Approve** the CSR `dev-user` so a certificate is issued.
2. Grant the User `dev-user` **read-only** access to `app-prod` by creating a RoleBinding
   named `dev-user-view` in `app-prod` that uses the built-in ClusterRole `view`.

Binding `edit` or `admin` is wrong. Verify:

```bash
kubectl auth can-i list pods   -n app-prod --as=dev-user   # yes
kubectl auth can-i delete pods -n app-prod --as=dev-user   # no
```

> Reference: [Certificates and CSRs](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)

## 3. Q3 (4 pts) Create a static pod

Create a static pod managed **directly by the kubelet** — not through the API server.

- Name `ops-static`, namespace `default`
- Image `busybox:1.36`, with a command that keeps running (e.g. `sleep 86400`)

The manifest directory in this environment (k3s) is:

```bash
ls /var/lib/rancher/k3s/agent/pod-manifests/
```

A static pod shows up in the API server as a **mirror pod** whose name has the node name
appended (`ops-static-<node>`). Drop the file, wait a few seconds, then check `kubectl get pod`.

> Reference: [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

## 4. Q4 (3 pts) ResourceQuota and LimitRange

Constrain consumption in namespace `ops`.

ResourceQuota `ops-quota`:

| Item | Value |
|---|---|
| `pods` | 5 |
| `requests.cpu` | 1 |
| `requests.memory` | 1Gi |

LimitRange `ops-limits` (`type: Container`):

| Item | Value |
|---|---|
| `defaultRequest.cpu` | 100m |
| `defaultRequest.memory` | 128Mi |
| `default.cpu` | 200m |
| `default.memory` | 256Mi |

Remember that once a quota constrains `requests.*`, **every pod in that namespace must declare
requests** — the LimitRange defaults are what make that bearable.

> Reference: [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/) ·
> [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)

## 5. Q5 (6 pts) Deployment and rollout strategy

Create a Deployment `web` in namespace `app-prod`.

- **3** replicas, image `nginx:1.26`
- Container requests `cpu: 50m`, `memory: 64Mi`
- `RollingUpdate` strategy with **zero downtime**: `maxSurge: 1`, `maxUnavailable: 0`
- Pod label `app=web` (later tasks rely on it)

All three replicas must be Ready.

> Reference: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 6. Q6 (4 pts) Deploy a DaemonSet

Deploy a DaemonSet `node-agent` in namespace `ops`.

- Image `busybox:1.36` with a long-running command
- **Declare resource requests** (e.g. `cpu: 10m`, `memory: 16Mi`) — `ops` is quota-bound
- The pod must be Ready on every node

> Reference: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)

## 7. Q7 (5 pts) Sidecar container with a shared volume

Create a pod `logger` in namespace `app-prod` with **two** containers sharing one `emptyDir`
volume at **the same path, `/var/log/app`**.

- Container `app` — periodically appends something to `/var/log/app/app.log`
- Container `sidecar` — reads the same file (e.g. `tail -f`)

Grading reads that log file **from inside the sidecar**. Mounting the volume without writing
anything will not pass.

> Reference: [Logging architecture — sidecar](https://kubernetes.io/docs/concepts/cluster-administration/logging/#sidecar-container-with-logging-agent)

## 8. Q8 (7 pts) Services — ClusterIP and NodePort

Expose the `web` pods from Q5 in two ways, both in namespace `app-prod`.

| Name | Type | Ports |
|---|---|---|
| `web-svc` | ClusterIP | `80` → container `80` |
| `web-np` | NodePort | `80` → container `80`, nodePort **30080** |

Both Services must have **3** endpoints, and the DNS name
`web-svc.app-prod.svc.cluster.local` must actually answer from inside the cluster.

> Reference: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 9. Q9 (7 pts) Restrict traffic with a NetworkPolicy

Make namespace `app-prod` deny-by-default, then allow only a designated client.

1. `default-deny` — deny **all Ingress** to **every pod** in `app-prod`
   (`podSelector: {}`, `policyTypes: ["Ingress"]`)
2. `allow-client` — for `app=web` pods, allow **TCP 80** only from pods labelled
   **`role=client`**

The namespace already contains a `client` pod (`role=client`) and an `intruder` pod
(`role=outsider`). Grading uses real traffic: `client` must get through and `intruder` must not.

```bash
kubectl exec -n app-prod client   -- wget -T3 -qO- http://<web pod IP>/
kubectl exec -n app-prod intruder -- wget -T3 -qO- http://<web pod IP>/   # must fail
```

> Reference: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 10. Q10 (6 pts) Author an Ingress resource

Create an Ingress `web-ing` in namespace `app-prod`.

- host `shop.example.com`
- path `/` with `pathType: Prefix`
- backend Service `web-svc` on port `80`

There is no Ingress controller here, so **only the resource definition is graded** (no routing
check).

> Reference: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 11. Q11 (5 pts) Static PV/PVC binding

Attach a statically provisioned volume to a pod.

1. PersistentVolume `pv-data` — `1Gi`, `ReadWriteOnce`, `storageClassName: manual`,
   hostPath `/mnt/data`
2. PersistentVolumeClaim `pvc-data` (`app-prod`) — `1Gi`, `ReadWriteOnce`, using the same
   `storageClassName` so it **binds to `pv-data`**
3. Pod `data-user` (`app-prod`) — mounts that PVC at `/data` and is Running

If you leave `storageClassName` empty, the default StorageClass dynamically provisions a
different volume. The claim would be `Bound`, but not to `pv-data` — that is wrong.

> Reference: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## 12. Q12 (5 pts) Dynamic provisioning and writing data

Use the default StorageClass to provision a volume **dynamically**.

1. PVC `pvc-dyn` (`app-prod`) — `storageClassName: local-path`, `500Mi`, `ReadWriteOnce`
2. Pod `writer` (`app-prod`) — mounts it at `/data`, writes `cka` into `/data/hello.txt`,
   and keeps running

`local-path` is `WaitForFirstConsumer`, so **the PVC stays Pending until a pod consumes it**.
That is expected — create the pod.

```bash
kubectl get sc
```

> Reference: [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 13. Q13 (10 pts) Troubleshoot — a Deployment that never starts

The Deployment `api` in namespace `broken` **never becomes Ready.** Find the cause and fix it.
Keep the name, namespace, and replica count (**2**).

```bash
kubectl get pods -n broken
kubectl describe pod -n broken <pod>      # read the Events
```

Both pods must be Running and Ready, with no failed pods left behind.

> Reference: [Troubleshooting applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 14. Q14 (10 pts) Troubleshoot — a Service with no endpoints

The Service `cache-svc` in namespace `broken` returns nothing. The backing Deployment `cache`
is itself healthy.

```bash
kubectl get endpoints cache-svc -n broken
kubectl get pods -n broken --show-labels
kubectl describe svc cache-svc -n broken
```

**Two things are wrong.** Keeping the service `port` at `80`, fix it so the endpoints fill in
and real HTTP responses come back.

> Reference: [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

## 15. Q15 (10 pts) Troubleshoot — CrashLoopBackOff and report the cause

The Deployment `worker` in namespace `broken` keeps restarting with `CrashLoopBackOff`.

```bash
kubectl logs -n broken deploy/worker
kubectl describe pod -n broken <pod>
```

1. Remove the cause so the pod runs **stably** (the restart loop must stop).
2. Write the offending resource into `~/answers/q15.txt` as **one lower-case line in
   `<kind>/<name>` form**, e.g. `deployment/foo`.

The check requires the container to have been up for at least 20 seconds without restarting.
If you submit right after fixing it, this can still fall short — wait a moment before submitting.

> Reference: [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

## 16. Q16 (6 pts) etcd backup and offline restore

The cluster datastore is **embedded etcd**. Work with the connection details below
(the certificates are root-owned, so use `sudo`).

- Endpoint: `https://127.0.0.1:2379`
- CA: `/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt`
- Certificate: `/var/lib/rancher/k3s/server/tls/etcd/server-client.crt`
- Key: `/var/lib/rancher/k3s/server/tls/etcd/server-client.key`

1. Save a snapshot to **`~/backup/etcd-snap.db`** with `etcdctl`.
2. **Restore that snapshot offline** into the directory **`~/backup/restored`** with
   `etcdutl` (use `--data-dir`; the target directory must not exist beforehand).

**Caution**: cutting the running cluster over to the restored data is out of scope for
this exam. Running anything like `k3s server --cluster-reset` may wipe the resources of
your other answers.

> Reference: [Operating etcd clusters](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

## 17. Q17 (3 pts) Drain node worker-1 for maintenance

Worker node `worker-1` is about to go down for a kernel patch. Deployment `payments`
(4 replicas) in namespace `maint` runs across worker-1 and worker-2.

1. **Safely empty `worker-1`** — keep it unschedulable and ignore DaemonSets.
2. `payments` must remain **4/4 available** afterwards (it moves to worker-2).

```bash
kubectl get pods -n maint -o wide
```

> Reference: [Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
