# systemd 服务与 journald

在 linux-02 中我们用 nohup 启动了守护进程,但实际工作中的守护进程全都是 **systemd 单元** — 开机自动启动、挂掉后自动重启、日志由 journald 自动收集。本模块中你将亲手编写单元,用 journal 诊断并修复出故障的单元,并用定时器取代 cron。

先浏览一下当前系统的单元。

浏览服务单元列表:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — 已加载到内存的单元列表。`--type=service` 只看服务,`--no-pager` 不经 less 直接输出。
- `| head -15` — 只看前 15 行。列依次为 LOAD(文件加载)、ACTIVE(总体状态)、SUB(详细状态)。

查看 cron 服务状态:

```
systemctl status cron --no-pager
```

- `systemctl status <单元>` — 在一屏中显示状态(`Active:`)、主 PID、cgroup 进程树以及最近几行日志。

## 编写服务单元

最小的服务单元只需要三个段。

| 段 | 作用 |
|---|---|
| `[Unit]` | 描述、依赖关系(Description、After 等) |
| `[Service]` | 运行方式(ExecStart、Restart、User 等) |
| `[Install]` | enable 时挂到哪里(WantedBy) |

任务:创建在 8080 端口运行静态 HTTP 服务器的 `hello-web.service`。

```
sudo tee /etc/systemd/system/hello-web.service <<'EOF'
[Unit]
Description=hello web

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 127.0.0.1

[Install]
WantedBy=multi-user.target
EOF
```

- `sudo tee <文件> <<'EOF'` — 由以 root 权限运行的 `tee` 把 heredoc 正文写入文件(`sudo cat > 文件` 的重定向由你自己的 shell 处理,会报权限错误)。
- `/etc/systemd/system/` — 管理员创建的单元文件存放位置,优先于软件包自带的单元(`/usr/lib/systemd/system/`)。
- `ExecStart=` — 要执行的命令(绝对路径)。`WantedBy=multi-user.target` — enable 后会挂到常规启动目标上。

创建或修改单元文件后,**一定要 daemon-reload** — systemd 不会直接读文件,而是使用已加载到内存中的副本。

重新加载更改:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — 让 systemd 重新读取单元文件。不会重启服务。

注册开机启动 + 立即启动:

```
sudo systemctl enable --now hello-web
```

- `enable` — 在 `WantedBy` 目标中创建符号链接,实现开机自动启动;`--now` — 同时立即执行 `start`。
- 单元名的 `.service` 后缀可以省略。

查看服务状态:

```
systemctl status hello-web --no-pager
```

- 看到 `Active: active (running)` 和主 PID(`python3`)就说明启动正常。

查看响应:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — 不显示进度地发送 HTTP 请求并输出响应正文。`| head -3` 只看前 3 行(目录列表 HTML)。

`enable --now` 的意思是"注册开机自动启动 + 现在就启动"。确认有响应后点击 **[校验]**。

## 用 journald 修复出故障的单元

系统中部署了一个名为 `lab-report.service` 的单元,但启动失败。亲自看看。

尝试启动服务:

```
sudo systemctl start lab-report
```

- `systemctl start` — 立即启动服务(与开机注册无关)。失败时会输出 `Job … failed` 的消息,并提示可用于排查的命令。

查看失败状态:

```
systemctl status lab-report --no-pager
```

- 通过 `Active: failed` 和 `code=exited, status=…` 这一行确认失败原因代码。

原因调查要用 **journalctl**。用 `-u` 指定单元,再配合 `-e`(跳到末尾)或 `--no-pager`。

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — 查看 journald 日志。`-u <单元>` 只看该单元的日志,`--no-pager` 直接输出,`| tail -20` 最近 20 行。
- 实时跟踪用 `-f`,只看本次启动用 `-b`,时间范围用 `--since "10 min ago"`。

你会看到 `status=203/EXEC` — 这是 systemd 退出码中的经典,意思是 **无法执行 ExecStart 中的可执行文件**(路径拼写错误、没有执行权限、shebang 问题)。把单元指向的路径和实际文件对照一下。

查看单元指向的路径:

```
systemctl cat lab-report
```

- `systemctl cat <单元>` — 显示 systemd 实际使用的单元文件(含 drop-in)的内容和路径。看看 `ExecStart=` 这一行。

查看实际文件:

```
ls -l /opt/lab/bin/
```

- `ls -l` — 同时查看文件名和权限(有没有 `x`)。与单元中的路径逐字比对。

任务:修正 ExecStart 路径(别忘了 daemon-reload)并启动服务。

修改单元文件:

