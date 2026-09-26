# Scheduling — Affinity, Taints, DaemonSets

The scheduler decides which node runs a Pod. **nodeAffinity/nodeSelector** makes a Pod *prefer*
certain nodes; **taints/tolerations** make a node *repel* Pods that don't tolerate it — opposite
tools. A **DaemonSet** places one Pod on every (matching) node.

This cluster has a single node. Get its name with:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — command substitution; `{.items[0].metadata.name}` extracts the first node's name into the shell variable `node`.
- `; echo "$node"` — prints it to confirm. Later commands refer to it as `"$node"`.

> Reference: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. Node labels and nodeAffinity

Label the node `disktype=ssd` and create Pod `affine` that, via a `requiredDuringScheduling`
nodeAffinity, only lands on nodes carrying that label.

Label the node:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <resource> <name> key=value` — adds a label. Use `--overwrite` to change an existing key, `key-` to remove it.

Create the nodeAffinity Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: affine }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disktype, operator: In, values: ["ssd"] }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `requiredDuringSchedulingIgnoredDuringExecution` — **must** hold at scheduling time; Pods already running are not evicted if the label changes later.
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — only nodes whose `disktype` label is `ssd` qualify (other operators: `NotIn`, `Exists`, …).

Check Pod placement:

```bash
kubectl get pod affine -o wide      # NODE column = our node
```

- The `NODE` column from `-o wide` shows which node the Pod landed on.

Remove the label (`kubectl label node "$node" disktype-`) and a new such Pod goes `Pending` —
try it.

## 2. Taints and tolerations

Add a `lab=demo:NoSchedule` **taint** to the node and Pods that don't **tolerate** it can't be
scheduled. Only `tolerant`, which carries a toleration, lands.

Taint the node:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <node> key=value:effect` — taints the node. Effects: `NoSchedule` (reject new Pods), `PreferNoSchedule` (avoid if possible), `NoExecute` (also evict running Pods).
- Remove it by appending `-`: `kubectl taint nodes "$node" lab=demo:NoSchedule-`

A Pod without a toleration stays Pending (demo):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — runs the next command after the first finishes, so you see the Pod's status right after creating it.
- With no toleration it stays `Pending`; `kubectl describe pod notol` shows `untolerated taint` in Events.

Delete the demo Pod:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <name>` — deletes the Pod. Leaving the test Pod around would get in the way of later checks.

Create the tolerating Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: tolerant }
spec:
  tolerations:
    - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `tolerations` — taints this Pod can tolerate; `key`, `value` and `effect` must match the node's taint.
- `operator: Equal` also compares the value; `Exists` accepts any value for the key.

Check Pod status:

```bash
kubectl get pod tolerant -o wide     # Running
```

- Thanks to the toleration it can land on the tainted node and becomes `Running`.

> `NoSchedule` only blocks new Pods; `NoExecute` also evicts existing Pods that don't tolerate
> the taint.

## 3. DaemonSet

A **DaemonSet** keeps one Pod on every node (log shippers, node agents). Because we tainted the
node with `lab`, the DaemonSet Pod must **also carry a toleration** to be placed.

Create the DaemonSet:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
        - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
      containers:
        - name: agent
          image: busybox:1.36
          args: ["/bin/sh","-c","sleep 3600"]
          resources: { requests: { cpu: "10m", memory: "16Mi" } }
EOF
```

- `kind: DaemonSet` — no `replicas`; keeps exactly one Pod on every eligible node.
- `selector.matchLabels` must match `template.metadata.labels`.
- Because of the `lab` taint on the node, the same `tolerations` are needed here too.

Check DaemonSet status:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` is short for `daemonset`. `DESIRED` — nodes that should run a Pod, `CURRENT` — Pods created, `READY` — Pods ready.

Success when `DESIRED` and `READY` equal the node count (1).

> Reference: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
