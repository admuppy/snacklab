# Services and Cluster Networking

Pods die and come back with new IPs. A **Service** selects a set of Pods by label and gives
them a stable virtual IP, a DNS name, and load balancing. In this lab you expose an existing
Deployment `web` (label `app=web`, 2 replicas) through three Service types.

Check the Deployment:

```bash
kubectl get deploy web
```

Check the backend pods:

```bash
kubectl get pods -l app=web -o wide     # backend pod IPs
```

> Reference: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. Expose with ClusterIP

The default type **ClusterIP** creates a virtual IP reachable only from inside the cluster.
Name the Service `web`, port 80.

Create the Service:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

Check the Service:

```bash
kubectl get svc web
```

Check the endpoints:

```bash
kubectl get endpoints web           # pod IP:port list chosen by the selector
```

Test from inside the cluster:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

Routing works once `kubectl get endpoints web` lists pod IPs. Empty endpoints mean the
selector (`app=web`) does not match the pod labels.

## 2. Expose with NodePort

**NodePort** opens a fixed port (default 30000–32767) on every node so the Service is reachable
from outside the cluster. Create Service `web-np`.

Create the NodePort Service:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

Check the assigned port:

```bash
kubectl get svc web-np                          # PORT(S) shows 80:3xxxx/TCP
```

Store the nodePort in a variable:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

Access it on the node:

```bash
curl -s http://127.0.0.1:$np | head -1          # hit it on the node (this pod)
```

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

Check the CLUSTER-IP:

```bash
kubectl get svc web-h                 # CLUSTER-IP is None
```

Test the DNS query:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # one A record per pod
```

Success when `CLUSTER-IP` is `None` and nslookup returns one IP per pod.

> Reference: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