```
sudo vim /etc/systemd/system/lab-report.service
```

- 单元文件属于 root,所以用 `sudo` 打开。vim:`i` 输入,`Esc` → `:wq` 保存并退出。
- 修改后如果忘了 `daemon-reload`,systemd 会继续用旧路径失败。

重新加载更改:

```
sudo systemctl daemon-reload
```

启动服务:

```
sudo systemctl start lab-report
```

实时查看日志:

```
tail -f /var/log/lab/report.log   # 用 Ctrl-C 退出
```

- `tail -f` — 持续跟踪(follow)文件末尾,每出现新行就输出。用于确认服务是否真的在工作。

变为 active(running)后点击 **[校验]**。

## 用 Restart 策略自愈

进程总会挂掉 — OOM、bug、失误。systemd 的 `Restart=` 就是在那时自动把它拉起来的安全网。

| 值 | 重启条件 |
|---|---|
| `no`(默认) | 不重启 |
| `on-failure` | 仅在异常退出(退出码≠0、信号)时 |
| `always` | 即使正常退出也一律重启 |

任务:给 hello-web 添加 `Restart=on-failure` 和 `RestartSec=1`。可以直接修改单元文件,也可以采用不动原文件的 **drop-in** 方式(`systemctl edit` 是交互式的,这里直接写文件)。

创建 drop-in 目录:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<单元>.d/` — drop-in 目录。其中的 `*.conf` 文件会覆盖在原单元之上。即使软件包更新了原文件,你的配置也能保留。

编写 drop-in 文件:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- 只写要加到 `[Service]` 段的键。`Restart=on-failure` 异常退出时重启,`RestartSec=1` 重启前等待 1 秒。

重新加载更改:

```
sudo systemctl daemon-reload
```

重启服务:

```
sudo systemctl restart hello-web
```

- `restart` — 先 stop 再 start。进程会在应用了新配置(drop-in)的状态下重新启动。

来实验一下是否真的会自动恢复。用 SIGKILL 杀掉主 PID,几秒后查看状态。

查看主 PID:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — 以 `键=值` 形式输出单元属性。`-p MainPID` 只取一个属性,`--value` 只输出值,不带 `MainPID=`。

强制终止进程:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- 对通过 `$( ... )` 获得的主 PID 执行 `kill -9`(SIGKILL)— 无法拦截的强制终止。这属于"异常退出",因此适用 `on-failure`。

稍等片刻后查看状态:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- 用 `sleep 3` 给重启(RestartSec=1)留出时间,然后查看状态的前 5 行。`Main PID` 应该和之前不同。

PID 变了且再次处于 active 就说明成功 — 点击 **[校验]**。(校验也会再做一次同样的实验。)

## 用定时器执行周期任务

cron 在 systemd 中的替代品就是 **定时器**。日志会留在 journal 中,失败也能作为单元来管理,所以如今发行版中的定期任务大多是定时器。它由 **服务(做什么)+ 定时器(何时做)** 一对组成。

任务:创建 `lab-tick` 定时器,每分钟把当前时间记录到 `/var/log/lab/tick.log`。

编写服务单元(做什么):

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — 执行完就结束的任务。命令结束即视为成功,并回到非活动状态。
- `bash -c '…'` — 重定向(`>>`,追加写入)是 shell 的功能,所以要经由 bash 执行。`date -Is` 输出 ISO 8601 格式的时间。

编写定时器单元(何时做):

```
sudo tee /etc/systemd/system/lab-tick.timer <<'EOF'
[Unit]
Description=lab tick every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
```

- `OnCalendar=*-*-* *:*:00` — `年-月-日 时:分:秒` 形式的日历表达式。每天每小时每分钟的第 0 秒 = 每分钟一次。
- `AccuracySec=1s` — 把执行时间的允许误差(默认 1 分钟)缩小到 1 秒。
- 定时器会执行同名的 `.service`(这里是 `lab-tick.service`)。通过 `WantedBy=timers.target` 进行 enable。

重新加载更改:

```
sudo systemctl daemon-reload
```

注册并启动定时器:

```
sudo systemctl enable --now lab-tick.timer
```

- 名称要写全到 `.timer`。省略的话会被当作 `.service`。

`Type=oneshot` 用于"执行一次就结束"的任务。注意 enable 的对象是 **timer 而不是 service**。确认注册状态后点击 **[校验]**,模块即完成。

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — 活动定时器的下次(`NEXT`)和上次(`LAST`)执行时间。
- `grep -E 'NEXT|lab-tick'` — 只保留表头行和 lab-tick 那一行(`|` 是扩展正则中的"或")。
