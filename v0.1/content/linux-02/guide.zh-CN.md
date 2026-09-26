# 进程与信号

服务器变慢或行为异常时,首先要做的就是 **查看进程**。本模块中你将用 ps 和 /proc 探查进程,用信号控制进程,让任务脱离终端在后台运行,并追查占用端口的进程。

实验环境中已经以 systemd 单元的形式运行着三个守护进程。

| 进程 | 身份 |
|---|---|
| `lab-worker` | 普通的工作进程 — 第 1 步的探查对象 |
| `lab-stubborn` | **会忽略 SIGTERM** 的顽固家伙 — 第 2 步中解决它 |
| `lab-listener` | 占用 127.0.0.1:5555 的某个东西 — 第 4 步中追查 |

## 探查进程 — ps 与 /proc

先浏览一下所有进程。

浏览完整列表:

```
ps aux | head
```

- `ps aux` — 显示所有用户(`a`,以及 `x`:包括没有终端的)的进程,并附带用户、CPU%、MEM%、命令(`u`)。
- `| head` — 只看前 10 行。

以树形查看:

```
ps -ef --forest | head -30
```

- `ps -ef` — 以包含 PID、PPID 的完整格式(`-f`)显示所有进程(`-e`)。
- `--forest` — 用缩进的树形画出父子关系。`head -30` 只看前 30 行。

来找一下 `lab-worker`。`pgrep -f` 会在整条命令行中匹配模式并返回 PID。

```
pgrep -f /opt/lab/bin/lab-worker
```

- `pgrep <模式>` — 只输出名称匹配模式的进程的 PID。
- `-f` — 不是按进程名,而是在 **整条命令行**(含路径和参数)中查找。

ps 显示的所有信息都来自 **/proc 文件系统**。直接看看 PID 目录里面(cmdline 以 NUL(\0)分隔,所以用 tr 替换后再读)。

把 PID 存入变量:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

- `$( ... )` — 命令替换。把输出(PID)存入 shell 变量 `pid`,之后用 `$pid` 引用。
- `| head -1` — 即使匹配到多个,也只取第一个 PID。

查看 PID 目录内容:

```
ls /proc/$pid/
```

- `/proc/<PID>/` — 内核以文件形式展示进程信息的虚拟目录。其中有 `cmdline`(运行参数)、`status`(状态、内存)、`fd/`(打开的文件)、`environ`(环境变量)等。

读取 cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

- `tr '\0' ' '` — 把输入中的 NUL 字符替换(translate)为空格。
- `< 文件` — 把文件作为标准输入。`; echo` 在末尾补一个换行。

任务:把结果保存到文件。

- `~/work/worker.pid` — lab-worker 的 PID
- `~/work/worker.cmdline` — `/proc/<PID>/cmdline` 的内容(tr 转换后的)

创建工作目录:

```
mkdir -p ~/work
```

- `mkdir -p` — 连同所需的上级目录一起创建,已存在也不报错。

保存 PID:

```
echo "$pid" > ~/work/worker.pid
```

- `echo "$pid"` — 输出变量的值。用 `> 文件` 把输出保存(覆盖)到文件。

保存 cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

- 与前面输出到屏幕的 `tr` 命令相同,这次用 `>` 把结果保存到文件。

保存好后点击 **[校验]**。

## 用信号控制进程

`kill` 不是杀死进程的命令,而是 **发送信号** 的命令。

| 信号 | 编号 | 特点 |
|---|---|---|
| SIGTERM | 15 | 默认值。进程 **可以忽略它,或清理后再退出** |
| SIGKILL | 9 | 内核立即移除进程。**无法忽略**,没有清理的机会 |
| SIGHUP | 1 | 按惯例常用于"重新加载配置" |

`lab-stubborn` 被写成用 trap 忽略 TERM 和 INT。亲自确认一下。

确认它是否存活:

```
pgrep -f /opt/lab/bin/lab-stubborn
```

- 输出 PID 说明存活。什么都没有输出(退出码 1)说明没有该进程。

发送 SIGTERM:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

- `pkill` — 向匹配模式的进程发送信号(`pgrep` + `kill`)。
- `-TERM` — 要发送的信号(SIGTERM,15)。`-f` 在整条命令行中查找。
- `sudo` — 这是其他用户(root)启动的进程,需要管理员权限。

