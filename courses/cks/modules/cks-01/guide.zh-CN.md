# CKS 模拟考试 第 1 套（120 分钟 · 16 题 · 100 分）

这是按照 Linux Foundation **CKS（Certified Kubernetes Security Specialist）** 实操考试形式设计的
模拟考试，题目权重与真实考试的各领域一致。

| 领域 | 权重 | 题目 |
|---|---|---|
| 集群搭建 | 15 | Q1 Q2 Q3 |
| 集群加固 | 15 | Q4 Q5 Q6 |
| 系统加固 | 10 | Q7 Q8 |
| 最小化微服务漏洞 | 20 | Q9 Q10 Q11 |
| 供应链安全 | 20 | Q12 Q13 Q14 |
| 监控、日志与运行时安全 | 20 | Q15 Q16 |

**考试方式**

- 限时 **120 分钟**，剩余时间显示在页面顶部。
- 题目可以 **按任意顺序** 作答，先做有把握的题是真实考场的策略。
- 与真实考试一样，**作答过程中不会给出评分反馈**。全部做完后点击下方的
  **[提交并评分]**，16 道题会被一次性评分（每题都会在真实集群上校验，需要一到两分钟）。
- **按部分给分。** 每道题有多个评分项，满足几项就得几分。
  评分结束后，页面上方会显示总分、各题得分和评分项明细，**下方会附上做错题目的解析**。
- **合格线为 67 分**（与真实 CKS 一致）。达到即可看到祝贺信息并获得结业徽章。
- 提交后仍可在剩余时间内继续修改并 **重新评分**，系统记录最高分。
- 题目指定了命名空间时，**必须在该命名空间中** 创建对象。
- 要求提交答案文件的题目，必须写到 **完全一致的指定路径**（`~/answers/…`）才会被评分。

**环境**

