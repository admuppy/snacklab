# NetworkPolicy —— 微隔离

默认情况下,集群中的所有 Pod 都可以相互通信。**NetworkPolicy** 是 Pod 级的防火墙,
针对按标签选出的 Pod,规定允许哪些 **来源(from)/目的地(to)** 的流量。规则是 **允许(allow)列表** —
一旦某个 Pod 被策略"选中",它就只接受被明确允许的流量(其余一律拒绝)。

本实验中已经运行着服务器 `web`(+Service `web`)和客户端 Pod `client`(标签 `app=client`)。
k3s 会真正强制执行 NetworkPolicy。

查看 web Pod:

```bash
kubectl get pod -l app=web -o wide
```

- 用 `-l app=web` 查看服务器 Pod,用 `-o wide` 查看其 IP。NetworkPolicy 也是按这个标签选择 Pod。

查看 client Pod:

```bash
kubectl get pod client -o wide
```

- 客户端 Pod。可以先用 `kubectl get pod client --show-labels` 确认它的 `app=client` 标签 — 第 3 步的允许规则就基于它。

> 参考: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. 确认基本连通性

在没有策略时确认 client 能访问 web,并把结果作为基线记录到 `~/work/baseline.txt`
(用于和第 2、3 步的阻断、放行作对比)。

测试 client → web 连通:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx 响应
```

- `kubectl exec client -- …` — 在 client Pod **内部** 发出请求(使来源成为 client)。
- `wget -q -T 3 -O- http://web` — 以 3 秒超时(`-T 3`)请求 `web` Service,把响应输出到标准输出(`-O-`)。
- `| head -1` — 只看响应的第一行。

创建记录用目录:

```bash
mkdir -p ~/work
```

- `mkdir -p` — 连同中间目录一起创建,已存在也不报错。

保存基线响应:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> 文件` — 把命令的标准输出保存(覆盖)到文件。`kubectl exec` 的输出会回到你的终端这边,所以文件也创建在本地。

查看保存的内容:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <文件>` — 只输出文件的第一行。

出现 nginx HTML 的第一行(`<!DOCTYPE html>`)就说明是通的。

## 2. 默认拒绝(default-deny)

创建一个选中 `web` Pod、但 **不含任何 ingress 规则** 的策略。发往被选中 Pod 的所有入站流量都会被阻断。

创建 default-deny 策略:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `podSelector` — 策略作用的目标 Pod(`app=web`)。空选择器 `{}` 表示命名空间中的所有 Pod。
- `policyTypes: [Ingress]` 却没有 `ingress:` 规则 → 拒绝所有进入被选中 Pod 的流量。

确认已阻断(预期超时):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # 超时(被阻断)
```

- `-t 1` — 只尝试 1 次。被阻断时 3 秒后以 `timed out` 结束(数据包被静默丢弃,没有拒绝响应)。

`wget` 因超时失败,说明策略已经挡住了流量。

## 3. 按来源放行

现在添加一个只允许来自带 `app=client` 标签 Pod 的 80 端口流量的策略。策略是累加的,
所以这条放行会叠加在 default-deny 之上,只有 client 能通过。

创建放行策略:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
```

- `ingress[].from[].podSelector` — 只允许同一命名空间中带 `app=client` 标签的 Pod 作为来源。
- `ports` — 允许的端口/协议(TCP 80)。`from` 与 `ports` 位于同一项内时必须同时满足。
- 策略之间按"或"合并,所以即使有 default-deny,这条放行也会额外生效。

再次测试 client → web:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # 再次成功
```

client → web 恢复连通即为成功。换一个没有 `app=client` 标签的 Pod 来测试,仍会被阻断 —
这就是微分段。

> 参考: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
