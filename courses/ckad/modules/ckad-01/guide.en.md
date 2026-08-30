# CKAD Practice Exam #1 (120 min · 16 tasks · 100 pts)

A mock exam modelled on the Linux Foundation **CKAD (Certified Kubernetes Application
Developer)** performance test. The tasks are weighted like the real exam's domains.

| Domain | Points | Tasks |
|---|---|---|
| Application Design and Build | 20 | Q1 Q2 Q3 |
| Application Deployment | 20 | Q4 Q5 Q6 |
| Application Observability and Maintenance | 15 | Q7 Q8 Q9 |
| Application Environment, Configuration and Security | 25 | Q10 Q11 Q12 Q13 |
| Services and Networking | 20 | Q14 Q15 Q16 |

**How it works**

- The time limit is **120 minutes**. The remaining time is shown at the top of the screen.
- Solve the tasks **in any order**. Starting with the ones you are confident about is real exam strategy.
- Like the real exam, **there is no feedback while you work**. When you are done, press
  **[Submit for grading]** once at the bottom: all 16 tasks are graded together (each task
  inspects the live cluster, so it takes 1–2 minutes).
- **There is partial credit.** Every task has several graded items and you earn the points for
  the items you got right. After grading, the total and per-task breakdown appear at the top,
  and **explanations for missed tasks** appear below.
- **The pass mark is 66 points.** Reach it and you get a congratulations message and the module
  badge (a perfect score is not required).
- After submitting you may keep fixing things and **resubmit** within the remaining time. Your
  best score is recorded.
- When a task names a namespace, the objects **must be created in that namespace**.

**Exam language**

The real CKAD is offered in **English, Japanese and Simplified Chinese** only (there is no
Korean version). This mock exam supports those three plus Korean — if you want to get used to
the sentences you will read at the test centre, switch the language selector to
**English / 日本語 / 简体中文** and take another pass.

**Environment**

