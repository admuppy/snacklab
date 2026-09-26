# Services and Cluster Networking

Pods die and come back with new IPs. A **Service** selects a set of Pods by label and gives
them a stable virtual IP, a DNS name, and load balancing. In this lab you expose an existing
Deployment `web` (label `app=web`, 2 replicas) through three Service types.

Check the Deployment:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — confirm the Deployment you are about to expose exists and all Pods are `READY`.

Check the backend pods:

```bash
kubectl get pods -l app=web -o wide     # backend pod IPs
```

- `-l app=web` — list Pods by the same label the Service selector will use.
- `-o wide` — shows the Pod IP column; compare it with the Service endpoints later.

> Reference: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. Expose with ClusterIP

The default type **ClusterIP** creates a virtual IP reachable only from inside the cluster.
Name the Service `web`, port 80.

Create the Service:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — creates a Service reusing the Deployment's Pod selector (`app=web`).
- `--name=web` — the Service name, which also becomes its DNS name.
- `--port=80` — port the Service listens on; `--target-port=80` — container port traffic is forwarded to.
- Without `--type` the default is `ClusterIP`.

Check the Service:

```bash
kubectl get svc web
```

- `svc` is short for `service`. `CLUSTER-IP` is the virtual IP reachable only inside the cluster.

Check the endpoints:

```bash
kubectl get endpoints web           # pod IP:port list chosen by the selector
```

- `endpoints` — the backends (Pod IP:port) the Service actually sends traffic to. Only **Ready** Pods matching the selector are listed.

Test from inside the cluster:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — starts a throwaway test Pod named `t`.
- `--restart=Never --rm -it` — run once without restarts, attach your terminal (`-it`) to see the output, and delete the Pod when it exits (`--rm`).
- Everything after `--` is the command run inside the container. The trailing `\` continues the same command on the next line.
- `wget -qO- <URL>` — fetch quietly (`-q`) and write to stdout (`-O-`) instead of a file.
- `web.default.svc.cluster.local` — Service DNS name in the form `<service>.<namespace>.svc.cluster.local`.

Routing works once `kubectl get endpoints web` lists pod IPs. Empty endpoints mean the
selector (`app=web`) does not match the pod labels.

## 2. Expose with NodePort

**NodePort** opens a fixed port (default 30000–32767) on every node so the Service is reachable
from outside the cluster. Create Service `web-np`.

Create the NodePort Service:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — on top of the ClusterIP, opens **the same port on every node** (auto-picked from 30000–32767) for access from outside the cluster.
- `--name=web-np` — a different name so it doesn't clash with the `web` Service.

Check the assigned port:

```bash
kubectl get svc web-np                          # PORT(S) shows 80:3xxxx/TCP
```

- In `PORT(S)` `80:3xxxx/TCP`, the first number is the Service port and the second is the nodePort opened on the nodes.

Store the nodePort in a variable:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — command substitution; stores the command's output in the shell variable `np`.
- `{.spec.ports[0].nodePort}` — JSONPath for the nodePort of the first port entry.

Access it on the node:

```bash
curl -s http://127.0.0.1:$np | head -1          # hit it on the node (this pod)
```

- `curl -s` — sends the HTTP request silently (no progress bar); `$np` expands to the nodePort saved above.
- `127.0.0.1` — in this lab your terminal is the node, so you hit the node's own address.
- `| head -1` — show only the first line of the response.

Success when a `80:3xxxx/TCP` nodePort is assigned and curl returns the nginx response.

## 3. Headless Service and DNS

A **Headless Service** (`clusterIP: None`) has no virtual IP or proxy; a DNS query returns the
**IP of each Pod** directly as A records. Used for per-pod addressing (e.g. StatefulSets).

Create the headless Service:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: web-h, namespace: default }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `clusterIP: None` — declares a Headless Service: no virtual IP; the IPs of the selected Pods go straight into DNS.

Check the CLUSTER-IP:

```bash
kubectl get svc web-h                 # CLUSTER-IP is None
```

- `CLUSTER-IP` of `None` means headless; kube-proxy does not load-balance it.

Test the DNS query:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # one A record per pod
```

- `kubectl run t --image=busybox:1.36` — starts a throwaway test Pod named `t`.
- `--restart=Never --rm -it` — run once without restarts, attach your terminal (`-it`) to see the output, and delete the Pod when it exits (`--rm`).
- Everything after `--` is the command run inside the container. The trailing `\` continues the same command on the next line.
- `nslookup <name>` — queries DNS and prints the A records (IPs). A headless Service returns one per Pod.

Success when `CLUSTER-IP` is `None` and nslookup returns one IP per pod.

> Reference: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
