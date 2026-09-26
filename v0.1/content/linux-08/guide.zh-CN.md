# 综合 —— 救活挂掉的服务

凌晨 2 点,告警响了:**"lab-app 起不来。"** 本模块是一个综合场景,要调动至今学过的所有知识(systemd、journald、信号与端口追踪、文件权限),从头到尾处理一次真实的故障。

这次不会把命令一条条告诉你 — **诊断顺序** 才是本模块的学习目标。卡住时,回想一下之前模块中的工具:`systemctl status/cat`、`journalctl -u`、`sudo ss -ltnp`、`ls -l`、`sudo -u <用户>`。

先掌握一下现状。

```
systemctl status lab-app --no-pager
```

- 从 `Active:` 行(状态)和最后几行日志中寻找第一条线索。`--no-pager` 不经 less 直接输出。

## 诊断启动失败 — 203/EXEC

只看 status 不够的话,journal 知道答案。

```
journalctl -u lab-app --no-pager | tail -20
```

- `journalctl -u <单元>` — 只看该单元的日志。用 `| tail -20` 聚焦在最近 20 行。

`status=203/EXEC` — 就是在 linux-06 中见过的那个代码。确认单元 **试图执行什么** 而失败了。

```
systemctl cat lab-app
```

- 原样查看单元文件内容。留意 `ExecStart=`(执行什么)和 `User=`(以谁的身份执行)。

对照一下 ExecStart 中解释器的路径在这个系统上是否真的存在(`ls /usr/bin/python3*`)。它应该指向了一个不存在的版本 — 部署脚本是按另一台服务器写的,这是常见的事故。

任务:把 ExecStart 改成实际存在的解释器,并执行 `daemon-reload`。改好后点击 **[校验]**。

> start 还不会成功 — 故障通常不止一层。进入下一步。

## 解决端口冲突

现在 start 会报另一个错误。

尝试启动服务:

```
sudo systemctl start lab-app
```

- 修复后再启动一次试试。如果失败,接下来的日志会告诉你新的原因。

查看错误日志:

```
journalctl -u lab-app --no-pager | tail -5
```

- 只需要看这次尝试的日志,所以看最后 5 行。

`Address already in use` — lab-app 要用的 8080 被 **别人抢先占用了**。用在 linux-02、07 中学到的端口追踪方法找出元凶。

```
sudo ss -ltnp | grep 8080
```

- 找出在 8080 上监听的套接字及其进程(`users:(("名称",pid=…))`)。记下 PID。

要从 PID 反查单元,`systemctl status <PID>` 很方便。元凶是一个即将废弃的遗留单元。只停止的话重启后它还会复活,所以 **还必须 disable**。

任务:用 `disable --now` 关掉抢占端口的单元,然后启动 lab-app。lab-app 变为 active 后点击 **[校验]**。

## 解决权限问题

服务起来了……但还没结束。

```
curl -i http://127.0.0.1:8080/index.html
```

- `curl -i` — 在响应正文之前一并(include)输出状态行(`HTTP/1.0 404 …`)和响应头。

**404** — 可是文件明明存在(`ls -l /srv/lab-app/`)。为什么?

线索有两条。① 单元中有 `User=labapp` — 服务不是以 root,而是以 labapp 身份运行。② index.html 是 `root:root 600` — **labapp 读不了它。** 这个服务器(http.server)打不开文件时就会返回 404。这是"文件存在却 404"的典型权限问题。

养成验证猜想的习惯 — 以那个用户的身份直接读一下。

```
sudo -u labapp cat /srv/lab-app/index.html
```

- `sudo -u <用户> <命令>` — 以该用户的权限执行命令。这是用与服务相同的权限读取文件的验证方法。

任务:修改所有权或权限,让 labapp 能读取(用 linux-01 的思路 — 不要放开得超出必要)。curl 返回 `LAB APP OK` 后点击 **[校验]**。

## 防止复发与收尾

恢复工作要做到"现在能用" + **"下次也能用"** 才算完整。检查清单:

1. lab-app 是否处于 **enable** 状态?(重启后又挂掉的恢复不算恢复)
2. 把最终响应留作证据 — 保存到 `~/work/final.txt`

注册开机自动启动:

```
sudo systemctl enable lab-app
```

- `enable` — 注册开机自动启动(创建符号链接)。对当前正在运行的服务没有影响。可用 `systemctl is-enabled lab-app` 确认。

保存最终响应:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

- 用 `>` 把 `curl -s` 收到的响应正文保存到文件。

查看保存的内容:

```
cat ~/work/final.txt
```

- 确认保存的响应是 `LAB APP OK`。

点击 **[校验]** 就完成了 Linux 路线。请记住:今天处理的三重故障(错误的路径 → 端口冲突 → 权限)是真实故障报告中最常见的组合,而且这三者 **journal、ss 和 ls -l 早就知道了**。
