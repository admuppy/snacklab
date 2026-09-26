# 文件权限与特殊权限

Linux 安全的第一步是 **文件权限**。本模块涵盖基本权限(rwx)与 umask、setgid 和 sticky bit 等特殊权限、用 ACL 做细粒度访问控制,最后是在真实系统上找出并修复危险权限的审计。

先确认一下当前用户。`learner` 是可以使用 sudo 的普通用户。

```
id
```

- `id` — 显示当前用户的 UID、主组(`gid`)以及所属的全部组(`groups`)。

你需要能在两种权限表示法之间自如切换。

| 表示法 | 示例 | 含义 |
|---|---|---|
| 符号 | `rwxr-x---` | 所有者 rwx / 组 r-x / 其他人 无 |
| 八进制 | `750` | r=4、w=2、x=1 之和 |

## 基本权限与 umask

创建文件时的默认权限由 **umask** 决定。

查看当前 umask 值:

```
umask
```

- `umask` — 从新建文件/目录中 **去掉** 的权限位。常见的 `0022` 会去掉组和其他人的写(w)权限 → 文件 644,目录 755。

创建一个文件,看看它实际以什么权限生成:

```
touch /tmp/t1 && stat -c %a /tmp/t1
```

- `touch` — 创建空文件(已存在则只更新修改时间)。`&&` — 前一条命令成功才接着执行。
- `stat -c %a` — 用格式指定(`-c`)只输出八进制权限(`%a`)。

现在创建一个只有你能访问的工作区。要求:

- `~/work` 目录 — 权限 **700**(只有所有者 rwx)
- `~/work/secret.txt` 文件 — 内容随意,权限 **600**(只有所有者 rw)

创建工作目录并设为 700:

```
mkdir -p ~/work && chmod 700 ~/work
```

- `mkdir -p` — 连同上级路径一起创建,已存在也不报错。
- `chmod 700` — 用八进制指定权限:所有者 rwx(7),组和其他人无(0)。

创建秘密文件:

```
echo "top secret" > ~/work/secret.txt
```

- `echo "…" > 文件` — 把字符串写入文件(不存在则创建,存在则覆盖)。新文件的权限遵循 umask。

把文件权限设为 600:

```
chmod 600 ~/work/secret.txt
```

- `600` — 所有者 rw(6 = 4+2),组和其他人无。符号写法为 `chmod u=rw,go= <文件>`。

用 `stat` 确认后点击 **[校验]**。

```
stat -c '%a %n' ~/work ~/work/secret.txt
```

- `%a` 为八进制权限,`%n` 为文件名。传入多个文件时每个输出一行。

> 目录的 `x` 是"通过(进入)权限"。即使目录有 `r`,没有 `x` 也无法访问其中的文件 — 在第 3 步 ACL 中还会遇到。

## setgid 与 sticky bit

创建团队共享目录时常用的两种特殊权限:

| 位 | 八进制 | 对目录的效果 |
|---|---|---|
| setgid | 2000 | 在其中创建的文件 **继承目录的组** |
| sticky | 1000 | 只有 **所有者** 才能删除文件(与 `/tmp` 相同) |

创建 `share` 组的共享目录 `/srv/share`。要求:

- 创建组:`share`
- `/srv/share` 目录,所属组为 `share`
- 权限 **3775** = setgid(2000)+ sticky(1000)+ 775

创建组:

```
sudo groupadd -f share
```

- `groupadd` — 创建组。`-f` 表示即使已存在也不报错,以成功结束。

创建共享目录:

```
sudo mkdir -p /srv/share
```

- `/srv` 属于 root,所以要用 `sudo` 创建。

把所属组改为 share:

```
sudo chgrp share /srv/share
```

- `chgrp <组> <路径>` — 只修改所属组。连所有者也改的话用 `chown 用户:组`。

连同特殊权限设为 3775:

```
sudo chmod 3775 /srv/share
```

