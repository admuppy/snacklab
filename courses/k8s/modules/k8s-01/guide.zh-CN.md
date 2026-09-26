# Deployment 与滚动发布

**Deployment** 是一种工作负载:你声明一组 Pod 的期望状态(副本数、镜像),控制器就会让集群收敛到该状态,
并在镜像变更时管理 **零停机滚动更新** 和 **回滚**。

本实验在 Pod 内运行的 **你专属的单节点 k3s 集群** 中进行。终端里可以直接使用 `kubectl`
(已配置 `k` 别名和自动补全),`KUBECONFIG` 也已设置好。

查看节点:

```bash
kubectl get nodes          # 1 个 Ready 节点
```

- `kubectl get <资源>` — 以表格形式列出资源,是最基本的查询命令。
- `nodes` — 加入集群的机器。`STATUS` 必须是 `Ready`,Pod 才能调度到上面。

查看当前上下文:

```bash
kubectl config current-context
```

- `kubectl config` — 操作 kubeconfig 文件(要连接的集群和用户信息)的子命令。
- `current-context` — 输出 kubectl 当前发送命令所用的上下文(集群 + 用户 + 命名空间的组合)名称。

> 参考: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. 创建 Deployment(3 个副本)

用 `nginx:1.25` 镜像创建一个 3 副本的 Deployment `web`。

创建 Deployment:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — 不写 YAML,以命令式方式创建 `web` Deployment。Pod 会自动带上 `app=web` 标签。
- `--image=nginx:1.25` — Pod 模板的容器镜像(`名称:标签`)。
- `--replicas=3` — 始终保持的 Pod 数量(`spec.replicas`)。

等待发布完成:

```bash
kubectl rollout status deploy/web            # 等到全部 Ready
```

- `kubectl rollout status` — 等待发布完成(新 Pod 全部 Ready),并输出进度。
- `deploy/web` — `<类型>/<名称>` 形式的资源指定。`deploy` 是 `deployment` 的缩写。

查看 Deployment 状态:

```bash
kubectl get deploy web
```

- `READY` — 就绪/期望的 Pod 数,`UP-TO-DATE` — 用最新模板创建的 Pod 数,`AVAILABLE` — 可对外服务的 Pod 数。

查看 Pod 列表:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — 标签选择器,只选出带 `app=web` 标签的 Pod。
- `-o wide` — 额外显示 Pod IP、所在节点等列。

`kubectl get deploy web` 的 `READY` 列显示 `3/3` 即为成功。也可以用 `kubectl get rs`
确认 ReplicaSet 是否创建了 3 个 Pod。

## 2. 滚动更新

把镜像升级到 `nginx:1.26`。Deployment 会创建新的 ReplicaSet,每次替换几个 Pod
(默认 `maxUnavailable=25%`、`maxSurge=25%`),在不中断服务的情况下完成更新。

更换镜像:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # 更换所有容器的镜像
```

- `kubectl set image deploy/web <容器>=<镜像>` — 只修改 Pod 模板中的镜像。模板一变就会开始新的发布。
- `'*=nginx:1.26'` — `*` 表示所有容器。用单引号包起来,防止 shell 把 `*` 展开成文件名。

等待发布完成:

```bash
kubectl rollout status deploy/web             # 等待发布完成
```

通过事件查看替换过程:

```bash
kubectl describe deploy web | grep -A2 Events # 通过事件查看替换过程
```

- `kubectl describe` — 以便于阅读的形式输出资源的详细信息和最近事件。
- `| grep -A2 Events` — 只看输出中的 `Events` 行及其后(After)2 行,可以看到新旧 ReplicaSet 的扩缩记录。

查看 ReplicaSet:

```bash
kubectl get rs                                # 新旧 ReplicaSet 并存 → 只有新的是 3 个
```

- `rs` — ReplicaSet 的缩写。每次镜像(模板)变更,Deployment 都会创建新的 ReplicaSet,并把旧的缩到 0,留作回滚之用。

`kubectl rollout status` 输出 `successfully rolled out` 即完成。

> 参考: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. 回滚

假设刚才的发布有问题,**回退到上一个版本(revision)。** Deployment 保存着版本历史,
所以可以立即回滚。

查看版本列表:

```bash
kubectl rollout history deploy/web           # 版本列表
```

- `kubectl rollout history` — 列出 Deployment 保存的版本(模板变更历史)。
- 要查看某个版本的具体内容,加上 `--revision=<N>`。

回滚到上一个版本:

```bash
kubectl rollout undo deploy/web              # 回滚到上一个版本(nginx:1.25)
```

- `kubectl rollout undo` — 发起一次新的发布,回到上一个版本的 Pod 模板。回滚本身也会被记录为一个新版本。

等待发布完成:

```bash
kubectl rollout status deploy/web
```

查看当前镜像:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — 用 JSONPath 表达式只取出需要的字段。`{.spec.template.spec.containers[0].image}` 是第一个容器的镜像。
- `; echo` — jsonpath 输出末尾没有换行,补一个换行以免提示符粘在后面。

镜像回到 `nginx:1.25`、并且多了一个版本,即为成功。要回滚到指定版本,
使用 `kubectl rollout undo deploy/web --to-revision=<N>`。

> 参考: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
