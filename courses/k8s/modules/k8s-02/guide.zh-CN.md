# Service 与集群网络

Pod 随时可能挂掉,并以新的 IP 重新启动。**Service** 通过标签选择一组 Pod,为它们提供稳定的
虚拟 IP、DNS 名称和负载均衡。本实验把已经在运行的 Deployment `web`(标签 `app=web`,2 个副本)
通过三种 Service 类型暴露出来。

查看 Deployment:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — 确认要暴露的 Deployment 存在,且 Pod 全部 `READY`。

查看后端 Pod:

```bash
kubectl get pods -l app=web -o wide     # 查看后端 Pod 的 IP
```

- `-l app=web` — 用 Service 选择器将要使用的同一个标签来查询 Pod。
- `-o wide` — 会显示 Pod IP 列,稍后可与 Service 的端点对比。

> 参考: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. 用 ClusterIP 暴露

默认类型 **ClusterIP** 会创建一个只能在集群内部访问的虚拟 IP。Service 名为 `web`,端口 80。

创建 Service:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — 直接沿用 Deployment 的 Pod 选择器(`app=web`)创建 Service。
- `--name=web` — 要创建的 Service 名称,这个名称同时也是 DNS 名。
- `--port=80` — Service 接收的端口,`--target-port=80` — 流量转发到的容器端口。
- 省略 `--type` 时默认为 `ClusterIP`。

查看 Service:

```bash
kubectl get svc web
```

- `svc` 是 `service` 的缩写。`CLUSTER-IP` 列是只在集群内部使用的虚拟 IP。

查看端点:

```bash
kubectl get endpoints web           # 选择器选中的 Pod IP:端口列表
```

- `endpoints` — Service 实际发送流量的后端(Pod IP:端口)列表。只有匹配选择器且 **Ready** 的 Pod 才会列入。

从集群内部测试访问:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — 启动一个用完即弃的测试 Pod `t`。
- `--restart=Never --rm -it` — 不重启、只运行一次,连接终端(`-it`)查看结果,结束后删除 Pod(`--rm`)。
- `--` 之后是要在容器内执行的命令。行尾的 `\` 表示命令延续到下一行。
- `wget -qO- <URL>` — 安静地(`-q`)获取内容,输出到标准输出(`-O-`)而不是文件。
- `web.default.svc.cluster.local` — `<服务>.<命名空间>.svc.cluster.local` 形式的 Service DNS 名。

`kubectl get endpoints web` 中出现 Pod IP,说明路由已建立。若端点为空,则是选择器(`app=web`)
与 Pod 标签不匹配。

## 2. 用 NodePort 对外暴露

**NodePort** 会在所有节点上开放一个固定端口(默认 30000–32767),使集群外部也能访问。
创建 Service `web-np`。

创建 NodePort Service:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — 在 ClusterIP 的基础上,再在 **所有节点的同一个端口**(从 30000–32767 中自动分配)上开放,供集群外部访问。
- `--name=web-np` — 换一个名字,避免与前面的 `web` Service 冲突。

查看分配的端口:

```bash
kubectl get svc web-np                          # PORT(S) 列中的 80:3xxxx/TCP
```

- `PORT(S)` 中的 `80:3xxxx/TCP` — 前面是 Service 端口,后面是在节点上开放的 nodePort。

把 nodePort 存入变量:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — 命令替换,把括号内命令的输出存入 shell 变量 `np`。
- `{.spec.ports[0].nodePort}` — 只取出第一个端口项 nodePort 值的 JSONPath。

在节点上直接访问:

```bash
curl -s http://127.0.0.1:$np | head -1          # 在节点(即本 Pod)上直接访问
```

- `curl -s` — 不显示进度(silent)地发送 HTTP 请求。`$np` 会替换为前面保存的 nodePort。
- `127.0.0.1` — 在本实验中终端本身就是节点,所以用节点自己的地址访问。
- `| head -1` — 只看响应的第一行。

像 `80:3xxxx/TCP` 这样分配了 nodePort,且 curl 返回 nginx 响应,即为成功。

## 3. Headless Service 与 DNS

`clusterIP: None` 的 **Headless Service** 没有虚拟 IP 和代理,DNS 查询会直接把
**每个 Pod 的 IP** 作为 A 记录返回。常用于 StatefulSet 中按 Pod 访问等场景。

创建 Headless Service:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: web-h, namespace: default }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行为止的 YAML 通过标准输入交给 kubectl 应用。`-f -` 表示"从 stdin 读取而不是文件",加引号的 `'EOF'` 可防止 shell 替换正文中的 `$`。
- `clusterIP: None` — 声明不创建虚拟 IP 的 Headless Service。`selector` 选中的 Pod IP 会直接登记到 DNS。

查看 CLUSTER-IP:

```bash
kubectl get svc web-h                 # CLUSTER-IP 为 None
```

- `CLUSTER-IP` 为 `None` 即表示 Headless,不参与 kube-proxy 的负载均衡。

测试 DNS 查询:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # Pod 有几个就有几条 A 记录
```

- `kubectl run t --image=busybox:1.36` — 启动一个用完即弃的测试 Pod `t`。
- `--restart=Never --rm -it` — 不重启、只运行一次,连接终端(`-it`)查看结果,结束后删除 Pod(`--rm`)。
- `--` 之后是要在容器内执行的命令。行尾的 `\` 表示命令延续到下一行。
- `nslookup <名称>` — 向 DNS 查询名称并输出 A 记录(IP)。Headless 会返回与 Pod 数量相同的 IP。

`CLUSTER-IP` 为 `None`,且 nslookup 返回与 Pod 数量相同的 IP,即为成功。

> 参考: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
