# Deployments and Rollouts

A **Deployment** lets you declare the desired state of a set of Pods (replicas, image); the
controller converges to it and manages **zero-downtime rolling updates** and **rollbacks**
when the image changes.

This lab runs on **your own single-node k3s cluster** inside the pod. You can use `kubectl`
straight from the terminal (the `k` alias and completion are set up), and `KUBECONFIG` is
already exported.

Check the node:

```bash
kubectl get nodes          # one Ready node
```

- `kubectl get <resource>` — the basic listing command; prints resources as a table.
- `nodes` — the machines in the cluster. `STATUS` must be `Ready` for Pods to be scheduled there.

Check the current context:

```bash
kubectl config current-context
```

- `kubectl config` — subcommands for the kubeconfig file (which cluster and user kubectl talks to).
- `current-context` — prints the name of the context (cluster + user + namespace) kubectl is using now.

> Reference: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Create a Deployment (3 replicas)

Create a Deployment named `web` with 3 replicas of `nginx:1.25`.

Create the Deployment:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — creates the `web` Deployment imperatively, no YAML needed. Pods automatically get the label `app=web`.
- `--image=nginx:1.25` — container image of the Pod template (`name:tag`).
- `--replicas=3` — number of Pods to keep running (`spec.replicas`).

Wait for the rollout:

```bash
kubectl rollout status deploy/web            # wait until all Ready
```

- `kubectl rollout status` — waits until the rollout finishes (all new Pods Ready) and prints its progress.
- `deploy/web` — the `<kind>/<name>` form; `deploy` is short for `deployment`.

Check the Deployment:

```bash
kubectl get deploy web
```

- `READY` — ready/desired Pods, `UP-TO-DATE` — Pods built from the latest template, `AVAILABLE` — Pods able to serve traffic.

List the pods:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — label selector; only Pods labelled `app=web`.
- `-o wide` — adds extra columns such as Pod IP and the node it runs on.

Success when the `READY` column of `kubectl get deploy web` shows `3/3`. Check the ReplicaSet
it created with `kubectl get rs`.

## 2. Rolling update

Bump the image to `nginx:1.26`. The Deployment creates a new ReplicaSet and swaps Pods a few
at a time (defaults `maxUnavailable=25%`, `maxSurge=25%`) with no downtime.

Update the image:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # replace image in all containers
```

- `kubectl set image deploy/web <container>=<image>` — changes only the image in the Pod template; a changed template starts a new rollout.
- `'*=nginx:1.26'` — `*` means every container. Single quotes stop the shell from expanding `*` into file names.

Wait for the rollout:

```bash
kubectl rollout status deploy/web             # wait for the rollout
```

Check the events:

```bash
kubectl describe deploy web | grep -A2 Events # watch the swap via events
```

- `kubectl describe` — human-readable details of a resource, including recent events.
- `| grep -A2 Events` — keep the `Events` line and the 2 lines After it; you can see the old/new ReplicaSets being scaled.

Check the ReplicaSets:

```bash
kubectl get rs                                # old/new ReplicaSets coexist → new has 3
```

- `rs` — short for ReplicaSet. Each template change makes a new ReplicaSet; the old one is scaled to 0 and kept for rollbacks.

Done when `kubectl rollout status` prints `successfully rolled out`.

> Reference: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. Rollback

Pretend that release was bad and **roll back to the previous revision.** The Deployment keeps
a revision history, so rollback is instant.

List revisions:

```bash
kubectl rollout history deploy/web           # list revisions
```

- `kubectl rollout history` — lists the revisions (template changes) the Deployment keeps.
- Add `--revision=<N>` to see what a specific revision contained.

Roll back to the previous revision:

```bash
kubectl rollout undo deploy/web              # roll back to previous (nginx:1.25)
```

- `kubectl rollout undo` — starts a new rollout back to the previous revision's Pod template. The rollback itself is recorded as a new revision.

Wait for the rollout:

```bash
kubectl rollout status deploy/web
```

Check the current image:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — prints only the fields selected by a JSONPath expression; `{.spec.template.spec.containers[0].image}` is the first container's image.
- `; echo` — jsonpath output has no trailing newline, so this keeps the prompt on its own line.

Success when the image is back to `nginx:1.25` and one more revision has been recorded. To go
to a specific revision use `kubectl rollout undo deploy/web --to-revision=<N>`.

> Reference: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
