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

- `-l app=web` selects the server Pods and `-o wide` shows their IPs. NetworkPolicies select Pods by this same label.

Check the client Pod:

```bash
kubectl get pod client -o wide
```

- The client Pod. Check its `app=client` label with `kubectl get pod client --show-labels` — step 3's allow rule is based on it.

> Reference: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. Verify baseline connectivity

With no policy, confirm the client can reach web, and save that baseline to
`~/work/baseline.txt` — you will compare against it in steps 2 and 3.

Test client → web connectivity:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx response
```

- `kubectl exec client -- …` — sends the request from **inside** the client Pod, so the client is the source.
- `wget -q -T 3 -O- http://web` — requests the `web` Service with a 3 s timeout (`-T 3`) and writes the response to stdout (`-O-`).
- `| head -1` — show only the first line.

Create a directory for the record:

```bash
mkdir -p ~/work
```

- `mkdir -p` — creates parent directories as needed and does not fail if it already exists.

Save the baseline response:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> file` — saves (overwrites) the command's stdout to a file. `kubectl exec` output comes back to your terminal, so the file is created locally.

Check the saved content:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <file>` — prints only the first line of the file.

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

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `podSelector` — the Pods the policy applies to (`app=web`); an empty selector `{}` means every Pod in the namespace.
- `policyTypes: [Ingress]` with no `ingress:` rules → all inbound traffic to the selected Pods is denied.

Verify it is blocked (expect timeout):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # times out (blocked)
```

- `-t 1` — a single try. When blocked it ends with `timed out` after 3 s (packets are silently dropped, not rejected).

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

- `ingress[].from[].podSelector` — allows only Pods labelled `app=client` in the same namespace as the source.
- `ports` — allowed port/protocol (TCP 80). `from` and `ports` in the same entry must both match.
- Policies are additive (OR), so this allow applies on top of default-deny.

Re-test client → web:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # works again
```

Success when client → web is restored. Try from another Pod without the `app=client` label and
it stays blocked — that's microsegmentation.

> Reference: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
