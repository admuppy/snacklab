# Explanations

After you submit, the notes below appear only for the questions you did not score full marks on.
There is more than one correct answer — grading looks at the resulting state, so these are simply
the shortest reference answers.

## Q1 RBAC — ServiceAccount, Role, RoleBinding

A read-only identity is three imperative commands. Hand-writing the YAML in an exam wastes time.

```bash
kubectl create serviceaccount deploy-bot -n app-prod
kubectl create role pod-reader -n app-prod --verb=get,list,watch --resource=pods,deployments.apps
kubectl create rolebinding deploy-bot-rb -n app-prod --role=pod-reader --serviceaccount=app-prod:deploy-bot
```

Common mistakes

- `--resource=deployments` resolves to the core API group. It must be `deployments.apps`.
- Using a `ClusterRole`/`ClusterRoleBinding` leaks the permission into other namespaces and loses points.
- `--serviceaccount=` takes **namespace:name**.

Grading runs `kubectl auth can-i --as=system:serviceaccount:app-prod:deploy-bot`, so however you
wrote the rules, only the **effective permissions** matter.

## Q2 Approve a CSR and grant user access

```bash
kubectl certificate approve dev-user
kubectl create rolebinding dev-user-view -n app-prod --clusterrole=view --user=dev-user
```

Common mistakes

- `--serviceaccount=` binds a service account, not the User `dev-user`. It must be **`--user=`**.
- Binding `edit`/`admin` allows deletes and loses points. Read-only is the built-in ClusterRole `view`.
- After approval `kubectl get csr dev-user -o jsonpath='{.status.certificate}'` must not be empty.
  A denied CSR cannot be undone — you would have to restart the lab.

## Q3 Create a static pod

A static pod is started by the **kubelet from a manifest directory on disk**, not by the apiserver.
On k3s that directory is `/var/lib/rancher/k3s/agent/pod-manifests/`.

```bash
kubectl run ops-static --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sh -c "sleep 86400" > /tmp/ops-static.yaml
sudo cp /tmp/ops-static.yaml /var/lib/rancher/k3s/agent/pod-manifests/
```

Common mistakes

- `kubectl apply` creates an ordinary pod. Grading checks the `kubernetes.io/config.source=file` annotation.
- The mirror pod's name has the **node name appended** (`ops-static-<node>`) — leave it as is.
- It takes a few seconds for the kubelet to pick the file up.

## Q4 ResourceQuota and LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: ops-quota, namespace: ops }
spec:
  hard:
    pods: "5"
    requests.cpu: "1"
    requests.memory: 1Gi
---
apiVersion: v1
kind: LimitRange
metadata: { name: ops-limits, namespace: ops }
spec:
  limits:
    - type: Container
      defaultRequest: { cpu: 100m, memory: 128Mi }
      default: { cpu: 200m, memory: 256Mi }
```

Common mistakes

- `pods: 5` fails to parse — quota values must be **strings** (`"5"`).
- In a LimitRange, `default` is the limit and `defaultRequest` is the request. They are easy to swap.
- The entry must be `type: Container` (`Pod` means something else).

## Q5 Deployment and rollout strategy

Generate the skeleton and only fill in `strategy` and `resources.requests`:

```bash
kubectl create deploy web -n app-prod --image=nginx:1.26 --replicas=3 --dry-run=client -o yaml > web.yaml
```

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 50m, memory: 64Mi } }
```

Common mistakes

- Omitting `maxUnavailable: 0` leaves the 25% default and loses a point.
- It is `requests`, not `resources.limits`.
- These `web` pods are also graded by Q8 and Q9 — make sure all three are Ready.

## Q6 Deploy a DaemonSet

`kubectl create` cannot make a DaemonSet. The exam-room trick is to generate a Deployment,
change `kind`, and delete `replicas`/`strategy`.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: ops }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
```

Common mistakes

- Leaving `replicas` in place is rejected — the field does not exist on a DaemonSet.
- busybox exits immediately with its default command and lands in CrashLoop. Give it a `sleep`-style command.
- **Both** cpu and memory requests must be set.

## Q7 Sidecar container with a shared volume

The point is that **both containers mount the same volume at the same path**.

```yaml
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "tail -f /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

Common mistakes

- Two separate volumes look fine in the spec but share nothing. Grading actually **reads**
  `/var/log/app/app.log` from the sidecar.
- The container names are fixed: `app` and `sidecar`.

## Q8 Services — ClusterIP and NodePort

```bash
kubectl expose deploy web -n app-prod --name=web-svc --port=80 --target-port=80
kubectl expose deploy web -n app-prod --name=web-np --type=NodePort --port=80 --target-port=80
kubectl patch svc web-np -n app-prod --type=merge -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'
```

Common mistakes

- `expose` cannot pin a `nodePort` — patch it afterwards or write the YAML.
- Empty endpoints mean the selector does not match the pod labels (`app=web`).
  Check with `kubectl get endpoints web-svc -n app-prod`.
- Grading makes a real HTTP request from the `client` pod to `web-svc.app-prod.svc.cluster.local`.

## Q9 Restrict traffic with a NetworkPolicy

You need two objects — a default deny and an explicit allow.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: app-prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client, namespace: app-prod }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { role: client } }
      ports: [{ protocol: TCP, port: 80 }]
