# Explanations

These explanations appear only for the tasks you did not score full marks on.
There is more than one right answer — grading checks "does the result match the spec", so
what follows is the shortest reference solution.

## Q1 Sidecar container — log streaming

One pod, two containers, one emptyDir. The whole point is that **both containers mount the
same volume at the same path**.

```yaml
apiVersion: v1
kind: Pod
metadata: { name: logger, namespace: dev }
spec:
  volumes: [{ name: logs, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: streamer
      image: busybox:1.36
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

Common mistakes

- Forget the sidecar's volumeMount and `tail` cannot even find an empty file — the log item
  (2 pts) is gone.
- `tail -F` (capital) waits for the file to appear; `-f` exits when it does not exist yet and
  can crash-loop the container.
- Grading checks that `tick` really flows in `kubectl logs logger -c streamer` — a correct
  shape with a wrong command earns nothing there.

## Q2 Job and CronJob

Create the Job imperatively and add completions/parallelism in YAML — that is faster.

```bash
kubectl create job pi -n batch --image=busybox:1.36 --dry-run=client -o yaml -- sh -c "echo 3.14159" > job.yaml
# add completions: 3 and parallelism: 2 under spec:, then
kubectl apply -f job.yaml
kubectl create cronjob cleanup -n batch --image=busybox:1.36 --schedule="0 3 * * *" \
  --dry-run=client -o yaml -- sh -c "echo cleaned" > cj.yaml
# add concurrencyPolicy: Forbid and successfulJobsHistoryLimit: 1 under spec:, then
kubectl apply -f cj.yaml
```

Common mistakes

- `completions`/`parallelism` live in the **Job's spec**, not in template.spec.
- The CronJob's `concurrencyPolicy` and `successfulJobsHistoryLimit` also sit at the
  **CronJob spec** level (not jobTemplate.spec).
- Omitting `restartPolicy: Never` makes Job creation fail outright (there is no default).

## Q3 Prepare content with an init container

The main container only starts after the init container finishes. Hand over the prepared
file through the emptyDir.

```yaml
spec:
  volumes: [{ name: web, emptyDir: {} }]
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo ready-to-serve > /work/index.html"]
      volumeMounts: [{ name: web, mountPath: /work }]
  containers:
    - name: web
      image: nginx:1.26
      volumeMounts: [{ name: web, mountPath: /usr/share/nginx/html }]
```

Common mistakes

- If the main mount path is not the nginx docroot (`/usr/share/nginx/html`), the HTTP item
  (2 pts) fails.
- Different volume names mean the file the init container wrote never reaches the main container.

## Q4 Rolling update — zero-downtime strategy

Strategy first, image second. In the other order the first rollout runs with the default
strategy (25%).

```bash
kubectl patch deploy api -n prod --type merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image deploy/api -n prod api=nginx:1.26
kubectl rollout status deploy/api -n prod
```

Common mistakes

- `kubectl edit` works just as well — grading only reads the field values.
- `maxUnavailable: 0` together with `maxSurge: 0` deadlocks the rollout forever.
- Confirm completion with `rollout status` before submitting, or the "both replicas Ready on
  the new version" item (2 pts) may not be there yet.

## Q5 Canary deployment — 25% of traffic

Leave the service selector (`app: shop`) alone; a second Deployment with the **same app label
plus a different track label** is all a label-based canary is.

```bash
kubectl create deploy shop-canary -n prod --image=nginx:1.26 --replicas=1 --dry-run=client -o yaml > canary.yaml
# fix the pod template labels to app: shop, track: canary (and the selector to match), then apply
kubectl scale deploy shop -n prod --replicas=3
```

Common mistakes

- `kubectl create deploy` generates the label `app: shop-canary` — you **must change it to
  `app: shop`** or the service never picks the canary up (the 2-pt endpoints item hangs on this).
- If the selector and the template labels disagree, the apply itself is rejected.
- Forgetting to scale stable down to 3 leaves a 4:1 split — that is not 25%.

## Q6 Kustomize overlay

An overlay is complete with a single kustomization.yaml that refers back to the base.

```yaml
# ~/work/kustomize/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources: [../../base]
replicas: [{ name: hello-web, count: 2 }]
images: [{ name: nginx, newTag: "1.26" }]
```

```bash
kubectl apply -k ~/work/kustomize/overlays/prod
```

Common mistakes

- The relative path in `resources` is **relative to the overlay directory** (`../../base`).
- `images.name` is the **image name** the base uses (nginx), not the container name (web).
- `newTag` is a string — quoting it (`"1.26"`) is the safe habit.
- Writing the files but forgetting `apply -k` loses all 5 cluster points.

## Q7 Probes — self-healing and traffic gating

Copy the numbers from the task verbatim. Probes are container-level fields.

```yaml
containers:
  - name: web
    image: nginx:1.26
    readinessProbe:
      httpGet: { path: /, port: 80 }
      initialDelaySeconds: 3
      periodSeconds: 5
    livenessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 10
```

Common mistakes

- The readiness and liveness blocks look alike and are easy to swap — they are graded separately.
- A wrong port (8080, say) fails the spec item and the Ready item (1 pt) with it.

## Q8 Troubleshoot — CrashLoopBackOff

Investigate (save the log), then repair (replace the command) — in that order.

```bash
kubectl logs deploy/orders -n broken > ~/answers/q8.txt 2>&1   # captures "not found"
kubectl patch deploy orders -n broken --type json -p \
  '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","while true; do date; sleep 5; done"]}]'
