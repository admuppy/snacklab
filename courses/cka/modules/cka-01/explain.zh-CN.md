# 解析

提交后，只有没拿到满分的题目才会显示下面的解析。
正确答案不止一种 —— 评分看的是「结果是否符合要求」，以下只是最简洁的参考答案。

## Q1 RBAC —— ServiceAccount、Role、RoleBinding

只读身份用命令式三行就能建好。考试时手写 YAML 会浪费时间。

```bash
kubectl create serviceaccount deploy-bot -n app-prod
kubectl create role pod-reader -n app-prod --verb=get,list,watch --resource=pods,deployments.apps
kubectl create rolebinding deploy-bot-rb -n app-prod --role=pod-reader --serviceaccount=app-prod:deploy-bot
```

常见错误

- 只写 `--resource=deployments` 会落到 core API 组，必须写成 `deployments.apps`。
- 用 `ClusterRole`/`ClusterRoleBinding` 会让权限漏到其他命名空间，要扣分。
- `--serviceaccount=` 的格式是 **命名空间:名称**。

评分执行 `kubectl auth can-i --as=system:serviceaccount:app-prod:deploy-bot`，
所以无论规则怎么写，只看 **实际生效的权限**。

## Q2 批准 CSR 并授予用户权限

```bash
kubectl certificate approve dev-user
kubectl create rolebinding dev-user-view -n app-prod --clusterrole=view --user=dev-user
```

常见错误

- 用 `--serviceaccount=` 绑定的是服务账号，而不是 User `dev-user`。必须用 **`--user=`**。
- 绑定 `edit`/`admin` 会连删除权限也给出去，要扣分。只读就是内置 ClusterRole `view`。
- 批准后 `kubectl get csr dev-user -o jsonpath='{.status.certificate}'` 不能为空。
  被拒绝(`deny`)的 CSR 无法撤销，只能重新开始实验。

## Q3 创建静态 Pod

静态 Pod 由 **kubelet 从磁盘上的清单目录** 读取并启动，而不是由 API Server 创建。
k3s 的路径是 `/var/lib/rancher/k3s/agent/pod-manifests/`。

```bash
kubectl run ops-static --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sh -c "sleep 86400" > /tmp/ops-static.yaml
sudo cp /tmp/ops-static.yaml /var/lib/rancher/k3s/agent/pod-manifests/
```

常见错误

- 用 `kubectl apply` 创建的是普通 Pod。评分会检查 `kubernetes.io/config.source=file` 注解。
- 镜像 Pod 的名字会在清单名称后 **追加节点名**（`ops-static-<node>`），保持原样即可。
- 放好文件后 kubelet 需要几秒才会拾取。

## Q4 ResourceQuota 与 LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: ops-quota, namespace: ops }
spec:
  hard:
    pods: "5"
    requests.cpu: "1"
    requests.memory: 1Gi
---
apiVersion: v1
kind: LimitRange
metadata: { name: ops-limits, namespace: ops }
spec:
  limits:
    - type: Container
      defaultRequest: { cpu: 100m, memory: 128Mi }
      default: { cpu: 200m, memory: 256Mi }
```

常见错误

- 写成 `pods: 5` 会解析失败 —— 配额值必须是 **字符串**（`"5"`）。
- LimitRange 中 `default` 是 limit，`defaultRequest` 才是 request，两者很容易写反。
- 条目必须是 `type: Container`（`Pod` 含义不同）。

## Q5 Deployment 与滚动更新策略

先生成骨架，只补 `strategy` 和 `resources.requests`：

```bash
kubectl create deploy web -n app-prod --image=nginx:1.26 --replicas=3 --dry-run=client -o yaml > web.yaml
```

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 50m, memory: 64Mi } }
```

常见错误

- 漏掉 `maxUnavailable: 0` 就会用默认的 25%，要扣分。
- 是 `requests`，不是 `resources.limits`。
- 本题的 `web` Pod 也是 Q8、Q9 的评分对象，先确认 3 个副本都 Ready。

