# 综合 —— 救活出故障的部署

两个电商应用(`shop`、`cart`)已经部署,但 **什么都没跑起来。** 三处埋着不同的故障。
这个综合实战不是学习新概念,而是训练你用学过的诊断工具 —`kubectl get`、`describe`、`logs`、
`get events`— **自己找到原因并修复**。

先从整体看起:

纵览所有资源:

```bash
kubectl get deploy,pods,svc
```

- 用逗号分隔,一次查询多种资源。同时查看 Deployment 的 `READY`、Pod 的 `STATUS` 和 Service 列表,找出异常之处。

查看最近事件:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — 命名空间中发生的事件(调度、镜像拉取、失败等)。
- `--sort-by=.lastTimestamp` — 按最后发生时间排序,`| tail -20` — 只看最近 20 行。

> 参考: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. 修复镜像拉取失败

`shop` 的 Pod 处于 `ImagePullBackOff`/`ErrImagePull`。找出原因。

查看 shop Pod 状态:

```bash
kubectl get pods -l app=shop
```

- `STATUS` 列的 `ImagePullBackOff`/`ErrImagePull` — 节点无法拉取镜像,正在逐步拉长重试间隔等待。

从事件中找原因:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # 能看到 "not found" 的标签
```

- `describe` 最下方的 `Events` 最直接地说明了失败原因。用 `grep -A5 -i events` 只看这一部分。

查看当前镜像标签:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — Deployment 创建 Pod 时使用的镜像名:标签。

问题在于镜像标签不存在。改成有效的标签:

更换镜像标签:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — 替换名为 `web` 的容器的镜像。模板改变,新的 Pod 会被发布。

等待发布完成:

```bash
kubectl rollout status deploy/shop
```

- 等到新 Pod 全部 Ready。如果一直不结束,按 `Ctrl+C` 后再用 `describe` 查看原因。

`shop` 变为 2/2 Ready,① 就解决了。

## 2. 修复 Service 选择器

Pod 已经起来了,但 Service `shop` 无法转发流量。看看端点是否为空。

查看端点:

```bash
kubectl get endpoints shop            # <none> — 没有任何 Pod 关联
```

- `ENDPOINTS` 为 `<none>`,说明没有任何 Ready 的 Pod 匹配 Service 的选择器。

查看 Service 选择器:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX(拼写错误)
```

- `{.spec.selector}` — 以 JSON 查看 Service 选择 Pod 所用的标签条件。

查看 Pod 的实际标签:

```bash
kubectl get pods -l app=shop --show-labels                  # 实际标签是 app=shop
```

- `--show-labels` — 用 `LABELS` 列显示每个 Pod 上的全部标签。与选择器逐字比对一下。

Service 选择器与 Pod 标签不匹配。修正选择器:

修改选择器:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — 就地修改资源的部分字段。
- `--type=merge` — 把 `-p` 给出的 JSON 合并到现有对象中(JSON merge patch)。
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — 只写要改的部分的补丁。用单引号括起来,避免 shell 解释。

再次查看端点:

```bash
kubectl get endpoints shop            # 现在填入了 Pod IP
```

端点被填上,② 就解决了。

## 3. 修复缺失的 ConfigMap

`cart` 的 Pod 卡在 `CreateContainerConfigError`。看看原因。

查看 cart Pod 状态:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — 镜像已拉取,但无法生成容器配置(引用的 ConfigMap/Secret 等)。

从事件中找原因:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- 在 Events 中可以看到缺失的是哪个对象(`configmap "cart-config" not found`),连名称都有。

查看引用的 envFrom:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — 容器整体导入为环境变量的 ConfigMap/Secret 引用列表。

它引用了不存在的 ConfigMap `cart-config`。创建它之后,kubelet 就会正常启动 Pod:

创建 ConfigMap:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- 给两次 `--from-literal=键=值`,创建含两个键的 ConfigMap。创建后 kubelet 会在重试中启动容器。

等待发布完成:

```bash
kubectl rollout status deploy/cart
```

`cart` 变为 1/1 Ready,③ 就解决了 — 三处故障全部修复。

```bash
kubectl get deploy,svc,endpoints      # 最终确认
```

- 一次性查看 Deployment 的 READY、Service 和端点,确认三处故障都已修复。