```

Common mistakes

- A crash-looping pod's log shows the last run's output even without `--previous`. If it is
  empty, use `kubectl logs <pod> -n broken --previous`.
- The answer file must hold the **actual output containing the error** — a hand-written
  summary does not count.
- Fixing the command via `kubectl edit deploy orders -n broken` counts just the same.

## Q9 Fix removed API versions

`apps/v1beta1` and `batch/v1beta1` were removed long ago. The current versions are `apps/v1`
and `batch/v1`.

```bash
sed -i -e 's|apps/v1beta1|apps/v1|' -e 's|batch/v1beta1|batch/v1|' ~/work/legacy/stack.yaml
kubectl apply -f ~/work/legacy/stack.yaml
```

Common mistakes

- Not sure which version is current? `kubectl api-resources | grep -i cronjob` or
  `kubectl explain cronjob` prints the live group/version.
- **The file itself** is graded (2 pts) — writing a fresh YAML elsewhere and leaving the file
  untouched loses that item.
- Apply and then confirm report-api is Ready, or the final point may slip away.

## Q10 Consume a ConfigMap and a Secret

Two imperative lines to create, YAML to consume.

```bash
kubectl create configmap app-config -n dev --from-literal=mode=production --from-literal=timeout=30
kubectl create secret generic db-cred -n dev --from-literal=user=admin --from-literal=pass=S3cret1
```

```yaml
spec:
  volumes: [{ name: creds, secret: { secretName: db-cred } }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef: { name: app-config, key: mode }
      volumeMounts: [{ name: creds, mountPath: /etc/creds, readOnly: true }]
```

Common mistakes

- A literal `env: [{name: APP_MODE, value: production}]` **does not count** — grading checks
  for the `configMapKeyRef` reference.
- A Secret volume becomes one file per key (`/etc/creds/user`, `/etc/creds/pass`).
- Editing the ConfigMap after the pod exists does not change env vars — recreate the pod if
  you put a wrong value in.

## Q11 SecurityContext — non-root, read-only

runAsUser/runAsNonRoot may sit at the pod level; the other three are **container-level**.

```yaml
spec:
  securityContext: { runAsUser: 1000, runAsNonRoot: true }
  volumes: [{ name: tmp, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      volumeMounts: [{ name: tmp, mountPath: /tmp }]
```

Common mistakes

- `allowPrivilegeEscalation`, `readOnlyRootFilesystem` and `capabilities` at the pod level are
  a **schema error** — they exist only in the container securityContext.
- With a read-only root some images fail to start without writable space — the `/tmp` emptyDir
  is that provision.
- Verify the uid actually took effect: `kubectl exec secure-app -n dev -- id -u`.

## Q12 ServiceAccount and token automount

```bash
kubectl create serviceaccount app-sa -n dev
```

```yaml
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
```

Common mistakes

- `automountServiceAccountToken` is a **pod-spec-level** field (not under the container).
- Setting it on the SA has the same effect, but the task said "turn it off in the pod spec",
  so the spec item (1 pt) requires it on the pod.
- Verify with `kubectl exec sa-pod -n dev -- ls /var/run/secrets/kubernetes.io/serviceaccount`
  — "No such file or directory" is the correct state.

## Q13 Requests and limits — inside a quota

```bash
kubectl create deploy worker -n batch --image=busybox:1.36 --replicas=2 --dry-run=client -o yaml > worker.yaml
# fill in command and resources, then apply
```

```yaml
resources:
  requests: { cpu: 100m, memory: 64Mi }
  limits: { cpu: 200m, memory: 128Mi }
```

Common mistakes

- **Why this task exists**: in a namespace with a ResourceQuota, pods without requests are
  rejected outright. The Deployment gets created, but with 0 pods —
  `kubectl get events -n batch` shows `failed quota`.
- Use the task's exact notation: Kubernetes treats `0.1` and `100m` the same, but grading
  compares the normalised string (100m), so copying the task's form is the safe move.

## Q14 Services — ClusterIP and NodePort

```bash
kubectl expose deploy frontend -n prod --name=frontend-svc --port=80 --target-port=80
kubectl expose deploy frontend -n prod --name=frontend-np --port=80 --target-port=80 --type=NodePort \
  --dry-run=client -o yaml > np.yaml
# add nodePort: 30080 to ports[0], then apply
```

Common mistakes

- `expose` cannot set a nodePort value — add `nodePort: 30080` to the dry-run YAML by hand.
- A hand-written selector that is not `app: frontend` leaves the endpoints empty and all 3
  traffic points fall with it.
- In-cluster check: `kubectl exec client -n dev -- wget -qO- http://frontend-svc.prod.svc.cluster.local`.

## Q15 Author an Ingress resource

No controller — still write the resource to full spec.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: frontend-svc, port: { number: 80 } } }
          - path: /shop
            pathType: Prefix
            backend: { service: { name: shop-svc, port: { number: 80 } } }
```

Common mistakes

- `pathType` is required — omit it and the apply is rejected. The task says Prefix.
- Shortening `port: { number: 80 }` to `port: 80` is a schema error.
- Both paths belong **under the same host rule**. Splitting them into two host entries still
  grades, but one rule is the canonical form.

## Q16 NetworkPolicy — admit named clients only

Select the target pods (podSelector, not from), then list who is admitted under from.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: cache-guard, namespace: dev }
spec:
  podSelector:
    matchLabels: { app: cache }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: client }
      ports:
        - { protocol: TCP, port: 80 }
```

Common mistakes

- Swapping `podSelector` (target) and `from.podSelector` (admitted source) produces the exact
  opposite policy.
- For selected pods a NetworkPolicy **blocks everything not explicitly allowed** — no
  separate deny rule is needed.
- This cluster really enforces policies (kube-router). Before submitting, verify that
  `kubectl exec intruder -n dev -- wget -T2 -qO- http://<cache IP>` **fails**.
