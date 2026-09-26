# ConfigMaps and Secrets

Keep configuration out of your code. A **ConfigMap** holds plain config; a **Secret** holds
sensitive values (passwords, tokens) base64-encoded. Both can be injected into a Pod as
**environment variables** or as **files in a volume**.

> Reference: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. Create a ConfigMap

Create a ConfigMap `app-config` with keys `APP_MODE` and `APP_GREETING`.

Create the ConfigMap:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — creates the ConfigMap `app-config` imperatively. A trailing `\` continues one command over several lines.
- `--from-literal=key=value` — adds a key/value pair directly; repeatable. Quote values containing spaces.
- From files use `--from-file=<path>`; from an env file use `--from-env-file=<path>`.

Inspect the contents:

```bash
kubectl get cm app-config -o yaml
```

- `cm` is short for `configmap`. `-o yaml` shows the stored object as-is (keys/values under `data:`).

Confirm both keys landed with `kubectl describe cm app-config`.

## 2. Create a Secret

Create an **Opaque** Secret `app-secret` with key `DB_PASSWORD`. `create secret generic`
base64-encodes the value automatically.

Create the Secret:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — creates an `Opaque` Secret for arbitrary key/values (other types: `tls`, `docker-registry`).
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — the value is base64-encoded automatically on save. Single quotes stop the shell from interpreting special characters.

Check the encoded value:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — extracts just one key's value (a base64 string) from the Secret's `data`.

Decode and check:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — decodes (`-d`) the base64 back to the original value. Anyone allowed to read the Secret can see the plaintext.

> Note: Secret data is encoded, not encrypted. In production, restrict access with etcd
> encryption and RBAC — [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. Consume them in a Pod

Create a Pod `app` that injects the **ConfigMap as env vars (envFrom)** and mounts the
**Secret as files** under `/etc/app-secret`.

Create the Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      envFrom:
        - configMapRef: { name: app-config }
      volumeMounts:
        - { name: secret-vol, mountPath: /etc/app-secret, readOnly: true }
  volumes:
    - name: secret-vol
      secret: { secretName: app-secret }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — feeds the YAML up to the `EOF` line to kubectl on stdin. `-f -` means "read stdin instead of a file"; quoting `'EOF'` stops the shell from expanding `$` inside the body.
- `envFrom.configMapRef` — injects **every key** of the ConfigMap as an environment variable of the same name (for one key use `env[].valueFrom.configMapKeyRef`).
- `volumes[].secret` + `volumeMounts` — mounts each Secret key as a file `/etc/app-secret/<key>`.

Wait until Ready:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — waits until the Pod's `Ready` condition is true.
- `--timeout=60s` — gives up with an error after that long.

Check the env vars:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → env
```

- `kubectl exec app -- <cmd>` — runs a command inside the running container; everything after `--` runs in the container.
- `printenv A B` — prints only the named environment variables.

Check the Secret file:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → file
```

- A Secret mounted as a volume shows up as already-decoded plaintext files; each key name is a file name.

Success when the env vars are visible and the file `/etc/app-secret/DB_PASSWORD` exists.

> Reference: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
