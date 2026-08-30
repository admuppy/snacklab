# 解析

提交后，只有没拿到满分的题目才会显示下面的解析。
正确答案不止一种 —— 评分看的是「结果是否符合要求」，以下只是最简洁的参考答案。

## Q1 Sidecar 容器 —— 日志流式输出

一个 Pod、两个容器、一个 emptyDir。关键在于 **两个容器把同一个卷挂载到同一路径**。

```yaml
apiVersion: v1
kind: Pod
metadata: { name: logger, namespace: dev }
spec:
  volumes: [{ name: logs, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: streamer
      image: busybox:1.36
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

常见错误

- 漏掉 sidecar 的 volumeMount，`tail` 连一个空文件都找不到 —— 日志评分项（2 分）就没了。
- `tail -F`（大写）会等待文件出现；`-f` 在文件尚不存在时直接退出，可能让容器进入 CrashLoop。
- 评分会检查 `kubectl logs logger -c streamer` 中是否真的流出 `tick` ——
  结构正确但命令写错，这一项照样得不到分。

## Q2 Job 与 CronJob

用命令式创建 Job，再在 YAML 中补上 completions/parallelism —— 这样更快。

```bash
kubectl create job pi -n batch --image=busybox:1.36 --dry-run=client -o yaml -- sh -c "echo 3.14159" > job.yaml
# add completions: 3 and parallelism: 2 under spec:, then
kubectl apply -f job.yaml
kubectl create cronjob cleanup -n batch --image=busybox:1.36 --schedule="0 3 * * *" \
  --dry-run=client -o yaml -- sh -c "echo cleaned" > cj.yaml
# add concurrencyPolicy: Forbid and successfulJobsHistoryLimit: 1 under spec:, then
kubectl apply -f cj.yaml
```

常见错误

- `completions`/`parallelism` 位于 **Job 的 spec** 中，不在 template.spec 中。
- CronJob 的 `concurrencyPolicy` 和 `successfulJobsHistoryLimit` 同样位于
  **CronJob spec** 层级（不是 jobTemplate.spec）。
- 漏写 `restartPolicy: Never` 会让 Job 创建直接失败（没有默认值）。

## Q3 用 init 容器准备内容

主容器只有在 init 容器结束之后才会启动。通过 emptyDir 把准备好的文件交接过去。

```yaml
spec:
  volumes: [{ name: web, emptyDir: {} }]
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo ready-to-serve > /work/index.html"]
      volumeMounts: [{ name: web, mountPath: /work }]
  containers:
    - name: web
      image: nginx:1.26
      volumeMounts: [{ name: web, mountPath: /usr/share/nginx/html }]
```

常见错误

- 主容器的挂载路径不是 nginx 的文档根目录（`/usr/share/nginx/html`）的话，
  HTTP 评分项（2 分）会失败。
- 卷名不一致意味着 init 容器写的文件永远到不了主容器。

## Q4 滚动更新 —— 零停机策略

先改策略，再换镜像。顺序反了的话，第一次滚动更新会按默认策略（25%）执行。

```bash
kubectl patch deploy api -n prod --type merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image deploy/api -n prod api=nginx:1.26
kubectl rollout status deploy/api -n prod
```

常见错误

- 用 `kubectl edit` 也完全可以 —— 评分只读取字段值。
- `maxUnavailable: 0` 和 `maxSurge: 0` 同时设置会让滚动更新永远死锁。
- 提交前用 `rollout status` 确认已完成，否则「两个副本都以新版本 Ready」
  这一项（2 分）可能还没达成。

## Q5 金丝雀发布 —— 25% 流量

不要动 Service 的选择器（`app: shop`）；再建一个 **app 标签相同、track 标签不同**
的 Deployment，这就是基于标签的金丝雀的全部。

```bash
kubectl create deploy shop-canary -n prod --image=nginx:1.26 --replicas=1 --dry-run=client -o yaml > canary.yaml
# fix the pod template labels to app: shop, track: canary (and the selector to match), then apply
kubectl scale deploy shop -n prod --replicas=3
```

常见错误

- `kubectl create deploy` 生成的标签是 `app: shop-canary` —— **必须改成
  `app: shop`**，否则 Service 永远选不中金丝雀（2 分的 endpoint 项就卡在这里）。
- selector 和 template 标签不一致时，apply 本身就会被拒绝。
- 忘记把 stable 缩到 3，比例会是 4:1 —— 那不是 25%。

## Q6 Kustomize overlay

一个引用回 base 的 kustomization.yaml 就是一个完整的 overlay。

```yaml
# ~/work/kustomize/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources: [../../base]
replicas: [{ name: hello-web, count: 2 }]
images: [{ name: nginx, newTag: "1.26" }]
```

```bash
kubectl apply -k ~/work/kustomize/overlays/prod
```

常见错误

- `resources` 中的相对路径 **相对于 overlay 目录**（`../../base`）。
- `images.name` 是 base 使用的 **镜像名**（nginx），不是容器名（web）。
- `newTag` 是字符串 —— 加引号（`"1.26"`）是稳妥的习惯。
- 文件写好却忘了 `apply -k`，会丢掉全部 5 分的集群评分项。

## Q7 探针 —— 自愈与流量门控

把题目中的数字原样照抄。探针是容器级字段。

```yaml
containers:
  - name: web
    image: nginx:1.26
    readinessProbe:
      httpGet: { path: /, port: 80 }
      initialDelaySeconds: 3
      periodSeconds: 5
    livenessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 10