## Q6 部署 DaemonSet

`kubectl create` 无法直接创建 DaemonSet。考场上的标准做法是先生成 Deployment，
再把 `kind` 改掉并删除 `replicas`/`strategy`。

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: ops }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
```

常见错误

- 保留 `replicas` 会被拒绝 —— DaemonSet 没有这个字段。
- busybox 的默认命令会立刻退出并进入 CrashLoop，必须给一个 `sleep` 之类的长驻命令。
- cpu 和 memory 的 requests **两个都要写**。

## Q7 Sidecar 容器与共享卷

关键在于 **两个容器把同一个卷挂载到同一路径**。

```yaml
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "tail -f /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

常见错误

- 建两个卷在 spec 上看着没问题，实际并没有共享。评分会 **真的从 sidecar 读取**
  `/var/log/app/app.log`。
- 容器名称是固定的：`app` 和 `sidecar`。

## Q8 Service —— ClusterIP 与 NodePort

```bash
kubectl expose deploy web -n app-prod --name=web-svc --port=80 --target-port=80
kubectl expose deploy web -n app-prod --name=web-np --type=NodePort --port=80 --target-port=80
kubectl patch svc web-np -n app-prod --type=merge -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'
```

常见错误

- `expose` 无法指定 `nodePort` —— 创建后再 patch，或者直接写 YAML。
- endpoint 为空说明选择器与 Pod 标签（`app=web`）不匹配。
  用 `kubectl get endpoints web-svc -n app-prod` 检查。
- 评分会从 `client` Pod 向 `web-svc.app-prod.svc.cluster.local` 发起真实 HTTP 请求。

## Q9 用 NetworkPolicy 限制流量

需要两个对象 —— 一个默认拒绝，一个显式放行。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: app-prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client, namespace: app-prod }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { role: client } }
      ports: [{ protocol: TCP, port: 80 }]
```

常见错误

- `podSelector: {}` 表示「命名空间内的所有 Pod」—— 留空和不写是两回事。
- 把 `podSelector:` 和 `namespaceSelector:` 放在 **同一个 from 条目里** 是 AND 关系；
  分成两个 `-` 条目才是 OR。
- 评分会验证真实流量：`client` 必须通，`intruder` 必须不通。
  这需要 Q5 的 `web` Pod 处于运行状态。

## Q10 编写 Ingress 资源

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: app-prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
```

常见错误

- `pathType` 是必填字段，缺失会导致对象被拒绝。
- `extensions/v1beta1` 早已被移除，要用 `networking.k8s.io/v1`。
- 后端字段是 `service.name`/`service.port.number`，不是旧版的 `serviceName`/`servicePort`。

## Q11 PV/PVC 静态绑定

静态绑定只有在 PV 与 PVC 的 storageClassName、accessModes 和容量都匹配时才会发生。

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 1Gi }
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  hostPath: { path: /mnt/data, type: DirectoryOrCreate }
```
PVC 也用同样的 `storageClassName: manual`、`ReadWriteOnce` 和 1Gi 创建，再在 Pod 中挂载到 `/data`。

常见错误

- PVC 不写 `storageClassName` 会使用默认存储类（local-path）**动态制备** 另一个卷，
  而不是 pv-data。评分会检查 `spec.volumeName == pv-data`。
- 已经绑错的 PVC 无法修改，只能删除重建。

## Q12 动态制备与写入数据

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-dyn, namespace: app-prod }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources: { requests: { storage: 500Mi } }
```

常见错误

- local-path 是 `WaitForFirstConsumer` —— **没有 Pod 使用之前 Pending 是正常的**，
  只建 PVC 干等 Bound 纯属浪费时间。
- 容量必须写 `500Mi`（不是 `500M`）。
- 评分会读取卷中的 `/data/hello.txt`。可以让 Pod 写入，也可以自己执行
  `kubectl exec writer -- sh -c 'echo cka > /data/hello.txt'`。

