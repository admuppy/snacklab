# CKA 模拟考试 第 1 套（120 分钟 · 17 题 · 100 分）

这是完全按照 Linux Foundation **CKA（Certified Kubernetes Administrator）** 实操考试形式设计的
模拟考试，题目权重与真实考试的各领域一致。

| 领域 | 权重 | 题目 |
|---|---|---|
| 集群架构、安装与配置 | 25 | Q1 Q2 Q3 Q4 Q16 Q17 |
| 工作负载与调度 | 15 | Q5 Q6 Q7 |
| 服务与网络 | 20 | Q8 Q9 Q10 |
| 存储 | 10 | Q11 Q12 |
| 故障排查 | 30 | Q13 Q14 Q15 |

**考试方式**

- 限时 **120 分钟**，剩余时间显示在页面顶部。
- 题目可以 **按任意顺序** 作答，先做有把握的题是真实考场的策略。
  唯一的例外：**Q9 需要 Q5 的 `web` Pod 正在运行**，因为它用真实流量来评分。
- 与真实考试一样，**作答过程中不会给出评分反馈**。全部做完后点击下方的
  **[提交并评分]**，17 道题会被一次性评分（每题都会在真实集群上校验，需要一到两分钟）。
- **按部分给分。** 每道题有多个评分项，满足几项就得几分。
  评分结束后，页面上方会显示总分、各题得分和评分项明细，**下方会附上做错题目的解析**。
- **合格线为 66 分。** 达到即可看到祝贺信息并获得结业徽章（不需要满分）。
- 提交后仍可在剩余时间内继续修改并 **重新评分**，系统记录最高分。
- 题目指定了命名空间时，**必须在该命名空间中** 创建对象。

**考试语言**

真实的 CKA 只提供 **英语、日语和简体中文**。本模拟考试同样支持这三种语言（外加韩语），
如果想用实际参加考试的语言练习，请使用页面顶部的语言选择器。

**环境**