A **single-node k3s v1.36** cluster running inside a pod, exclusively yours. `kubectl` (alias
`k`) and `KUBECONFIG` are already set up, `sudo` needs no password, and `jq` and `vi`/`nano`
are available. As in the exam you may consult the
[official Kubernetes docs](https://kubernetes.io/docs/) — finding a YAML example there and
adapting it is the canonical exam technique.

```bash
kubectl get nodes
kubectl get ns          # dev, prod, batch and broken are prepared
```

**Differences from the real exam** (unavoidable environment constraints)

- **No Helm task** (the environment has no helm binary). Kustomize is covered via `kubectl apply -k`.
- There is no Ingress controller, so **Q15 grades the resource spec only** (no routing check).
- Container image building (writing Dockerfiles, docker build) needs separate study.

> Time-saving habit: scaffold with `kubectl create ... --dry-run=client -o yaml > q.yaml`, then
> edit. `kubectl explain <resource>.<field>` is also instantly available.

## 1. Q1 (7 pts) Sidecar container — log streaming

In namespace `dev`, create a pod `logger`. Two containers share an **emptyDir volume `logs`**.

- Main container `app` — image `busybox:1.36`, command:
  `sh -c "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"`
  Mount the volume at `/var/log/app`.
- Sidecar container `streamer` — image `busybox:1.36`, command:
  `sh -c "tail -F /var/log/app/app.log"` with the volume mounted at the same path.

Grading looks at the pod shape (two containers, shared emptyDir) and at whether
**`kubectl logs logger -c streamer` really shows the `tick` lines**.

> Reference: [Sidecar containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

## 2. Q2 (7 pts) Job and CronJob

In namespace `batch`:

1. Job `pi` — image `busybox:1.36`, command `sh -c "echo 3.14159"`,
   **completions 3 · parallelism 2**, `restartPolicy: Never`. All three runs must succeed.
2. CronJob `cleanup` — image `busybox:1.36`, command `sh -c "echo cleaned"`,
   schedule **daily at 03:00** (`0 3 * * *`), **concurrencyPolicy Forbid**,
   **successfulJobsHistoryLimit 1**, `restartPolicy: Never`.

Grading looks at the Job spec, at whether **`status.succeeded` reached 3**, and at the
CronJob's schedule and policy fields.

> Reference: [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) ·
> [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-job/)

## 3. Q3 (6 pts) Prepare content with an init container

In namespace `dev`, create a pod `web-init`.

- Init container `setup` — image `busybox:1.36`, mounts an emptyDir volume `web` at `/work`
  and runs `sh -c "echo ready-to-serve > /work/index.html"`.
- Main container `web` — image `nginx:1.26`, mounts the same volume at `/usr/share/nginx/html`.

Grading looks at the init container setup and at whether an **HTTP request to the pod IP
returns `ready-to-serve`**.

> Reference: [Init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

## 4. Q4 (7 pts) Rolling update — zero-downtime strategy

Namespace `prod` has a Deployment `api` (nginx:1.25, replicas 2) prepared.

1. Set the update strategy to **maxSurge 1 · maxUnavailable 0** (the zero-downtime condition).
2. Roll the container image to **`nginx:1.26`**.
3. The update must complete: **both replicas Ready on the new version**.

Grading looks at the strategy fields, the new image, and rollout completion (revision
advanced, all pods Ready).

> Reference: [Deployment — updating](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 5. Q5 (6 pts) Canary deployment — 25% of traffic

Namespace `prod` has a Deployment `shop` (track=stable, replicas 4) and a Service `shop-svc`
(selector `app: shop`). Send **25% of traffic to a canary** of the new version.

1. Create Deployment `shop-canary` — image **`nginx:1.26`**, replicas **1**,
   pod labels **`app: shop` + `track: canary`** (so the service picks it up too).
2. Scale the existing `shop` down to replicas **3**, so the pods behind the service are
   **3 stable : 1 canary**.

Grading looks at the canary Deployment spec, at the service endpoints including the canary
pod, and at the 3:1 split.

> Reference: [Canary deployments](https://kubernetes.io/docs/concepts/workloads/management/#canary-deployments)

## 6. Q6 (7 pts) Kustomize overlay

`~/work/kustomize/base` holds the base of a Deployment `hello-web` (nginx:1.25, replicas 1).

1. Create an overlay in **`~/work/kustomize/overlays/prod`**. It refers to the base and
   - sets the **namespace to `prod`**,
   - sets **replicas to 2**,
   - changes the **image tag to `nginx:1.26`**.
2. Apply it with `kubectl apply -k ~/work/kustomize/overlays/prod`.

Grading looks at the overlay's kustomization (the files) and at the **result applied to the
cluster** (hello-web in prod, replicas 2, nginx:1.26, Ready).

> Reference: [Managing objects with Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

## 7. Q7 (5 pts) Probes — self-healing and traffic gating

In namespace `dev`, create a pod `probe-pod` (image `nginx:1.26`) with two probes.

- **readinessProbe** — `httpGet` path `/` port `80`, `initialDelaySeconds: 3`, `periodSeconds: 5`
- **livenessProbe** — `httpGet` path `/` port `80`, `periodSeconds: 10`

Grading looks at both probes' fields and at whether the pod is **Ready**.

> Reference: [Configure probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 8. Q8 (5 pts) Troubleshoot — CrashLoopBackOff

Deployment `orders` in namespace `broken` is in CrashLoopBackOff.

1. Find the cause in the logs and **save the failure log (the output holding the error
   message) to `~/answers/q8.txt`** (redirecting `kubectl logs` output is fine).
2. Fix the container command to `sh -c "while true; do date; sleep 5; done"` so the
   **Deployment becomes Available**.

Grading looks at whether the answer file holds the real error string and the Deployment is
Available.

> Reference: [Debug running pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

## 9. Q9 (5 pts) Fix removed API versions

`~/work/legacy/stack.yaml` comes from an old cluster and uses **removed apiVersions**, so
`kubectl apply` fails.

1. **Fix the file's apiVersions to ones this cluster supports** (keep the kinds, names and specs).
2. Apply the fixed file so namespace `batch` gets Deployment `report-api` and CronJob `report-gen`.

Grading looks at both resources existing and at the file's apiVersions being correct.

> Reference: [Deprecated API migration guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

## 10. Q10 (7 pts) Consume a ConfigMap and a Secret

In namespace `dev`:

1. ConfigMap `app-config` — keys `mode=production`, `timeout=30`.
2. Secret `db-cred` — keys `user=admin`, `pass=S3cret1`.
3. Pod `webapp` — image `busybox:1.36`, command `sh -c "sleep 86400"`.
   - Environment variable **`APP_MODE`** injected from the ConfigMap's `mode` key (`configMapKeyRef`).
   - The whole Secret mounted read-only as a volume at **`/etc/creds`**.

Grading looks at the resource values and — **inside the pod** — at the real
`APP_MODE=production` variable and the `/etc/creds/user` file content.

> Reference: [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 11. Q11 (6 pts) SecurityContext — non-root, read-only

In namespace `dev`, create a pod `secure-app`. Image `busybox:1.36`,
command `sh -c "sleep 86400"`, and:

- `runAsUser: 1000`, `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- capabilities — **drop them all** (`drop: ["ALL"]`)
- an emptyDir volume mounted at `/tmp` (writable space under a read-only root)

Grading looks at every security field, at the pod Running, and at whether it **really runs as
uid 1000** (`id -u`).

> Reference: [Pod SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 12. Q12 (6 pts) ServiceAccount and token automount

In namespace `dev`:

1. Create ServiceAccount `app-sa`.
2. Pod `sa-pod` — image `busybox:1.36`, command `sh -c "sleep 86400"`,
   **`serviceAccountName: app-sa`**, and turn token automounting off in the pod spec with
   **`automountServiceAccountToken: false`**.

Grading looks at the SA, the pod's SA assignment, and at the **token directory really being
absent inside the pod**.

> Reference: [Configure Service Accounts for pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

## 13. Q13 (6 pts) Requests and limits — inside a quota

Namespace `batch` carries a ResourceQuota `batch-quota` (requests.cpu 1, requests.memory 1Gi).
Create a Deployment `worker`.

- Image `busybox:1.36`, command `sh -c "sleep 86400"`, replicas **2**
- Container resources: requests **cpu 100m · memory 64Mi**, limits **cpu 200m · memory 128Mi**

Grading looks at the requests/limits values and at **both replicas really being Ready** (this
task exists to show that in a quota-carrying namespace, pods without requests are rejected
outright).

> Reference: [Managing container resources](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

## 14. Q14 (7 pts) Services — ClusterIP and NodePort

Namespace `prod` has a Deployment `frontend` (nginx:1.26) prepared.

1. ClusterIP Service **`frontend-svc`** — port 80 → targetPort 80, selector `app: frontend`.
2. NodePort Service **`frontend-np`** — port 80, **nodePort 30080**, same selector.

Grading looks at both services' type, ports and selector, at non-empty endpoints, and at
**real traffic** (service DNS from inside the cluster, port 30080 on the node).

> Reference: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 15. Q15 (6 pts) Author an Ingress resource

In namespace `prod`, author an Ingress **`web-ing`** for host **`shop.example.com`**:

- path **`/`** (Prefix) → Service `frontend-svc` port 80
- path **`/shop`** (Prefix) → Service `shop-svc` port 80

This environment has no Ingress controller, so **only the resource spec is graded** (no
routing check).

> Reference: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 16. Q16 (7 pts) NetworkPolicy — admit named clients only

Namespace `dev` has a pod `cache` (app=cache) plus verification pods `client` (role=client)
and `intruder` prepared.

Create a NetworkPolicy **`cache-guard`**.

- Target: pods labelled **`app: cache`**
- Allow only **TCP 80** ingress from pods labelled **`role: client`** (block everything else)

Grading looks at the policy spec and at **real traffic** — client → cache must work,
intruder → cache must be blocked.

> Reference: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