## Q13 故障排查 —— 无法启动的 Deployment

```bash
kubectl -n broken describe pod -l app=api | tail -20   # ErrImagePull / InvalidImageName
kubectl -n broken set image deploy/api api=nginx:1.26
kubectl -n broken rollout status deploy/api
```

常见错误

- 先分清是 Pending 还是拉取镜像失败 —— `describe` 的 Events 会告诉你答案。
- 删除后重建 Deployment 也算通过，但 **名称、命名空间和副本数（2）必须保持不变**。
- 旧 ReplicaSet 遗留的失败 Pod 会扣分，用 `rollout status` 确认已收敛。

## Q14 故障排查 —— 没有 endpoint 的 Service

**有两处错误**：选择器和 targetPort。先从 Pod 标签和容器端口查起。

```bash
kubectl -n broken get pod --show-labels
kubectl -n broken get svc cache-svc -o yaml | head -30
kubectl -n broken patch svc cache-svc --type=merge \
  -p '{"spec":{"selector":{"app":"cache"},"ports":[{"port":80,"targetPort":80}]}}'
kubectl -n broken get endpoints cache-svc
```

常见错误

- `port` 是 Service 暴露的端口，`targetPort` 是容器端口。Service 的 80 必须保持为 80。
- 即使 endpoint 填上了，targetPort 错了依然没有响应 —— 评分会发起真实 HTTP 请求。
- 用 `kubectl edit svc` 也行，但考试中 patch 更快、更不容易出错。

## Q15 故障排查 —— CrashLoopBackOff 与根因报告

```bash
kubectl -n broken logs deploy/worker --previous     # 提示找不到配置文件/键
kubectl -n broken describe pod -l app=worker        # 查看挂载的 ConfigMap 键
kubectl -n broken get cm worker-config -o yaml
```

容器期望的键与 ConfigMap 中的键对不上。修好 ConfigMap 后重新滚动更新。

```bash
kubectl -n broken rollout restart deploy/worker
echo "configmap/worker-config" > ~/answers/q15.txt
```

常见错误

- 报告文件 `~/answers/q15.txt` 必须只有一行 **`configmap/worker-config`**
  （忽略大小写和空白）。
- 修改 ConfigMap **不会更新已运行的 Pod**，必须执行 `rollout restart`。
- 评分要求 Pod 已无重启地运行至少 20 秒，刚修好就提交可能仍不达标。

## Q16 etcd 备份与离线恢复

备份用 `etcdctl`，离线恢复用 `etcdutl` —— 与真实考试完全相同的工具。证书为 root 所有，
两条命令都需要 `sudo`。

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  snapshot save ~/backup/etcd-snap.db
sudo etcdutl snapshot restore ~/backup/etcd-snap.db --data-dir ~/backup/restored
sudo etcdutl snapshot status ~/backup/etcd-snap.db   # 养成验证的习惯
```

常见错误

- `--cacert`/`--cert`/`--key` 缺一不可，否则 TLS 握手失败。
- `--data-dir` 已存在时 restore 会拒绝执行 —— 要指定一个全新的目录。
- `etcdctl snapshot restore` 仍可用但已弃用；考试中请用 `etcdutl`。
- 评分会检查快照的 revision 以及恢复目录中的 `member/snap/db` —— 空文件或手工建的目录不得分。

## Q17 排空节点 worker-1 以进行维护

一条命令即可；drain 包含 cordon。

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n maint -o wide   # 4 个 Pod 全部在 worker-2 上 Running 即完成
```

常见错误

- 不加 `--ignore-daemonsets` 时，drain 可能因 DaemonSet Pod 而被拒绝。
- 只 `cordon` 只能阻止新调度，旧 Pod 仍在 —— 驱逐掉才算 drain。
- 之后不要 `uncordon` —— 维护场景要求节点保持不可调度。
