# CKAD 模拟考试 第 1 套（120 分钟 · 16 题 · 100 分）

这是仿照 Linux Foundation **CKAD（Certified Kubernetes Application Developer）** 实操考试设计的
模拟考试，题目权重与真实考试的各领域一致。

| 领域 | 权重 | 题目 |
|---|---|---|
| 应用设计与构建 | 20 | Q1 Q2 Q3 |
| 应用部署 | 20 | Q4 Q5 Q6 |
| 应用可观测性与维护 | 15 | Q7 Q8 Q9 |
| 应用环境、配置与安全 | 25 | Q10 Q11 Q12 Q13 |
| 服务与网络 | 20 | Q14 Q15 Q16 |

**考试方式**

- 限时 **120 分钟**，剩余时间显示在页面顶部。
- 题目可以 **按任意顺序** 作答，先做有把握的题是真实考场的策略。
- 与真实考试一样，**作答过程中不会给出评分反馈**。全部做完后点击下方的
  **[提交并评分]**，16 道题会被一次性评分（每题都会在真实集群上校验，需要一到两分钟）。
- **按部分给分。** 每道题有多个评分项，满足几项就得几分。
  评分结束后，页面上方会显示总分和各题得分明细，**下方会附上做错题目的解析**。
- **合格线为 66 分。** 达到即可看到祝贺信息并获得结业徽章（不需要满分）。
- 提交后仍可在剩余时间内继续修改并 **重新评分**，系统记录最高分。
- 题目指定了命名空间时，**必须在该命名空间中** 创建对象。

**考试语言**

真实的 CKAD 只提供 **英语、日语和简体中文**。本模拟考试同样支持这三种语言（外加韩语），
如果想用实际参加考试的语言练习，请使用页面顶部的语言选择器切换到
**English / 日本語 / 简体中文** 再做一遍。

**环境**

