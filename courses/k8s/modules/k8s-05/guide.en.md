# Resource Requests, Limits, and QoS

Give containers **requests** (the minimum the scheduler reserves) and **limits** (the ceiling —
CPU is throttled, memory is OOM-killed when exceeded). Their combination puts a Pod into one of
three **QoS classes**, which decides **eviction order** under node pressure: `BestEffort` is
evicted first, then `Burstable`, and `Guaranteed` last.

> Reference: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. A Guaranteed QoS Pod

When every container sets **equal requests and limits for both cpu and memory**, the Pod is
`Guaranteed` — the most protected class.

Create the Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF
```

Check the QoS class:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

## 2. A Burstable QoS Pod

With requests set but limits higher (or only partially set) the Pod is `Burstable`: it normally
uses its requests and can burst up to its limits when capacity allows.

Create the Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF
```

Check the QoS class:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

> With no requests/limits at all a Pod is `BestEffort` — try `kubectl run be --image=nginx:1.26`
> then `kubectl get pod be -o jsonpath='{.status.qosClass}'`.

## 3. LimitRange defaults

A **LimitRange** sets default requests/limits for a namespace so Pods get resource bounds even
when a developer forgets. It must exist **before** the Pod for the defaults to be injected.

Create the LimitRange:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # default limits
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # default requests
EOF
```

Create a Pod with no explicit limits — the LimitRange fills them in:

```bash
kubectl run defaulted --image=nginx:1.26
```

Check the injected resources:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

Success when Pod `defaulted` has `resources.limits.memory` set to `128Mi`.

> Reference: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