```

Common mistakes

- `podSelector: {}` means "every pod in the namespace" — empty is not the same as absent.
- Putting `podSelector:` and `namespaceSelector:` in the **same `from` item** ANDs them.
  Two separate `-` items OR them.
- Grading checks real traffic: `client` must get through and `intruder` must not.
  The `web` pods from Q5 have to be running for that check.

## Q10 Author an Ingress resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: app-prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
```

Common mistakes

- `pathType` is required — without it the object is rejected.
- `extensions/v1beta1` was removed long ago; use `networking.k8s.io/v1`.
- The backend is `service.name`/`service.port.number`, not the old `serviceName`/`servicePort`.

## Q11 Static PV/PVC binding

Static binding only happens when the PV and the PVC agree on storageClassName, accessModes and size.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 1Gi }
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  hostPath: { path: /mnt/data, type: DirectoryOrCreate }
```
Create the PVC with the same `storageClassName: manual`, `ReadWriteOnce` and 1Gi, then mount it at `/data`.

Common mistakes

- A PVC without `storageClassName` uses the default class (local-path) and gets a **dynamically
  provisioned** volume instead of pv-data. Grading checks `spec.volumeName == pv-data`.
- A PVC that is already bound to the wrong volume cannot be edited — delete and recreate it.

## Q12 Dynamic provisioning and writing data

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-dyn, namespace: app-prod }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources: { requests: { storage: 500Mi } }
```

Common mistakes

- local-path is `WaitForFirstConsumer` — **Pending is normal until a pod consumes the claim**.
  Waiting for Bound with no pod just burns time.
- The size must be `500Mi` (not `500M`).
- Grading reads `/data/hello.txt` from the volume. Let the pod write it, or do it yourself with
  `kubectl exec writer -- sh -c 'echo cka > /data/hello.txt'`.

## Q13 Troubleshoot — a Deployment that never starts

```bash
kubectl -n broken describe pod -l app=api | tail -20   # ErrImagePull / InvalidImageName
kubectl -n broken set image deploy/api api=nginx:1.26
kubectl -n broken rollout status deploy/api
```

Common mistakes

- First tell Pending apart from an image-pull failure — the Events in `describe` say which.
- Deleting and recreating the Deployment is accepted, but the **name, namespace and replicas (2)** must stay.
- Leftover failed pods from the old ReplicaSet cost a point. Confirm convergence with `rollout status`.

## Q14 Troubleshoot — a Service with no endpoints

**Two** things are wrong: the selector and the targetPort. Start from the pod labels and container port.

```bash
kubectl -n broken get pod --show-labels
kubectl -n broken get svc cache-svc -o yaml | head -30
kubectl -n broken patch svc cache-svc --type=merge \
  -p '{"spec":{"selector":{"app":"cache"},"ports":[{"port":80,"targetPort":80}]}}'
kubectl -n broken get endpoints cache-svc
```

Common mistakes

- `port` is what the Service exposes, `targetPort` is the container port. Service port 80 must stay 80.
- Endpoints can be populated and the service still not answer if targetPort is wrong — grading does a real HTTP request.
- `kubectl edit svc` works too, but patching is faster and less error-prone under time pressure.

## Q15 Troubleshoot — CrashLoopBackOff and report the cause

```bash
kubectl -n broken logs deploy/worker --previous     # complains about a missing config file/key
kubectl -n broken describe pod -l app=worker        # check the mounted ConfigMap key
kubectl -n broken get cm worker-config -o yaml
```

The key the container expects does not match the key in the ConfigMap. Fix the ConfigMap and roll out again.

```bash
kubectl -n broken rollout restart deploy/worker
echo "configmap/worker-config" > ~/answers/q15.txt
```

Common mistakes

- The report file `~/answers/q15.txt` must contain the single line **`configmap/worker-config`**
  (case and whitespace are ignored).
- Editing the ConfigMap does **not** update running pods — `rollout restart` is required.
- Grading requires the pod to have stayed up for at least 20 seconds, so submitting immediately
  after the fix can still fall short.

## Q16 etcd backup and offline restore

Backup with `etcdctl`, offline restore with `etcdutl` — the exact tools of the real
exam. Both need `sudo` because the certificates are root-owned.

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  snapshot save ~/backup/etcd-snap.db
sudo etcdutl snapshot restore ~/backup/etcd-snap.db --data-dir ~/backup/restored
sudo etcdutl snapshot status ~/backup/etcd-snap.db   # good habit: verify
```

Common mistakes

- Missing any of `--cacert`/`--cert`/`--key` fails the TLS handshake.
- Restore refuses an existing `--data-dir` — point it at a fresh directory.
- `etcdctl snapshot restore` still works but is deprecated; prefer `etcdutl` in the exam.
- Grading checks the snapshot's revision and `member/snap/db` inside the restore dir —
  an empty file or hand-made directory earns nothing.

## Q17 Drain node worker-1 for maintenance

One line does it; drain implies cordon.

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n maint -o wide   # done when all 4 run on worker-2
```

Common mistakes

- Without `--ignore-daemonsets`, drain can refuse because of DaemonSet pods.
- `cordon` alone only blocks new scheduling — existing pods stay; eviction is what makes
  it a drain.
- Do not `uncordon` afterwards — the maintenance scenario requires the node to stay
  unschedulable.
