# ConfigMap 与 Secret

配置与代码分离是基本原则。**ConfigMap** 保存明文配置,**Secret** 保存密码、令牌等敏感信息
(以 base64 编码),二者都可以作为 **环境变量** 或 **卷中的文件** 注入到 Pod。

> 参考: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. 创建 ConfigMap

创建包含键 `APP_MODE` 和 `APP_GREETING` 的 ConfigMap `app-config`。

创建 ConfigMap:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — 以命令式方式创建 ConfigMap `app-config`。行尾的 `\` 表示把一条命令分成多行书写。
- `--from-literal=键=值` — 直接写入键值对,可以指定多次;含空格的值要用引号括起来。
- 从文件创建用 `--from-file=<路径>`,从 env 文件创建用 `--from-env-file=<路径>`。

查看内容:

```bash
kubectl get cm app-config -o yaml
```

- `cm` 是 `configmap` 的缩写。`-o yaml` 可原样查看保存的对象(`data:` 下的键值)。

用 `kubectl describe cm app-config` 确认两个键都已写入。

## 2. 创建 Secret

创建包含键 `DB_PASSWORD` 的 **Opaque** Secret `app-secret`。`create secret generic`
会自动对值进行 base64 编码。

创建 Secret:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — 创建用于任意键值的 `Opaque` 类型 Secret(另有 `tls`、`docker-registry` 类型)。
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — 保存时值会自动 base64 编码。单引号防止 shell 解释特殊字符。

查看编码后的值:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — 只取出 Secret 的 `data` 中某一个键的值(base64 字符串)。

解码后查看:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — 对 base64 解码(`-d`),还原成原始值。也就是说,只要有读取 Secret 的权限,任何人都能看到明文。

> 注意: Secret 的 data 只是编码而不是加密。生产环境中要通过 etcd 加密和 RBAC 限制访问 —
> [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. 在 Pod 中注入使用

创建 Pod `app`,把 **ConfigMap 作为环境变量(envFrom)**、**Secret 作为卷文件**
(`/etc/app-secret`)注入。

创建 Pod:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `envFrom.configMapRef` — 把 ConfigMap 的 **所有键** 注入为同名环境变量(只要一个键时用 `env[].valueFrom.configMapKeyRef`)。
- `volumes[].secret` + `volumeMounts` — 把 Secret 的每个键挂载为文件 `/etc/app-secret/<键>`。

等待 Ready:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — 等到 Pod 的 `Ready` 条件为真。
- `--timeout=60s` — 超过这个时间仍未满足则以失败结束。

查看环境变量:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → 环境变量
```

- `kubectl exec app -- <命令>` — 在运行中的容器里执行命令,`--` 之后是在容器中运行的命令。
- `printenv A B` — 只输出指定环境变量的值。

查看 Secret 文件:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → 文件
```

- 以卷方式挂载的 Secret 会显示为已经解码的明文文件,键名就是文件名。

环境变量中能看到 `APP_MODE`/`APP_GREETING`,且存在文件 `/etc/app-secret/DB_PASSWORD`,即为成功。

> 参考: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