```

常见错误

- readiness 和 liveness 两个块长得很像，容易写反 —— 它们是分开评分的。
- 端口写错（比如 8080）会同时丢掉规格项和 Ready 项（1 分）。

## Q8 故障排查 —— CrashLoopBackOff

先调查（保存日志），再修复（替换命令）—— 按这个顺序。

```bash
kubectl logs deploy/orders -n broken > ~/answers/q8.txt 2>&1   # captures "not found"
kubectl patch deploy orders -n broken --type json -p \
  '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","while true; do date; sleep 5; done"]}]'
```

常见错误

- 处于 CrashLoop 的 Pod 即使不加 `--previous` 也会显示上一次运行的输出。
  如果是空的，就用 `kubectl logs <pod> -n broken --previous`。
- 答案文件必须是 **包含错误信息的实际输出** —— 手写的总结不算数。
- 用 `kubectl edit deploy orders -n broken` 修复命令同样有效。

## Q9 修复已移除的 API 版本

`apps/v1beta1` 和 `batch/v1beta1` 早已被移除。当前版本是 `apps/v1` 和 `batch/v1`。

```bash
sed -i -e 's|apps/v1beta1|apps/v1|' -e 's|batch/v1beta1|batch/v1|' ~/work/legacy/stack.yaml
kubectl apply -f ~/work/legacy/stack.yaml
```

常见错误

- 不确定当前版本？`kubectl api-resources | grep -i cronjob` 或
  `kubectl explain cronjob` 会打印实际的 group/version。
- **文件本身** 也会被评分（2 分）—— 在别处另写一份 YAML 而不改原文件，会丢掉这一项。
- 应用后确认 report-api 已 Ready，否则最后一分可能溜走。

## Q10 使用 ConfigMap 与 Secret

创建用两行命令式，消费用 YAML。

```bash
kubectl create configmap app-config -n dev --from-literal=mode=production --from-literal=timeout=30
kubectl create secret generic db-cred -n dev --from-literal=user=admin --from-literal=pass=S3cret1
```

```yaml
spec:
  volumes: [{ name: creds, secret: { secretName: db-cred } }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef: { name: app-config, key: mode }
      volumeMounts: [{ name: creds, mountPath: /etc/creds, readOnly: true }]
```

常见错误

- 直接写字面量 `env: [{name: APP_MODE, value: production}]` **不算数** ——
  评分检查的是 `configMapKeyRef` 引用。
- Secret 卷会变成每个键一个文件（`/etc/creds/user`、`/etc/creds/pass`）。
- Pod 建好之后再改 ConfigMap 不会更新环境变量 —— 如果填错了值，请重建 Pod。

## Q11 SecurityContext —— 非 root、只读

runAsUser/runAsNonRoot 可以放在 Pod 级；其余三项是 **容器级** 字段。

```yaml
spec:
  securityContext: { runAsUser: 1000, runAsNonRoot: true }
  volumes: [{ name: tmp, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      volumeMounts: [{ name: tmp, mountPath: /tmp }]
```

常见错误

- 把 `allowPrivilegeEscalation`、`readOnlyRootFilesystem` 和 `capabilities` 写在 Pod 级
  是 **schema 错误** —— 它们只存在于容器的 securityContext 中。
- 根文件系统只读时，有些镜像没有可写空间就无法启动 —— `/tmp` 的 emptyDir 就是为此准备的。
- 验证 uid 是否真的生效：`kubectl exec secure-app -n dev -- id -u`。

## Q12 ServiceAccount 与令牌自动挂载

```bash
kubectl create serviceaccount app-sa -n dev
```

```yaml
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
```

常见错误

- `automountServiceAccountToken` 是 **Pod spec 级** 字段（不在容器下面）。
- 设在 SA 上效果相同，但题目要求「在 Pod spec 中关闭」，
  所以规格评分项（1 分）要求它出现在 Pod 上。
- 用 `kubectl exec sa-pod -n dev -- ls /var/run/secrets/kubernetes.io/serviceaccount`
  验证 —— 出现「No such file or directory」才是正确状态。

## Q13 资源请求与上限 —— 在配额之内

```bash
kubectl create deploy worker -n batch --image=busybox:1.36 --replicas=2 --dry-run=client -o yaml > worker.yaml
# fill in command and resources, then apply
```

```yaml
resources:
  requests: { cpu: 100m, memory: 64Mi }
  limits: { cpu: 200m, memory: 128Mi }
```

常见错误

- **这道题存在的意义**：在带 ResourceQuota 的命名空间中，没有 requests 的 Pod
  会被直接拒绝。Deployment 能建出来，但 Pod 数是 0 ——
  `kubectl get events -n batch` 会显示 `failed quota`。
- 使用题目给出的写法：Kubernetes 把 `0.1` 和 `100m` 视为相同，
  但评分比较的是规范化后的字符串（100m），照抄题目的形式最稳妥。

## Q14 Service —— ClusterIP 与 NodePort

```bash
kubectl expose deploy frontend -n prod --name=frontend-svc --port=80 --target-port=80
kubectl expose deploy frontend -n prod --name=frontend-np --port=80 --target-port=80 --type=NodePort \
  --dry-run=client -o yaml > np.yaml
# add nodePort: 30080 to ports[0], then apply
```

常见错误

- `expose` 无法指定 nodePort 的值 —— 在 dry-run 生成的 YAML 中手动加上
  `nodePort: 30080`。
- 手写的选择器不是 `app: frontend` 会让 endpoint 为空，3 分的流量评分项也随之全丢。
- 集群内验证：`kubectl exec client -n dev -- wget -qO- http://frontend-svc.prod.svc.cluster.local`。

## Q15 编写 Ingress 资源

没有控制器 —— 资源定义仍要写完整。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: frontend-svc, port: { number: 80 } } }
          - path: /shop
            pathType: Prefix
            backend: { service: { name: shop-svc, port: { number: 80 } } }
```

常见错误

- `pathType` 是必填字段 —— 漏写会被拒绝。题目指定了 Prefix。
- 把 `port: { number: 80 }` 简写成 `port: 80` 是 schema 错误。
- 两条路径都属于 **同一条 host 规则**。拆成两个 host 条目也能得分，
  但单条规则才是标准写法。

## Q16 NetworkPolicy —— 仅放行指定客户端

先选中目标 Pod（podSelector，不是 from），再在 from 下列出被放行的来源。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: cache-guard, namespace: dev }
spec:
  podSelector:
    matchLabels: { app: cache }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: client }
      ports:
        - { protocol: TCP, port: 80 }
```

常见错误

- 把 `podSelector`（目标）和 `from.podSelector`（放行来源）写反，
  得到的是完全相反的策略。
- 对被选中的 Pod，NetworkPolicy 会 **阻断一切未被显式允许的流量** ——
  不需要另写拒绝规则。
- 本集群真的会执行策略（kube-router）。提交前确认
  `kubectl exec intruder -n dev -- wget -T2 -qO- http://<cache IP>` **失败**。