一个运行在 Pod 内的 **单节点 k3s v1.36** 集群，完全属于你。`kubectl`（别名 `k`）和
`KUBECONFIG` 均已配置好，`sudo` 无需密码，可以使用 `jq` 和 `vi`/`nano`。
与真实考试一样，你可以查阅 [Kubernetes 官方文档](https://kubernetes.io/docs/) ——
从文档中找到 YAML 示例再修改正是考试的标准做法。

```bash
kubectl get nodes
kubectl get ns          # 已为你准备好 dev、prod、batch、broken
```

**与真实考试的差异**（环境限制所致）

- **没有 Helm 题目**（环境中没有 helm 二进制）。Kustomize 通过 `kubectl apply -k` 覆盖。
- 环境中没有 Ingress 控制器，因此 **Q15 只评分资源定义**（不校验实际路由）。
- 容器镜像构建（编写 Dockerfile、docker build）需要另行学习。

> 省时技巧：用 `kubectl create ... --dry-run=client -o yaml > q.yaml` 生成骨架再编辑。
> `kubectl explain <资源>.<字段>` 也可以随时使用。

## 1. Q1（7 分）Sidecar 容器 —— 日志流式输出

在命名空间 `dev` 中创建 Pod `logger`，其中两个容器共享一个 **emptyDir 卷 `logs`**。

- 主容器 `app` —— 镜像 `busybox:1.36`，命令：
  `sh -c "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"`
  把卷挂载到 `/var/log/app`。
- Sidecar 容器 `streamer` —— 镜像 `busybox:1.36`，命令：
  `sh -c "tail -F /var/log/app/app.log"`，卷挂载到相同路径。

评分会检查 Pod 的结构（两个容器、共享 emptyDir），以及
**`kubectl logs logger -c streamer` 是否真的输出 `tick` 行**。

> 参考：[Sidecar 容器](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

## 2. Q2（7 分）Job 与 CronJob

在命名空间 `batch` 中：

1. Job `pi` —— 镜像 `busybox:1.36`，命令 `sh -c "echo 3.14159"`，
   **completions 3 · parallelism 2**，`restartPolicy: Never`。三次运行都必须成功。
2. CronJob `cleanup` —— 镜像 `busybox:1.36`，命令 `sh -c "echo cleaned"`，
   调度为 **每天 03:00**（`0 3 * * *`），**concurrencyPolicy Forbid**，
   **successfulJobsHistoryLimit 1**，`restartPolicy: Never`。

评分会检查 Job 的定义、**`status.succeeded` 是否达到 3**，以及
CronJob 的调度和策略字段。

> 参考：[Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) ·
> [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-job/)

## 3. Q3（6 分）用 init 容器准备内容

在命名空间 `dev` 中创建 Pod `web-init`。

- Init 容器 `setup` —— 镜像 `busybox:1.36`，把 emptyDir 卷 `web` 挂载到 `/work`，
  并执行 `sh -c "echo ready-to-serve > /work/index.html"`。
- 主容器 `web` —— 镜像 `nginx:1.26`，把同一个卷挂载到 `/usr/share/nginx/html`。

评分会检查 init 容器的配置，以及 **向 Pod IP 发起 HTTP 请求是否返回
`ready-to-serve`**。

> 参考：[Init 容器](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

## 4. Q4（7 分）滚动更新 —— 零停机策略

命名空间 `prod` 中已准备好 Deployment `api`（nginx:1.25、replicas 2）。

1. 把更新策略设为 **maxSurge 1 · maxUnavailable 0**（零停机条件）。
2. 把容器镜像滚动更新到 **`nginx:1.26`**。
3. 更新必须完成：**两个副本都以新版本 Ready**。

评分会检查策略字段、新镜像，以及滚动更新是否完成（revision 已递增、所有 Pod Ready）。

> 参考：[Deployment —— 更新](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 5. Q5（6 分）金丝雀发布 —— 25% 流量

命名空间 `prod` 中已有 Deployment `shop`（track=stable、replicas 4）和 Service `shop-svc`
（选择器 `app: shop`）。把 **25% 的流量导向新版本的金丝雀**。

1. 创建 Deployment `shop-canary` —— 镜像 **`nginx:1.26`**，replicas **1**，
   Pod 标签为 **`app: shop` + `track: canary`**（这样 Service 也会选中它）。
2. 把现有的 `shop` 缩容到 replicas **3**，使 Service 后面的 Pod 变成
   **3 stable : 1 canary**。

评分会检查金丝雀 Deployment 的定义、Service 的 endpoint 是否包含金丝雀 Pod，
以及 3:1 的比例。

> 参考：[金丝雀部署](https://kubernetes.io/docs/concepts/workloads/management/#canary-deployments)

## 6. Q6（7 分）Kustomize overlay

`~/work/kustomize/base` 中存放着 Deployment `hello-web`（nginx:1.25、replicas 1）的 base。

1. 在 **`~/work/kustomize/overlays/prod`** 中创建一个 overlay。它引用 base，并
   - 把 **命名空间设为 `prod`**，
   - 把 **replicas 设为 2**，
   - 把 **镜像标签改为 `nginx:1.26`**。
2. 用 `kubectl apply -k ~/work/kustomize/overlays/prod` 应用。

评分会检查 overlay 的 kustomization（文件本身），以及 **应用到集群的结果**
（prod 中的 hello-web、replicas 2、nginx:1.26、Ready）。

> 参考：[使用 Kustomize 管理对象](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

## 7. Q7（5 分）探针 —— 自愈与流量门控

在命名空间 `dev` 中创建 Pod `probe-pod`（镜像 `nginx:1.26`），配置两个探针。

- **readinessProbe** —— `httpGet` 路径 `/`、端口 `80`，`initialDelaySeconds: 3`、`periodSeconds: 5`
- **livenessProbe** —— `httpGet` 路径 `/`、端口 `80`，`periodSeconds: 10`

评分会检查两个探针的字段，以及 Pod 是否 **Ready**。

> 参考：[配置探针](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 8. Q8（5 分）故障排查 —— CrashLoopBackOff

命名空间 `broken` 中的 Deployment `orders` 处于 CrashLoopBackOff。

1. 从日志中找出原因，并把 **失败日志（包含错误信息的输出）保存到 `~/answers/q8.txt`**
   （直接重定向 `kubectl logs` 的输出即可）。
2. 把容器命令修复为 `sh -c "while true; do date; sleep 5; done"`，
   使 **Deployment 变为 Available**。

评分会检查答案文件中是否包含真实的错误字符串，以及 Deployment 是否 Available。

> 参考：[调试运行中的 Pod](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

## 9. Q9（5 分）修复已移除的 API 版本

`~/work/legacy/stack.yaml` 来自旧集群，使用了 **已被移除的 apiVersion**，
导致 `kubectl apply` 失败。

1. **把文件中的 apiVersion 修改为本集群支持的版本**（保持 kind、名称和 spec 不变）。
2. 应用修复后的文件，使命名空间 `batch` 中出现 Deployment `report-api` 和 CronJob `report-gen`。

评分会检查两个资源是否存在，以及文件中的 apiVersion 是否正确。

> 参考：[已弃用 API 迁移指南](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

## 10. Q10（7 分）使用 ConfigMap 与 Secret

在命名空间 `dev` 中：

1. ConfigMap `app-config` —— 键 `mode=production`、`timeout=30`。
2. Secret `db-cred` —— 键 `user=admin`、`pass=S3cret1`。
3. Pod `webapp` —— 镜像 `busybox:1.36`，命令 `sh -c "sleep 86400"`。
   - 环境变量 **`APP_MODE`** 从 ConfigMap 的 `mode` 键注入（`configMapKeyRef`）。
   - 把整个 Secret 以只读卷的形式挂载到 **`/etc/creds`**。

评分会检查资源的值，并 **在 Pod 内部** 检查真实的
`APP_MODE=production` 变量和 `/etc/creds/user` 文件内容。

> 参考：[ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 11. Q11（6 分）SecurityContext —— 非 root、只读

在命名空间 `dev` 中创建 Pod `secure-app`。镜像 `busybox:1.36`，
命令 `sh -c "sleep 86400"`，并且：

- `runAsUser: 1000`、`runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- capabilities —— **全部丢弃**（`drop: ["ALL"]`）
- 一个挂载到 `/tmp` 的 emptyDir 卷（只读根文件系统下的可写空间）

评分会检查每个安全字段、Pod 是否 Running，以及它 **是否真的以
uid 1000 运行**（`id -u`）。

> 参考：[Pod SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 12. Q12（6 分）ServiceAccount 与令牌自动挂载

在命名空间 `dev` 中：

1. 创建 ServiceAccount `app-sa`。
2. Pod `sa-pod` —— 镜像 `busybox:1.36`，命令 `sh -c "sleep 86400"`，
   **`serviceAccountName: app-sa`**，并在 Pod spec 中用
   **`automountServiceAccountToken: false`** 关闭令牌自动挂载。

评分会检查 SA、Pod 的 SA 分配，以及 **Pod 内部的令牌目录是否真的不存在**。

> 参考：[为 Pod 配置服务账号](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

## 13. Q13（6 分）资源请求与上限 —— 在配额之内

命名空间 `batch` 中有一个 ResourceQuota `batch-quota`（requests.cpu 1、requests.memory 1Gi）。
创建 Deployment `worker`。

- 镜像 `busybox:1.36`，命令 `sh -c "sleep 86400"`，replicas **2**
- 容器 resources：requests **cpu 100m · memory 64Mi**，limits **cpu 200m · memory 128Mi**

评分会检查 requests/limits 的值，以及 **两个副本是否真的 Ready**
（这道题的意义在于：在带配额的命名空间中，没有声明 requests 的 Pod 会被直接拒绝）。

> 参考：[管理容器资源](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

## 14. Q14（7 分）Service —— ClusterIP 与 NodePort

命名空间 `prod` 中已准备好 Deployment `frontend`（nginx:1.26）。

1. ClusterIP Service **`frontend-svc`** —— port 80 → targetPort 80，选择器 `app: frontend`。
2. NodePort Service **`frontend-np`** —— port 80，**nodePort 30080**，相同的选择器。

评分会检查两个 Service 的类型、端口和选择器、endpoint 是否非空，
以及 **真实流量**（集群内通过 Service DNS 访问、节点的 30080 端口）。

> 参考：[Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 15. Q15（6 分）编写 Ingress 资源

在命名空间 `prod` 中，为主机 **`shop.example.com`** 编写 Ingress **`web-ing`**：

- 路径 **`/`**（Prefix）→ Service `frontend-svc` 的 80 端口
- 路径 **`/shop`**（Prefix）→ Service `shop-svc` 的 80 端口

本环境没有 Ingress 控制器，因此 **只评分资源定义**（不校验实际路由）。

> 参考：[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 16. Q16（7 分）NetworkPolicy —— 仅放行指定客户端

命名空间 `dev` 中已准备好 Pod `cache`（app=cache），以及用于验证的
Pod `client`（role=client）和 `intruder`。

创建 NetworkPolicy **`cache-guard`**。

- 目标：带 **`app: cache`** 标签的 Pod
- 只允许来自带 **`role: client`** 标签的 Pod 的 **TCP 80** ingress 流量（阻断其余一切）

评分会检查策略定义和 **真实流量** —— client → cache 必须通，
intruder → cache 必须被阻断。

> 参考：[NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