确认它是否仍然存活:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # 仍然存活
```

- `sleep 1` — 等待 1 秒,给信号处理留出时间,然后用 `;` 接着再次确认。

注意:这个进程由 **systemd 单元**(lab-stubborn.service)管理。只对进程 kill -9 也可以,但由单元管理的进程,按常规应在单元层面处理。不过 `systemctl stop` 会先发送 TERM 并等待超时(默认 90 秒),对这个家伙来说太慢了 — 请使用 **通过单元直接发送 SIGKILL** 的方法。

通过单元发送 SIGKILL:

```
sudo systemctl kill -s KILL lab-stubborn
```

- `systemctl kill <单元>` — 向单元中的 **所有进程** 发送信号。
- `-s KILL` — 把要发送的信号设为 SIGKILL(9)。进程无法拦截,会被立即移除。

确认已终止:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "terminated"
```

- `A || B` — 只有 A 失败(退出码 ≠ 0)时才执行 B。`pgrep` 什么都没找到时就会输出这条消息。

确认它已终止后点击 **[校验]**。

## 脱离会话的后台运行

在终端中用 `&` 启动的进程,在终端断开时会收到 SIGHUP 并一起终止。要让它在会话结束后依然存活,需要使用 **nohup**(忽略 HUP + 重定向输出)或 **setsid**(脱离到新会话)。

`/opt/lab/bin/lab-batch` 是一个批处理任务,每 10 秒向第一个参数指定的文件写入时间戳。请让它脱离终端启动,并把日志写到 `~/work/batch.log`。

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

- `nohup <命令>` — 让命令忽略 SIGHUP,终端关闭后仍继续运行。
- `>/dev/null 2>&1` — 丢弃标准输出,并把标准错误(2)也送到与标准输出(1)相同的地方。
- 末尾的 `&` — 在后台运行,并立即返回提示符。

查看一下父进程。脱离 shell 成为孤儿进程后,会被 PID 1(在 Pod 中是 systemd)收养。

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

- `ps -o pid,ppid,cmd` — 把输出列指定为 PID、父 PID、命令。
- `-p $(pgrep ...)` — 只查询通过命令替换得到的 PID 的进程。

查看日志:

```
tail ~/work/batch.log
```

- `tail <文件>` — 文件末尾 10 行。要持续跟踪用 `tail -f`(Ctrl+C 退出)。

PPID 为 1 且日志在不断增加,就点击 **[校验]**。

> 实际工作中,比起这种临时守护进程,systemd 单元(或 `systemd-run`)才是正解 — 在 linux-06 模块中介绍。

## 追查占用端口的进程

"这个端口被谁占着?"是最常见的诊断问题。用 `ss`(socket statistics)找出 5555 端口的主人。要看到进程名需要 `-p`,其他用户的进程需要 sudo 才能看到。

查看所有监听套接字:

```
sudo ss -ltnp
```

- `ss` — 查看套接字状态(netstat 的继任者)。`-l` 只看监听套接字,`-t` TCP,`-n` 端口以数字而非名称显示,`-p` 连同打开套接字的进程一起显示。

只查询 5555 端口:

```
sudo ss -ltnp sport = :5555
```

- `sport = :5555` — 过滤表达式,只显示源(本地)端口为 5555 的套接字。

用 `lsof` 也能得到同样的答案。

```
sudo lsof -i :5555
```

- `lsof` — 列出打开的文件(在 Linux 中套接字也是文件)。`-i :5555` — 只看使用 5555 端口的网络连接。

任务:把占用 5555 端口的 **进程名** 保存到 `~/work/port-owner.txt`。

提取并保存进程名:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

- `grep -o` — 不输出整行,**只输出匹配的部分**。从 `users:(("python3",pid=…))` 中只取出名称。
- 用 `head -1` 只留一个,再用 `>` 保存。

查看保存的内容:

```
cat ~/work/port-owner.txt
```

- `cat <文件>` — 原样输出文件内容。

如果好奇这个 python3 到底是什么,就用 PID 再去翻一翻 /proc — 正是第 1 步学到的方法。保存好后点击 **[校验]**。
