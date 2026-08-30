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

Check the current context:

```bash
kubectl config current-context
```

> Reference: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Create a Deployment (3 replicas)

Create a Deployment named `web` with 3 replicas of `nginx:1.25`.

Create the Deployment:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

Wait for the rollout:

```bash
kubectl rollout status deploy/web            # wait until all Ready
```

Check the Deployment:

```bash
kubectl get deploy web
```

List the pods:

```bash
kubectl get pods -l app=web -o wide
```

Success when the `READY` column of `kubectl get deploy web` shows `3/3`. Check the ReplicaSet
it created with `kubectl get rs`.

## 2. Rolling update

Bump the image to `nginx:1.26`. The Deployment creates a new ReplicaSet and swaps Pods a few
at a time (defaults `maxUnavailable=25%`, `maxSurge=25%`) with no downtime.

Update the image:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # replace image in all containers
```

Wait for the rollout:

```bash
kubectl rollout status deploy/web             # wait for the rollout
```

Check the events:

```bash
kubectl describe deploy web | grep -A2 Events # watch the swap via events
```

Check the ReplicaSets:

```bash
kubectl get rs                                # old/new ReplicaSets coexist → new has 3
```

Done when `kubectl rollout status` prints `successfully rolled out`.

> Reference: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. Rollback

Pretend that release was bad and **roll back to the previous revision.** The Deployment keeps
a revision history, so rollback is instant.

List revisions:

```bash
kubectl rollout history deploy/web           # list revisions
```

Roll back to the previous revision:

```bash
kubectl rollout undo deploy/web              # roll back to previous (nginx:1.25)
```

Wait for the rollout:

```bash
kubectl rollout status deploy/web
```

Check the current image:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

Success when the image is back to `nginx:1.25` and one more revision has been recorded. To go
to a specific revision use `kubectl rollout undo deploy/web --to-revision=<N>`.

> Reference: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
