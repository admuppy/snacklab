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

Check recent events:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

> Reference: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. Fix the image pull failure

The `shop` Pods are in `ImagePullBackOff`/`ErrImagePull`. Find out why.

Check shop Pod status:

```bash
kubectl get pods -l app=shop
```

Find the cause in events:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # a "not found" tag shows up
```

Check the current image tag:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

The image tag doesn't exist. Fix it to a valid tag:

Replace the image tag:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

Wait for the rollout:

```bash
kubectl rollout status deploy/shop
```

Once `shop` is 2/2 Ready, ① is solved.

## 2. Fix the Service selector

The Pods are up now, but Service `shop` sends no traffic. Check its endpoints.

Check the endpoints:

```bash
kubectl get endpoints shop            # <none> — no Pods attached
```

Check the Service selector:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX (typo)
```

Check the real Pod labels:

```bash
kubectl get pods -l app=shop --show-labels                  # real label is app=shop
```

The Service selector doesn't match the Pod labels. Fix it:

Fix the selector:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

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

Find the cause in events:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

Check the referenced envFrom:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

It references a ConfigMap `cart-config` that doesn't exist. Create it and the kubelet starts the
Pod:

Create the ConfigMap:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

Wait for the rollout:

```bash
kubectl rollout status deploy/cart
```

When `cart` is 1/1 Ready, ③ is solved — all three failures revived.

```bash
kubectl get deploy,svc,endpoints      # final check
```
