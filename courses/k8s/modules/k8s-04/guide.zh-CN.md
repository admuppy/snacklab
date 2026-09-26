# 探针与自愈

kubelet 用三种探针监视容器状态。**livenessProbe** 失败时会 **重启** 容器(自愈);
**readinessProbe** 失败时会把 Pod **暂时移出** Service 端点,不再向它发送流量。
(startupProbe 用于保护启动较慢的应用。)

本实验的容器启动时创建 `/tmp/healthy`,并在 **30 秒后删除它。** 两种探针都检查这个文件,
因此 30 秒后 liveness 会失败,你可以观察到自动重启。

> 参考: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. 定义 livenessProbe

应用下面的 Deployment `web`。其 `livenessProbe` 每 5 秒执行一次 `cat /tmp/healthy`,
失败 1 次就重启容器。

应用 Deployment:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `livenessProbe.exec.command` — 在容器内执行该命令,退出码为 0 视为健康(也有 `httpGet`、`tcpSocket` 方式)。
- `initialDelaySeconds` — 首次检查前的等待时间,`periodSeconds` — 检查间隔,`failureThreshold: 1` — 失败 1 次即重启。
- `args` 中的 shell 脚本会在 30 秒后删除 `/tmp/healthy`,故意制造故障。

查看 Pod:

```bash
kubectl get pod -l app=web
```

- `READY` 反映 readiness 结果,`RESTARTS` 是因 liveness 失败而重启的次数。

## 2. 定义 readinessProbe

上面的清单里也包含了 `readinessProbe`。Pod 就绪后显示 `READY 1/1`。

查看 Pod 状态:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — 额外显示 Pod IP、节点、readiness gate 等列。

查看 readiness 探针配置:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — 输出按标签选中的 Pod 的详细信息(含探针配置)。
- `grep -A3 -i readiness` — 忽略大小写(`-i`)匹配 `readiness` 行及其后 3 行。

readiness 探针通过期间 Pod 处于 Ready;失败后(文件被删除之后)会短暂变成 `READY 0/1`,
重启后又回到 Ready。

## 3. 制造故障 → 自动重启

文件在 30 秒后消失,liveness 开始失败。观察 Pod,会看到 `RESTARTS` 增加。

观察 Pod:

```bash
kubectl get pod -l app=web -w        # RESTARTS 从 0 → 1(Ctrl+C 退出)
```

- `-w`(`--watch`)— 不是输出一次就结束,而是每当有变化就输出新的一行。按 `Ctrl+C` 退出。

查看探针事件:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` 是基本正则中的"或"。一次查看探针失败(`Liveness`)、容器终止(`Killing`)、重新启动(`Started`)事件。

`RESTARTS` 达到 1 及以上,说明自愈已经生效。想立即触发的话,也可以用
`kubectl exec deploy/web -- rm -f /tmp/healthy` 删掉文件。

> 参考: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
