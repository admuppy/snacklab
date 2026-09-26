# 用户、组与 sudo 最小权限

服务器上来了新同事,就要创建账号、把他加入团队组,并 **只按需** 开放 sudo 权限;同事离职时,则要锁定账号。本模块覆盖这一整个生命周期。

先看看账号信息保存在哪里。

| 文件 | 内容 |
|---|---|
| `/etc/passwd` | 用户列表(名称:x:UID:GID:说明:主目录:shell) |
| `/etc/shadow` | 密码哈希 + 过期策略(只有 root 可读) |
| `/etc/group` | 组及其成员 |
| `/etc/sudoers`、`/etc/sudoers.d/` | sudo 权限规则 |

查询 learner 账号:

```
getent passwd learner
```

- `getent <数据库> <键>` — 通过 NSS 查询一个条目。从 `passwd` 数据库中输出 `learner` 这一行。

查看 shadow 的开头部分:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` 只有 root 能读,所以需要 `sudo`。第二个字段是密码哈希(`*`、`!` 表示无法登录)。

> `getent` 不直接打开文件,而是通过 NSS(包括 LDAP 等外部来源)查询 — 比 `cat /etc/passwd` 更准确的习惯。

## 创建用户

创建部署专用账号 `deploy`。要求:

- 创建主目录(`-m` — 不加的话会得到一个没有主目录的账号)
- 登录 shell 为 `/bin/bash`(`-s` — 很多发行版的默认值是 sh)

创建 deploy 用户:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — 创建新用户。`-m` 创建主目录(复制 `/etc/skel` 的内容),`-s /bin/bash` 指定登录 shell,最后一个参数是用户名。
- 密码另外用 `passwd deploy` 设置(本实验不需要)。

查看 passwd 条目:

```
getent passwd deploy
```

- 以冒号分隔的字段中,最后两个是主目录和 shell。确认是否为 `/home/deploy`、`/bin/bash`。

查看主目录:

```
ls -ld /home/deploy
```

- `ls -ld` — 查看目录 **本身**(`-d`)而不是其内容的权限和所有者。所有者应该是 `deploy`。

`useradd` 是底层工具,**什么都不会问你**。漏了选项它也照样创建,所以创建后必须确认。确认后点击 **[校验]**。

## 配置组

创建运维团队组 `ops`,并把 deploy 加进去。这里有一个经典陷阱 —

| 命令 | 结果 |
|---|---|
| `usermod -aG ops deploy` | 把 ops **添加为附加组** ✔ |
| `usermod -G ops deploy` | 把附加组 **替换为只有 ops 一个**(原有的全部被移除!) |
| `usermod -g ops deploy` | **替换主组**(创建文件时的默认组会改变) |

不带 `-a`(append)的 `-G` 是通往事故的捷径。请把它添加为附加组。

创建 ops 组:

```
sudo groupadd ops
```

- `groupadd <组>` — 创建新组,会在 `/etc/group` 中添加一行。

添加为附加组:

```
sudo usermod -aG ops deploy
```

- `usermod` — 修改已有用户的属性。`-G ops` 指定附加组,`-a` 表示 **追加**(append)到已有的附加组。
- 已经登录的会话需要重新登录才能生效新组。

查看组:

```
id deploy
```

- `id <用户>` — 在一行中显示 UID、主组(`gid=`)和所有组(`groups=`)。

在 `id` 的输出中,分清 `gid=`(主组)和 `groups=`(全部)。确认后点击 **[校验]**。

## sudoers 最小权限

我们想允许 deploy 查询服务状态,但 **禁止更多操作**。惯例是不直接修改 `/etc/sudoers`,而是在 `/etc/sudoers.d/` 下创建附加文件(drop-in)。

语法:`谁 在哪里=(以谁的身份) [NOPASSWD:] 命令列表`

编写 drop-in 规则:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo '规则' | sudo tee <文件>` — 如果写成 `sudo echo … > 文件`,重定向由你自己的 shell 处理,会报权限错误。所以让以 root 身份运行的 `tee` 来写文件。
- 规则:`deploy` 可以在所有主机(`ALL`)上、以任何身份(`(ALL)`)、无需密码(`NOPASSWD:`)只执行 `systemctl status *`。

把权限设为 440:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — 所有者(root)和组只读。sudo 会拒绝其他用户可写的 sudoers 文件。

**语法检查是必须的。** sudoers 一旦损坏,sudo 本身就无法使用,恢复会很麻烦。`visudo -cf` 就是这道保险。

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — 只做语法检查(check),`-f <文件>` — 指定要检查的文件。应输出 `parsed OK`。
- 编辑 sudoers 的正规做法是用 `sudo visudo`(保存前自动检查)。

从 deploy 的角度确认一下能做什么。

deploy 的 sudo 权限列表:

```
sudo -l -U deploy
```

- `sudo -l` — 列出允许的 sudo 命令,`-U deploy` — 查询其他用户的列表(需要 root 权限)。

允许的命令 — 应该成功:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # 允许的命令
```

- `sudo -u deploy <命令>` — 以 deploy 用户身份执行命令。在其中再调用 `sudo`,测试 deploy 的 sudo 权限。
- `sudo -n` — 不询问密码(non-interactive)。需要询问时会直接失败。
- `--no-pager` — 不把输出交给 less,直接打印。

禁止的命令 — 应该被拒绝:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # 被拒绝的命令
```

- `restart` 不在规则中,所以会被拒绝。用 `2>&1` 把错误信息也送进管道,再用 `tail -1` 只看最后一行。

允许/拒绝符合预期,就点击 **[校验]**。

## 锁定账号与密码策略

`olduser` 是离职人员的账号。删除(`userdel`)会带来文件所有权清理的问题,所以通常先 **锁定**。

锁定账号:

```
sudo usermod -L olduser
```

- `usermod -L` — 锁定(Lock)账号。在 shadow 的哈希前加上 `!`,阻止密码登录。解锁用 `-U`。

查看锁定状态:

```
sudo passwd -S olduser
```

- `passwd -S <用户>` — 密码状态摘要。第二个字段为 `L` 表示已锁定,`P` 表示可用,`NP` 表示无密码。

`passwd -S` 的第二个字段是 `L`(locked)就说明成功了。锁定只是在 shadow 的哈希前加一个 `!`,随时可以用 `-U` 恢复。

接着为 deploy 设置 **密码最长使用期限 90 天** 的策略。

设置最长 90 天的策略:

```
sudo chage -M 90 deploy
```

- `chage` — 修改密码过期策略(change age)。`-M 90` — 把最长使用天数设为 90 天。

查看策略:

```
sudo chage -l deploy
```

- `chage -l` — 以列表(list)形式显示当前策略:最后修改日期、过期日期、最长/最短期限等。

两项都确认后点击 **[校验]** — 模块完成。
