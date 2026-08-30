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

Inspect the contents:

```bash
kubectl get cm app-config -o yaml
```

Confirm both keys landed with `kubectl describe cm app-config`.

## 2. Create a Secret

Create an **Opaque** Secret `app-secret` with key `DB_PASSWORD`. `create secret generic`
base64-encodes the value automatically.

Create the Secret:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

Check the encoded value:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

Decode and check:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

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

Wait until Ready:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

Check the env vars:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → env
```

Check the Secret file:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → file
```

Success when the env vars are visible and the file `/etc/app-secret/DB_PASSWORD` exists.

> Reference: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