- 四位八进制数的第一位是特殊位:`3` = setgid(2)+ sticky(1)。其余 `775` 为所有者和组 rwx,其他人 r-x。

看看结果。在符号表示中,setgid 显示为组位置上的 `s`,sticky 显示为最后一位的 `t`(`drwxrwsr-t`)。

查看权限和所属组:

```
stat -c '%a %G %n' /srv/share
```

- `%G` — 所属组的名称。

查看符号表示:

```
ls -ld /srv/share
```

- `ls -ld` — 以符号形式(`drwxrwsr-t`)显示目录 **本身**(`-d`),而不是其内容。

确认无误后点击 **[校验]**。

## 用 ACL 做细粒度访问控制

`rwx` 只有所有者/组/其他人三栏。"只允许 **某一个特定用户** 读取这个文件"要用 **ACL**(Access Control List)来解决。

系统中已经准备了审计账号 `audit`。请把第 1 步创建的 `~/work/secret.txt` 以 **只读** 方式开放给 audit。

授予 audit 读取 ACL:

```
setfacl -m u:audit:r ~/work/secret.txt
```

- `setfacl -m` — 添加/修改(modify)ACL 条目。格式为 `u:<用户>:<权限>`(组用 `g:`)。

查看设置的 ACL:

```
getfacl ~/work/secret.txt
```

- `getfacl` — 显示文件的所有者、组、全部 ACL 条目以及 `mask`(ACL 的最大允许权限)。

但这还没完 — audit 要 **到达** 这个文件,必须能通过路径上的目录(`~` 和 `~/work`)。700 的目录会挡住 audit。

只用 ACL 开放通过(x)权限:

```
setfacl -m u:audit:x ~ ~/work
```

- 目录只给 `x`,表示只允许 **通过**,而不能列出内容(r)。一次作用于两个路径(`~`、`~/work`)。

从 audit 的角度验证一下是否真的可行。

读取 — 应该成功:

```
sudo -u audit cat ~/work/secret.txt
```

- `sudo -u <用户> <命令>` — 以其他用户身份执行命令,验证实际权限。

写入 — 应该失败:

```
sudo -u audit sh -c 'echo x >> ~learner/work/secret.txt'
```

- `sh -c '…'` — 以 audit 身份启动整个 shell,让重定向(`>>`)也以 audit 的权限执行。
- `~learner` — learner 用户的主目录(对 audit 来说 `~` 是它自己的主目录)。

设置了 ACL 的文件,在 `ls -l` 中权限后面会带一个 `+`。确认后点击 **[校验]**。

## 权限审计与修复

最后是实战任务。带有 **SUID**(4000)位的可执行文件会以所有者(通常是 root)的权限运行,因此是审计的头号对象。

在整个系统中查找 SUID 文件并保存:

```
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt
```

- `find /` — 从根目录递归查找。`-xdev` — 不跨入其他文件系统(/proc 等)。
- `-perm -4000` — **包含** SUID 位的文件(`-` 表示"具有这些位的全部")。`-type f` — 只要普通文件。
- `> ~/work/suid.txt` — 把结果列表保存到文件。

查看列表:

```
cat ~/work/suid.txt
```

- `cat` — 输出保存的 SUID 文件列表。

想一想 `passwd` 为什么是 SUID — 因为普通用户需要更新属于 root 的 `/etc/shadow`。

第二个任务:`/opt/lab/perm/danger.conf` 是包含数据库密码的配置文件,却以 **666**(任何人都可读写!)的权限部署了。

查看当前权限:

```
ls -l /opt/lab/perm/
```

- `ls -l` — 查看权限(`-rw-rw-rw-` = 666)以及所有者和组。

修复为 640:

```
sudo chmod 640 /opt/lab/perm/danger.conf
```

- `640` — 所有者 rw,组 r,其他人无。保留应用通过组权限读取,其余全部堵上。

修复后点击 **[校验]**,模块即完成。
