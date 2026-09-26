# 网络诊断

"服务连不上"的原因大多是以下四种之一 — **IP 不对、端口没开、绑定错了、名称解析不了。** 本模块将学习按顺序诊断这四种情况的工具(ip、ss、curl、getent)。

实验环境中运行着一个名为 `lab-api` 的 API 服务 — 但已经收到"外部无法连接"的报告。做到最后,你会找出原因并修复它。

## 检查网络接口与 IP

网络诊断的起点是确认 **我是谁**(IP)。如今的标准工具是 `ip`(ifconfig 已经退役)。

查看接口列表:

```
ip link
```

- `ip link` — 显示网络接口(L2)列表及其状态(`UP`/`DOWN`)、MAC 地址、MTU。

查看 IPv4 地址:

```
ip -4 addr show
```

- `ip addr show` — 各接口的 IP 地址。`-4` 只看 IPv4。以 `inet 10.x.x.x/24` 这样的地址/前缀长度(CIDR)形式显示。

查看路由表:

```
ip route
```

- `ip route` — 路由表。`default via <网关>` 这一行是通往外部的默认路由。

容器中通常能看到 `lo`(环回)和 `eth0` 两个接口。适合在脚本中使用的单行提取方法:

把 eth0 输出为一行:

```
ip -4 -o addr show eth0
```

- `-o` — 把一个接口的信息输出为 **一行**(oneline),便于用 `grep`、`awk` 处理。
- `show eth0` — 只看指定的接口。

只提取 CIDR 字段:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

- `awk '{print $4}'` — 只取出按空白分隔的第 4 个字段(`10.x.x.x/24`)。

任务:把 eth0 的 IPv4 地址 **不带 CIDR,只保存地址** 到 `~/work/myip.txt`。`/24` 这样的后缀用 `cut -d/ -f1` 去掉。

只取地址并保存:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

- `cut -d/ -f1` — 以 `/` 为分隔符(`-d`)切分,只取第一个字段(`-f1`)→ 地址部分。
- `> ~/work/myip.txt` — 把结果保存到文件。

查看保存的内容:

```
cat ~/work/myip.txt
```

- 输出保存的地址进行确认。之后的命令会以 `$(cat ~/work/myip.txt)` 的形式复用它。

保存好后点击 **[校验]**。

## 追踪监听套接字

下一个问题:**什么在哪个端口上监听。** 先从 `ss` 的必备组合开始。

| 选项 | 含义 |
|---|---|
| `-l` | 只看监听套接字 |
| `-t` / `-u` | TCP / UDP |
| `-n` | 端口以数字显示(省略服务名转换) |
| `-p` | 显示进程(其他用户的需要 sudo) |

```
sudo ss -ltnp
```

- 上表中的选项组合。结果中的 `Local Address:Port` 告诉你在哪个地址和端口上监听,`users:((…))` 告诉你是哪个进程。

任务:找出 `lab-api.service` 监听的 **端口号**,保存到 `~/work/api-port.txt`。从单元的主 PID 入手也是个好办法。

查看 lab-api 的主 PID:

```
systemctl show -p MainPID --value lab-api
```

- `systemctl show -p MainPID --value <单元>` — 只输出单元主进程的 PID 值。

查找该 PID 的监听套接字:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

- 双引号中的 `$( … )` 也会被替换 → 变成 `grep "pid=1234"`,只留下该 PID 的套接字行。

从 Local Address 列的 `127.0.0.1:端口` 中读出端口即可。保存后点击 **[校验]**。

## 诊断并修复绑定问题

你可能已经在刚才的 ss 输出中注意到了 — lab-api 的 Local Address 是 `127.0.0.1:9090`。它 **只绑定在环回地址上**,所以在这个容器里能用,从外部(其他 Pod、节点)访问就会出现 connection refused。来复现一下。

通过环回地址连接:

```
curl -s http://127.0.0.1:9090/status.json        # 成功
```

- `curl -s <URL>` — 安静地发送请求,只输出响应正文。通过环回地址(`127.0.0.1`)可以连通。

通过容器 IP 连接:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # 失败!
```

- `--max-time 3` — 把整个请求限制在 3 秒内(没有响应就不再等待)。
- `$(cat ~/work/myip.txt)` — 把保存好的容器 IP 嵌入 URL。

同一个进程,结果却取决于 **请求从哪个地址进来**。需要把绑定改为 `0.0.0.0`(所有接口)。

任务:把单元文件中的 `--bind 127.0.0.1` 改为 `--bind 0.0.0.0` 并重启。

修改单元文件:

```
sudo vim /etc/systemd/system/lab-api.service
```

- 找到 `ExecStart=` 行中的 `--bind 127.0.0.1` 并修改。vim:`i` 输入,`Esc` → `:wq` 保存并退出。

重新加载更改:

```
sudo systemctl daemon-reload
```

- 修改了单元文件,所以要让 systemd 重新读取。

重启服务:

```
sudo systemctl restart lab-api
```

- 用新的绑定地址重新启动进程。

查看绑定地址:

```
sudo ss -ltn | grep 9090
```

- 不需要进程名,所以不加 `-p`。显示 `0.0.0.0:9090` 表示在所有接口上接收连接。

再次通过容器 IP 连接:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # 现在成功了
```

- 再次发送同样的请求,确认这次是否有响应。

变为 `0.0.0.0:9090` 且通过容器 IP 能得到响应,就点击 **[校验]**。

## 名称解析 — hosts 与 DNS

最后一块拼图是 **名称 → IP**。解析顺序通常是 `/etc/hosts` → DNS(`/etc/resolv.conf` 中的域名服务器),这个顺序规则由 `/etc/nsswitch.conf` 中的 `hosts:` 行决定。

查看 DNS 服务器配置:

```
cat /etc/resolv.conf
```

- `nameserver` — 要查询的 DNS 服务器,`search` — 依次附加在短名称后尝试的域名列表。

查看解析顺序规则:

```
grep hosts /etc/nsswitch.conf
```

- `hosts: files dns` — 表示先查 `files`(即 `/etc/hosts`),查不到再查 `dns`。

查询工具的用途各不相同:`nslookup`/`dig` **直接向 DNS 服务器** 查询,而 `getent hosts` 走的是 **系统实际的解析路径**(包括 hosts 文件)。应用程序看到的结果与 getent 一致。

任务:让 lab-api 能通过 `api.lab.local` 这个名称访问。DNS 服务器改不了,所以登记到 `/etc/hosts` 中。

在 hosts 文件中登记名称:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

- `tee -a` — 不覆盖文件,而是 **追加**(append)到末尾。漏掉的话整个 hosts 文件就只剩这一行了!
- 格式:`<IP> <名称> [别名…]`。

按系统解析路径查询:

```
getent hosts api.lab.local
```

- `getent hosts <名称>` — 按 nsswitch 的顺序(包括 hosts 文件)解析名称,与应用程序看到的结果相同。

用名称连接:

```
curl -s http://api.lab.local:9090/status.json
```

- 用名称而不是 IP 发送请求。curl 也使用系统解析器,所以 `/etc/hosts` 中的条目会生效。

收到响应后点击 **[校验]** — 模块完成。
