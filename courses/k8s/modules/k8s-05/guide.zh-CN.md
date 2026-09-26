# 资源请求、限制与 QoS

为容器设置 **requests**(调度器预留的最小量)和 **limits**(上限 — 超出时 CPU 被限流,
内存会被 OOM Kill)。二者的组合决定 Pod 属于三种 **QoS 类别** 中的哪一种,进而决定节点资源紧张时的
**驱逐(eviction)顺序**:`BestEffort` → `Burstable` → `Guaranteed`,越靠前越先被驱逐。

> 参考: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. Guaranteed QoS 的 Pod

所有容器的 **cpu、memory 的 requests 与 limits 都设为相同值** 时,Pod 为 `Guaranteed`,
是受保护程度最高的类别。

创建 Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `resources.requests` — 调度器在节点上预留的最小量,`limits` — 不可超过的上限。
- `cpu: "250m"` — 毫核单位(1000m = 1 个 CPU),`memory: "64Mi"` — 二进制单位 MiB。
- requests 与 limits 相同即为 `Guaranteed`。

查看 QoS 类别:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — 只取出 Pod status 中记录的 QoS 类别(`Guaranteed`/`Burstable`/`BestEffort`)。

## 2. Burstable QoS 的 Pod

设置了 requests,但 limits 更大(或只设置了一部分)时为 `Burstable`。平时按 requests 使用,
有富余时可以突增(burst)到 limits。

创建 Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF
```

- limits(500m/128Mi)大于 requests(100m/32Mi)→ 平时少量预留,节点有空闲时才用到 limits(`Burstable`)。

查看 QoS 类别:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — 只取出 Pod status 中记录的 QoS 类别(`Guaranteed`/`Burstable`/`BestEffort`)。

> 完全不设置 requests、limits 时为 `BestEffort` — 验证:先 `kubectl run be --image=nginx:1.26`,
> 再 `kubectl get pod be -o jsonpath='{.status.qosClass}'`。

## 3. LimitRange 默认值

**LimitRange** 为命名空间规定默认的 requests/limits,即使开发者忘记设置,Pod 也会有资源上限。
**必须先于 Pod** 创建,默认值才会被注入。

创建 LimitRange:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # limits 默认值
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # requests 默认值
EOF
```

- `kind: LimitRange` — 适用于在此命名空间中创建的容器的资源规则。
- `default` — 未写 limits 的容器会被填入的 limits 默认值,`defaultRequest` — requests 默认值。
- 默认值在 Pod **创建时** 注入,不会追溯到已存在的 Pod。

创建不显式设置 limits 的 Pod — LimitRange 会填入默认值:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <名称> --image=<镜像>` — 不经 Deployment,直接创建一个 Pod。这里故意不设置 resources。

查看注入的 resources:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — 以 JSON 查看第一个容器的整个 resources 块。你没写的值已由 LimitRange 填入。

Pod `defaulted` 的 `resources.limits.memory` 被填为 `128Mi` 即为成功。

> 参考: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