一个运行在 Pod 内的 **单节点 k3s v1.36** 集群，完全属于你。`kubectl`（别名 `k`）和
`KUBECONFIG` 均已配置好，`sudo` 无需密码。可以使用 `jq`、`openssl`、
`sha512sum`、`vi`/`nano`。与真实考试一样，你可以查阅
[Kubernetes 官方文档](https://kubernetes.io/docs/)。

```bash
kubectl get nodes
kubectl get ns    # prod、apps、sys-hard、restricted-ns、supply、runtime 均已准备好
ls ~/work         # 题目引用的文件
```

**与真实考试的差异**（环境限制所致）

- 没有 **AppArmor、Falco、gVisor（RuntimeClass）** 类题目。运行在 Pod 内的集群无法保证宿主机
  内核功能，该领域需要另行学习。
- **没有 trivy 二进制。** Q13 使用预先生成的扫描报告（`~/work/scans/`）来判断
  （真实考试中你要自己运行 `trivy image <镜像>`）。
- 环境中没有 Ingress 控制器，因此 **Q2 只评分到资源定义为止**（不做实际 TLS 终止校验）。
- ImagePolicyWebhook / OPA Gatekeeper 因组件引入问题被排除。

> 省时技巧：用 `kubectl create ... --dry-run=client -o yaml > q.yaml` 生成骨架，
> 对已有资源用 `kubectl get ... -o yaml > q.yaml` 下载下来修改后再 apply。
> `kubectl explain pod.spec.securityContext` 也可以随时使用。

## 1. Q1（7 分）NetworkPolicy —— 默认拒绝与选择性放行

命名空间 `prod` 中运行着 `backend`（nginx，`app=backend`）以及发起请求的客户端 Pod
`frontend`（`app=frontend`）和 `other`（`app=other`）。请先默认拒绝，再放行指定路径。

1. `deny-all` —— 对 `prod` 中的 **所有 Pod** **全面拒绝 Ingress**
   （`podSelector: {}`、`policyTypes: ["Ingress"]`）
2. `allow-frontend` —— 对 `app=backend` 的 Pod，只允许来自 `app=frontend` Pod 的 **TCP 80** 流量

评分使用真实流量 —— `frontend` 必须能访问 `backend`，而 `other` 必须被拒绝。

```bash
kubectl exec -n prod frontend -- wget -T3 -qO- http://<backend-Pod-IP>/
kubectl exec -n prod other    -- wget -T3 -qO- http://<backend-Pod-IP>/   # 应当失败
```

> 参考：[NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 2. Q2（4 分）TLS Secret 与 TLS Ingress

为命名空间 `prod` 中的 Web 服务加上 TLS。

1. 用 `openssl` 生成一个 **自签名证书** —— CN 为 `web.snacklab.local`
2. 用该证书和密钥在 `prod` 中创建 **TLS 类型的 Secret** `web-cert`
3. Ingress `web-tls`（`prod`）—— host `web.snacklab.local`、path `/`（Prefix）、
   后端 `web-svc:80`，并在 **`tls` 段中引用 `web-cert`**

本环境没有 Ingress 控制器，因此 **只评分资源定义**。

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
```

> 参考：[Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) ·
> [TLS Secret](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## 3. Q3（4 分）验证平台二进制的完整性

`~/work/binaries/` 中有三个发布二进制（`kube-apiserver`、`kubelet`、`kube-proxy`）以及
发布方公布的校验和文件 `checksums.txt`。

1. **比对 SHA-512 校验和**，找出被篡改的二进制。
2. 将被篡改二进制的 **文件名单独一行** 写入 `~/answers/q3.txt`。例如：`kube-proxy`

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
```

> 参考：[验证发布制品](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/)

## 4. Q4（6 分）将 RBAC 收紧到最小权限

命名空间 `apps` 中的 ServiceAccount `ci-bot` 属于 CI 流水线，但目前 RoleBinding
`ci-bot-rb` 把整个 ClusterRole `admin` 都授予了它 —— **权限过大**。

将 `ci-bot` 限制为恰好只能：

- `pods` —— `get`、`list`
- `deployments`（apps 组）—— `get`、`list`、`update`

Role 命名为 `ci-role`，并 **保持绑定名 `ci-bot-rb` 不变**（重建它没问题）。
如果它仍能读取 Secret 或删除 Pod，就会扣分。

```bash
kubectl auth can-i list secrets -n apps --as=system:serviceaccount:apps:ci-bot   # 必须是 no
```

> 参考：[RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 5. Q5（5 分）阻止 ServiceAccount 令牌自动挂载

命名空间 `apps` 中的 Deployment `web` 从不访问 API，但 **默认 SA 令牌却被挂载进了容器** ——
一旦 Pod 被攻陷，这就是通往 API 的通道。

1. 在 `apps` 中创建 ServiceAccount `web-sa`，并设置 **`automountServiceAccountToken: false`**
2. 让 Deployment `web` 使用 `web-sa`
3. 新 Pod 中 **不应挂载** `/var/run/secrets/kubernetes.io/serviceaccount`

```bash
kubectl exec -n apps deploy/web -- ls /var/run/secrets/kubernetes.io/serviceaccount  # 应当失败
```

> 参考：[退出令牌自动挂载](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting)

## 6. Q6（4 分）移除危险的 ClusterRoleBinding

有人以"调试"为由留下了一个 ClusterRoleBinding，把 **`cluster-admin` 授予了所有已认证用户
（`system:authenticated`）**。

1. 找到它，将其 **名称单独一行** 写入 `~/answers/q6.txt`。
2. **删除** 该绑定。不要动默认的 `cluster-admin` 绑定（主体为 `system:masters`）。

```bash
kubectl get clusterrolebindings -o wide | grep cluster-admin
```

> 参考：[RBAC 最佳实践](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)

## 7. Q7（5 分）应用 RuntimeDefault seccomp 配置

命名空间 `sys-hard` 中的 Deployment `runner` 未启用 seccomp。请在 **Pod 安全上下文** 中
添加 `seccompProfile: { type: RuntimeDefault }`，并确保两个 Pod 都重新 Ready。

> 参考：[seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)

## 8. Q8（5 分）移除宿主机访问 —— privileged、hostPID、hostPath

命名空间 `sys-hard` 中的 Deployment `node-tool` 把整个节点都攥在手里：
`privileged: true`、`hostPID: true`、`hostNetwork: true`，以及对 `/` 的 hostPath 挂载。

**移除全部四种宿主机访问**，保持名称、命名空间和镜像不变，并让 Pod 继续处于 Running。

> 参考：[Pod 安全上下文](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 9. Q9（7 分）用 SecurityContext 加固容器

在命名空间 `apps` 中创建 Deployment `secure-app`。

- 镜像 `busybox:1.36`，长时间运行的命令（例如 `sleep 86400`），副本数 1
- 容器安全上下文：

| 项目 | 值 |
|---|---|
| `runAsNonRoot` | `true` |
| `runAsUser` | `10001` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |
| `readOnlyRootFilesystem` | `true` |

Pod 必须 Ready 才算通过。

> 参考：[SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 10. Q10（7 分）Pod Security Admission —— 强制 restricted

命名空间 `restricted-ns` 中有一个以 `privileged` 运行的 Deployment `legacy`。

1. 给命名空间打标签以 **强制 `restricted` 配置**
   （`pod-security.kubernetes.io/enforce=restricted`）
2. **修改 Deployment `legacy` 使其满足 restricted 标准**，让新 Pod 能正常启动
   （去掉 privileged，设置 `runAsNonRoot`、`allowPrivilegeEscalation: false`、
   `capabilities.drop: ["ALL"]`、`seccompProfile: RuntimeDefault` —— busybox 还需要
   指定 `runAsUser` 才能起来）

只打标签会 **保留已有的旧 Pod** —— 必须修改 Deployment 并滚动出新 Pod，新 Pod 才能通过准入审查。

> 参考：[Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) ·
> [用命名空间标签强制标准](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

## 11. Q11（6 分）操作 Secret —— 提取、创建、挂载

围绕命名空间 `apps` 中的 Secret `db-creds` 进行操作。

1. **解码 `db-creds` 的 `password` 值**，将其单独一行写入 `~/answers/q11.txt`。
2. 在 `apps` 中创建一个新的 Secret `api-token` —— 键 `token`，值 `cks-2026`
3. Pod `secret-user`（`apps`，`busybox:1.36`，长时间运行）—— 将 `db-creds` 以
   **只读卷** 的形式挂载到 `/etc/creds` 并处于 Running

> 参考：[Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 12. Q12（7 分）修复 Dockerfile 中的安全缺陷

`~/work/audit/Dockerfile` 带着安全缺陷被提交上来审查。**请直接修改该文件。**

1. 基础镜像用的是 `latest` —— **固定为 `nginx:1.26`**。
2. 凭据被硬编码进镜像（`ENV API_KEY=…`）—— **删除该行**。
3. 结尾是 `USER root` —— 改为以 **`nginx` 用户** 运行。

其余行（COPY、CMD 等）必须保留。评分依据文件内容。

> 参考：[Dockerfile 最佳实践](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)

## 13. Q13（7 分）识别并隔离有漏洞的镜像

命名空间 `supply` 中运行着 Deployment `frontend-app`、`report-app` 和 `batch-app`。
它们镜像的漏洞扫描报告已准备在 `~/work/scans/` 中
（真实考试中你要自己运行 `trivy image`）。

1. 阅读报告，找出所有镜像存在 **CRITICAL** 漏洞的 Deployment。
2. 将这些 Deployment 名称写入 `~/answers/q13.txt`，**每行一个**。
3. **将这些 Deployment 缩放到 0 副本** 以隔离它们。
   不要动没有漏洞的工作负载。

> 参考：[供应链安全](https://kubernetes.io/docs/concepts/security/supply-chain-security/)

## 14. Q14（6 分）用摘要固定镜像

标签可能被重新推送而悄悄替换。请修改命名空间 `supply` 中的 Deployment `pinned`，
让它 **以摘要而非标签** 引用 `nginx:1.26`（`nginx@sha256:<64 位十六进制>`）。Pod 必须保持 Ready。

可以从正在运行的 Pod 上读取摘要：

```bash
kubectl get pod -n supply -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
```

> 参考：[镜像摘要](https://kubernetes.io/docs/concepts/containers/images/#image-names)

## 15. Q15（8 分）配置 API Server 审计日志（audit logging）

在 API Server 上启用审计日志。k3s 通过 `/etc/rancher/k3s/config.yaml` 中的
`kube-apiserver-arg` 传递 apiserver 标志。

1. 审计策略 `/var/lib/rancher/k3s/server/audit-policy.yaml` ——
   将 **`secrets` 资源以 `Metadata` 级别** 记录，其余一律不记录（`None`）
2. apiserver 参数 —— `audit-policy-file=<上述路径>`、
   `audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log`、
   `audit-log-maxage=7`、`audit-log-maxbackup=2`
3. 创建日志目录，并用 `sudo systemctl restart k3s` 使配置生效。
   重启后，**务必用 `kubectl get nodes` 确认集群正常** ——
   参数写错会导致 apiserver 起不来，从而连带阻塞其他题目的评分。

评分会先查询一次 Secret，然后检查审计日志中是否留下了对应记录。

> 参考：[审计（Auditing）](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)

## 16. Q16（12 分）运行时取证 —— 找出并隔离被攻陷的 Pod

安全团队在命名空间 `runtime` 中检测到 **疑似加密货币挖矿的通信**。
其工作负载有三个：`web`、`metrics`、`logshipper`。

1. **检查每个 Pod 中正在运行的进程**（`kubectl exec <pod> -- ps` 或
   `crictl`），找出被攻陷的那个。可以看到矿池地址、`xmrig` 之类的痕迹。
2. 将管理该被攻陷 Pod 的 **Deployment 名称单独一行** 写入 `~/answers/q16.txt`。
3. **将该 Deployment 缩放到 0 副本** 以隔离它。
   其余两个工作负载必须继续处于 Running。

> 参考：[安全检查清单](https://kubernetes.io/docs/concepts/security/security-checklist/)
