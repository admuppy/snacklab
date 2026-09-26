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

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `resources.requests` — the minimum the scheduler reserves on a node; `limits` — the hard ceiling.
- `cpu: "250m"` — millicores (1000m = 1 CPU); `memory: "64Mi"` — binary mebibytes.
- Equal requests and limits make the Pod `Guaranteed`.

Check the QoS class:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — extracts the QoS class (`Guaranteed`/`Burstable`/`BestEffort`) recorded in the Pod status.

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

- limits (500m/128Mi) are larger than requests (100m/32Mi) → reserves little, bursts up to the limits when the node has room (`Burstable`).

Check the QoS class:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — extracts the QoS class (`Guaranteed`/`Burstable`/`BestEffort`) recorded in the Pod status.

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

- `kind: LimitRange` — resource rules applied to containers created in this namespace.
- `default` — limits filled in when a container sets none; `defaultRequest` — the same for requests.
- Defaults are injected **at Pod creation**, so existing Pods are not changed.

Create a Pod with no explicit limits — the LimitRange fills them in:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <name> --image=<image>` — creates a single Pod directly, no Deployment. Resources are deliberately left out here.

Check the injected resources:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — prints the first container's whole resources block as JSON; the values you didn't write were filled in by the LimitRange.

Success when Pod `defaulted` has `resources.limits.memory` set to `128Mi`.

> Reference: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