一个运行在 Pod 内的 **单节点 k3s v1.36** 集群，完全属于你。`kubectl`（别名 `k`）和
`KUBECONFIG` 均已配置好，`sudo` 无需密码。可以使用 `jq` 和 `vi`/`nano`。
与真实考试一样，你可以查阅 [Kubernetes 官方文档](https://kubernetes.io/docs/) ——
实际上，从文档中复制 YAML 示例再修改正是考试的标准做法。

```bash
kubectl get nodes       # lab（控制平面）+ worker-1、worker-2（虚拟工作节点）
kubectl get ns          # 已为你准备好 app-prod、ops、broken、maint
```

**与真实考试的差异**（环境限制所致）

- 没有 **kubeadm 集群升级** 类题目。环境基于 k3s，无法复现 kubeadm 流程，该领域需要另行学习。
- **Q16 的 etcd 恢复只评分到离线步骤**（`--data-dir` 恢复）。把运行中的集群切换到恢复数据
  属于 k3s 专有流程，不在考试范围内。
- **worker-1、worker-2 是 KWOK 虚拟工作节点。** 调度、驱逐与 drain 的行为与真实节点完全一致，
  但其上的 Pod 不会运行真实进程（不影响 Q17 的评分）。
- 环境中没有 Ingress 控制器，因此 **Q10 只评分资源定义**（不校验实际路由）。

> 省时技巧：用 `kubectl create ... --dry-run=client -o yaml > q.yaml` 生成骨架再编辑，
> 这是考试中收益最大的习惯。`kubectl explain <资源>.<字段>` 也可以随时使用。

## 1. Q1（5 分）RBAC —— ServiceAccount、Role、RoleBinding

在命名空间 `app-prod` 中，为部署工具创建一个 **只读** 身份。

- ServiceAccount `deploy-bot`
- Role `pod-reader` —— 对 `pods` 和 `deployments`（apps 组）**只允许 `get`、`list`、`watch`**
- RoleBinding `deploy-bot-rb` —— 把该 Role 绑定到 `deploy-bot`

权限只能在 `app-prod` 内生效。如果能列出其他命名空间的 Pod，或者能创建、删除 Pod，都算错。

```bash
kubectl auth can-i list pods -n app-prod --as=system:serviceaccount:app-prod:deploy-bot
```

> 参考：[RBAC 鉴权](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 2. Q2（4 分）批准 CSR 并授予用户权限

新开发者 `dev-user` 的客户端证书签名请求正 **等待批准**。

```bash
kubectl get csr
```

1. **批准** CSR `dev-user`，使证书被签发。
2. 让用户（User）`dev-user` 对 `app-prod` **只有只读权限**：在 `app-prod` 中创建名为
   `dev-user-view` 的 RoleBinding，使用内置 ClusterRole `view`。

绑定 `edit` 或 `admin` 算错。验证：

```bash
kubectl auth can-i list pods   -n app-prod --as=dev-user   # yes
kubectl auth can-i delete pods -n app-prod --as=dev-user   # no
```

> 参考：[证书与 CSR](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)

## 3. Q3（4 分）创建静态 Pod

创建一个由节点 kubelet **直接** 管理的静态 Pod，不要通过 API Server 创建。

- 名称 `ops-static`，命名空间 `default`
- 镜像 `busybox:1.36`，命令要保持运行（例如 `sleep 86400`）

本环境（k3s）的清单目录是：

```bash
ls /var/lib/rancher/k3s/agent/pod-manifests/
```

静态 Pod 会以 **镜像 Pod（mirror pod）** 的形式出现在 API Server 中，名称后面会追加节点名
（`ops-static-<节点名>`）。放好文件后等几秒，再用 `kubectl get pod` 查看。

> 参考：[静态 Pod](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

## 4. Q4（3 分）ResourceQuota 与 LimitRange

限制命名空间 `ops` 的资源用量。

ResourceQuota `ops-quota`：

| 项目 | 值 |
|---|---|
| `pods` | 5 |
| `requests.cpu` | 1 |
| `requests.memory` | 1Gi |

LimitRange `ops-limits`（`type: Container`）：

| 项目 | 值 |
|---|---|
| `defaultRequest.cpu` | 100m |
| `defaultRequest.memory` | 128Mi |
| `default.cpu` | 200m |
| `default.memory` | 256Mi |

请记住：一旦配额限制了 `requests.*`，该命名空间中的 **每个 Pod 都必须声明 requests**，
而 LimitRange 的默认值正是为此而设。

> 参考：[ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/) ·
> [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)

## 5. Q5（6 分）Deployment 与滚动更新策略

在命名空间 `app-prod` 中创建 Deployment `web`。

- 副本数 **3**，镜像 `nginx:1.26`
- 容器 requests 为 `cpu: 50m`、`memory: 64Mi`
- 采用 `RollingUpdate` 策略并做到 **零停机**：`maxSurge: 1`、`maxUnavailable: 0`
- Pod 标签为 `app=web`（后面的题目会用到）

三个副本都必须 Ready。

> 参考：[Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 6. Q6（4 分）部署 DaemonSet

在命名空间 `ops` 中部署 DaemonSet `node-agent`。

- 镜像 `busybox:1.36`，使用长时间运行的命令
- **必须声明 requests**（例如 `cpu: 10m`、`memory: 16Mi`）—— `ops` 有配额限制
- Pod 必须在每个节点上都 Ready

> 参考：[DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)

## 7. Q7（5 分）Sidecar 容器与共享卷

在命名空间 `app-prod` 中创建 Pod `logger`，其中 **两个** 容器共享同一个 `emptyDir` 卷，
并挂载在 **相同路径 `/var/log/app`**。

- 容器 `app` —— 定期向 `/var/log/app/app.log` 追加内容
- 容器 `sidecar` —— 读取同一个文件（例如 `tail -f`）

评分会 **从 sidecar 内部实际读取** 该日志文件。只挂载卷而不写入任何内容不会通过。

> 参考：[日志架构 —— sidecar](https://kubernetes.io/docs/concepts/cluster-administration/logging/#sidecar-container-with-logging-agent)

## 8. Q8（7 分）Service —— ClusterIP 与 NodePort

用两种方式暴露 Q5 的 `web` Pod，两者都在命名空间 `app-prod` 中。

| 名称 | 类型 | 端口 |
|---|---|---|
| `web-svc` | ClusterIP | `80` → 容器 `80` |
| `web-np` | NodePort | `80` → 容器 `80`，nodePort **30080** |

两个 Service 都必须有 **3 个** endpoint，并且在集群内通过 DNS 名称
`web-svc.app-prod.svc.cluster.local` 能真正得到响应。

> 参考：[Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 9. Q9（7 分）用 NetworkPolicy 限制流量

把命名空间 `app-prod` 改为默认拒绝，然后只放行指定的客户端。

1. `default-deny` —— 对 `app-prod` 中的 **所有 Pod** **全面拒绝 Ingress**
   （`podSelector: {}`、`policyTypes: ["Ingress"]`）
2. `allow-client` —— 对 `app=web` 的 Pod，只允许来自带 **`role=client`** 标签的 Pod 的
   **TCP 80** 流量

命名空间中已经有 `client`（`role=client`）和 `intruder`（`role=outsider`）两个 Pod。
评分使用真实流量：`client` 必须能访问 `web`，而 `intruder` 必须被拒绝。

```bash
kubectl exec -n app-prod client   -- wget -T3 -qO- http://<web Pod 的 IP>/
kubectl exec -n app-prod intruder -- wget -T3 -qO- http://<web Pod 的 IP>/   # 应当失败
```

> 参考：[网络策略](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 10. Q10（6 分）编写 Ingress 资源

在命名空间 `app-prod` 中创建 Ingress `web-ing`。

- host `shop.example.com`
- path `/`，`pathType: Prefix`
- 后端为 Service `web-svc` 的 `80` 端口

本环境没有 Ingress 控制器，因此 **只评分资源定义**（不校验实际路由）。

> 参考：[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 11. Q11（5 分）PV/PVC 静态绑定

把一个静态制备的卷挂载到 Pod。

1. PersistentVolume `pv-data` —— 容量 `1Gi`、`ReadWriteOnce`、
   `storageClassName: manual`、hostPath `/mnt/data`
2. PersistentVolumeClaim `pvc-data`（`app-prod`）—— `1Gi`、`ReadWriteOnce`，
   使用相同的 `storageClassName`，从而 **绑定到 `pv-data`**
3. Pod `data-user`（`app-prod`）—— 把该 PVC 挂载到 `/data` 并处于 Running

如果 `storageClassName` 留空，默认 StorageClass 会动态制备另一个卷。那样虽然也是 `Bound`，
但绑定的不是 `pv-data`，算错。

> 参考：[持久卷](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## 12. Q12（5 分）动态制备与写入数据

使用默认 StorageClass **动态制备** 一个卷。

1. PVC `pvc-dyn`（`app-prod`）—— `storageClassName: local-path`、`500Mi`、`ReadWriteOnce`
2. Pod `writer`（`app-prod`）—— 把它挂载到 `/data`，向 `/data/hello.txt` 写入 `cka`，
   并保持运行

`local-path` 是 `WaitForFirstConsumer`，因此 **在有 Pod 使用之前 PVC 会一直是 Pending**，
这是正常现象 —— 请创建 Pod。

```bash
kubectl get sc
```

> 参考：[存储类](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 13. Q13（10 分）故障排查 —— 无法启动的 Deployment

命名空间 `broken` 中的 Deployment `api` **始终无法 Ready**。找出原因并修复。
名称、命名空间和副本数（**2**）都要保持不变。

```bash
kubectl get pods -n broken
kubectl describe pod -n broken <pod>      # 阅读 Events
```

两个 Pod 都必须 Running 且 Ready，并且不能遗留失败的 Pod。

> 参考：[应用故障排查](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 14. Q14（10 分）故障排查 —— 没有 endpoint 的 Service

命名空间 `broken` 中的 Service `cache-svc` 没有任何响应，而其后端 Deployment `cache` 本身是健康的。

```bash
kubectl get endpoints cache-svc -n broken
kubectl get pods -n broken --show-labels
kubectl describe svc cache-svc -n broken
```

**有两处是错的。** 在保持 Service `port` 为 `80` 的前提下修复它，使 endpoint 被填充并能返回真实的
HTTP 响应。

> 参考：[调试 Service](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

## 15. Q15（10 分）故障排查 —— CrashLoopBackOff 与根因报告

命名空间 `broken` 中的 Deployment `worker` 不断以 `CrashLoopBackOff` 重启。

```bash
kubectl logs -n broken deploy/worker
kubectl describe pod -n broken <pod>
```

1. 消除原因，让 Pod **稳定** 运行（重启循环必须停止）。
2. 把出问题的资源写入 `~/answers/q15.txt`，**一行小写，格式为 `<kind>/<name>`**，
   例如 `deployment/foo`。

评分要求容器已经无重启地运行至少 20 秒。刚修好就提交可能仍然不达标，请稍等片刻再提交。

> 参考：[调试 Pod](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

## 16. Q16（6 分）etcd 备份与离线恢复

集群的数据存储是 **内置 etcd**。请使用下面的连接信息操作（证书为 root 所有，需要 `sudo`）。

- 端点：`https://127.0.0.1:2379`
- CA：`/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt`
- 证书：`/var/lib/rancher/k3s/server/tls/etcd/server-client.crt`
- 密钥：`/var/lib/rancher/k3s/server/tls/etcd/server-client.key`

1. 用 `etcdctl` 把快照保存到 **`~/backup/etcd-snap.db`**。
2. 用 `etcdutl` 把该快照 **离线恢复** 到目录 **`~/backup/restored`**
   （使用 `--data-dir`；目标目录事先存在会失败）。

**注意**：把运行中的集群切换到恢复数据不在本考试范围内。执行 `k3s server --cluster-reset`
之类的命令可能会清空其他题目的资源。

> 参考：[运维 etcd 集群](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

## 17. Q17（3 分）排空节点 worker-1 以进行维护

工作节点 `worker-1` 即将停机打内核补丁。命名空间 `maint` 中的 Deployment `payments`
（4 副本）分布在 worker-1 和 worker-2 上。

1. **安全地清空 `worker-1`** —— 保持其不可调度，并忽略 DaemonSet。
2. 操作完成后 `payments` 必须仍然 **4 个副本全部可用**（会迁移到 worker-2）。

```bash
kubectl get pods -n maint -o wide
```

> 参考：[安全地清空一个节点](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
