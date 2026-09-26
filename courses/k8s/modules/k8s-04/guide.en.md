# Probes and Self-Healing

The kubelet watches container health with three probes. When a **livenessProbe** fails the
container is **restarted** (self-healing); when a **readinessProbe** fails the Pod is **pulled
out** of Service endpoints so it receives no traffic. (A startupProbe protects slow starters.)

This lab's container creates `/tmp/healthy` at startup and **deletes it after 30 seconds.**
Both probes check that file, so after 30s liveness fails and you can watch the auto restart.

> Reference: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. Define a livenessProbe

Apply the Deployment `web` below. Its `livenessProbe` runs `cat /tmp/healthy` every 5s and
restarts the container after a single failure.

Apply the Deployment:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `livenessProbe.exec.command` — runs this command in the container; exit code 0 means healthy (`httpGet` and `tcpSocket` probes also exist).
- `initialDelaySeconds` — wait before the first check, `periodSeconds` — interval, `failureThreshold: 1` — restart after a single failure.
- The shell script in `args` deletes `/tmp/healthy` after 30 s to cause a failure on purpose.

Check the Pod:

```bash
kubectl get pod -l app=web
```

- `READY` reflects readiness; `RESTARTS` counts restarts caused by liveness failures.

## 2. Define a readinessProbe

The manifest above also includes a `readinessProbe`. When the Pod is ready it shows
`READY 1/1`.

Check the Pod status:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — adds columns such as Pod IP, node and readiness gates.

Inspect the readiness probe:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — details (including probe settings) of the Pods selected by label.
- `grep -A3 -i readiness` — case-insensitive (`-i`) match on `readiness` plus the 3 lines after it.

While the readiness probe passes the Pod is Ready; once the file is gone it briefly drops to
`READY 0/1`, then returns to Ready after the restart.

## 3. Induce failure → auto restart

Once the file disappears (after 30s) liveness starts failing. Watch the Pod and `RESTARTS`
climbs.

Watch the Pod:

```bash
kubectl get pod -l app=web -w        # RESTARTS goes 0 → 1 (Ctrl+C to stop)
```

- `-w` (`--watch`) — instead of exiting after one listing, prints a new line whenever something changes. Leave with `Ctrl+C`.

Check probe events:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` is OR in basic regex; shows probe failures (`Liveness`), container kills (`Killing`) and restarts (`Started`) together.

Success once `RESTARTS` is at least 1. To trigger it immediately, delete the file yourself:
`kubectl exec deploy/web -- rm -f /tmp/healthy`.

> Reference: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
