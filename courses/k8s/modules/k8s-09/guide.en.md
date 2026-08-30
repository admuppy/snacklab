# NetworkPolicy — Microsegmentation

By default every Pod in a cluster can talk to every other Pod. A **NetworkPolicy** is a
pod-level firewall: for Pods chosen by label it defines which **sources (from) / destinations
(to)** are allowed. Rules are an **allow list** — the moment a policy "selects" a Pod, that Pod
only accepts explicitly allowed traffic (everything else is denied).

This lab already has a server `web` (+Service `web`) and a client Pod `client` (label
`app=client`). k3s enforces NetworkPolicies for real.

Check the web Pod:

```bash
kubectl get pod -l app=web -o wide
```

Check the client Pod:

```bash
kubectl get pod client -o wide
```

> Reference: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. Verify baseline connectivity

With no policy, confirm the client can reach web, and save that baseline to
`~/work/baseline.txt` — you will compare against it in steps 2 and 3.

Test client → web connectivity:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx response
```

Create a directory for the record:

```bash
mkdir -p ~/work
```

Save the baseline response:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

Check the saved content:

```bash
head -1 ~/work/baseline.txt
```

Seeing the first line of nginx HTML (`<!DOCTYPE html>`) means it's open.

## 2. Default-deny ingress

Create a policy that **selects** the `web` Pods but has **no ingress rules** — all inbound
traffic to the selected Pods is blocked.

Create the default-deny policy:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
```

Verify it is blocked (expect timeout):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # times out (blocked)
```

When `wget` times out, the policy has cut the traffic.

## 3. Allow from a specific source

Now add a policy allowing port 80 only from Pods labeled `app=client`. Policies are additive, so
this allow layers on top of the default-deny and only the client gets through.

Create the allow policy:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
```

Re-test client → web:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # works again
```

Success when client → web is restored. Try from another Pod without the `app=client` label and
it stays blocked — that's microsegmentation.

> Reference: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
