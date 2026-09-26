# Capstone — Reviving a Broken Deployment

Two e-commerce apps (`shop`, `cart`) are deployed but **nothing is running.** Three different
failures are planted. This capstone isn't about new concepts — it's practice at using the
diagnostic tools you've learned (`kubectl get`, `describe`, `logs`, `get events`) to **find and
fix the root causes yourself.**

Start with a survey:

Survey all resources:

```bash
kubectl get deploy,pods,svc
```

- Comma-separated kinds are listed in one go. Scan Deployment `READY`, Pod `STATUS` and the Services to spot what's wrong.

Check recent events:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — things that happened in the namespace (scheduling, image pulls, failures, …).
- `--sort-by=.lastTimestamp` — sort by last occurrence; `| tail -20` — only the 20 most recent lines.

> Reference: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. Fix the image pull failure

The `shop` Pods are in `ImagePullBackOff`/`ErrImagePull`. Find out why.

Check shop Pod status:

```bash
kubectl get pods -l app=shop
```

- `ImagePullBackOff`/`ErrImagePull` in `STATUS` — the node can't pull the image and is backing off between retries.

Find the cause in events:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # a "not found" tag shows up
```

- The `Events` at the bottom of `describe` state the failure most directly; `grep -A5 -i events` shows just that part.

Check the current image tag:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — the image name:tag the Deployment uses for its Pods.

The image tag doesn't exist. Fix it to a valid tag:

Replace the image tag:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — replaces the image of the container named `web`; the template changes so new Pods roll out.

Wait for the rollout:

```bash
kubectl rollout status deploy/shop
```

- Waits for all new Pods to be Ready. If it hangs, `Ctrl+C` and `describe` again to find out why.

Once `shop` is 2/2 Ready, ① is solved.

## 2. Fix the Service selector

The Pods are up now, but Service `shop` sends no traffic. Check its endpoints.

Check the endpoints:

```bash
kubectl get endpoints shop            # <none> — no Pods attached
```

- `<none>` under `ENDPOINTS` means no Ready Pod matches the Service selector.

Check the Service selector:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX (typo)
```

- `{.spec.selector}` — the label condition the Service uses to pick Pods, as JSON.

Check the real Pod labels:

```bash
kubectl get pods -l app=shop --show-labels                  # real label is app=shop
```

- `--show-labels` — adds a `LABELS` column with every label on each Pod; compare it with the selector character by character.

The Service selector doesn't match the Pod labels. Fix it:

Fix the selector:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — edits just some fields of a resource in place.
- `--type=merge` — merges the JSON given with `-p` into the object (JSON merge patch).
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — the patch contains only what changes; single quotes keep the shell from interpreting it.

Re-check the endpoints:

```bash
kubectl get endpoints shop            # now populated with Pod IPs
```

When endpoints are populated, ② is solved.

## 3. Fix the missing ConfigMap

The `cart` Pod is stuck in `CreateContainerConfigError`. Find out why.

Check cart Pod status:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — the image is there but the container config (a referenced ConfigMap/Secret, …) can't be built.

Find the cause in events:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- The Events name the missing object (`configmap "cart-config" not found`).

Check the referenced envFrom:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — the ConfigMaps/Secrets the container imports wholesale as environment variables.

It references a ConfigMap `cart-config` that doesn't exist. Create it and the kubelet starts the
Pod:

Create the ConfigMap:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- Two `--from-literal=key=value` flags create a ConfigMap with two keys. Once it exists, the kubelet's retry starts the container.

Wait for the rollout:

```bash
kubectl rollout status deploy/cart
```

When `cart` is 1/1 Ready, ③ is solved — all three failures revived.

```bash
kubectl get deploy,svc,endpoints      # final check
```

- One final look at Deployment READY, Services and endpoints to confirm all three faults are fixed.
