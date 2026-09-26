# Bash 脚本编程

当某条单行命令开始被反复使用时,就该把它写成脚本了。本模块要学的不是 **永远不死的脚本,而是一出问题就立刻终止(fail-fast)的脚本** — 因为悄无声息地给出错误结果的脚本才是最危险的。

所有文件都写在 `~/work/` 下。编辑器用 vim 或 nano 都可以,也可以用 `cat > 文件 <<'EOF'` 这样的 heredoc 来创建。

## 安全的脚本骨架

所有脚本的前两行基本上是固定的。

```
#!/bin/bash
set -euo pipefail
```

| 选项 | 效果 |
|---|---|
| `-e` | 命令失败时立即退出 |
| `-u` | 引用未定义的变量时报错(防止拼写错误) |
| `-o pipefail` | 管道中间某一步失败也视为失败 |

任务:编写 `~/work/sysinfo.sh`。要求:

- bash 的 shebang + `set -euo pipefail`
- 输出一行 `host=<主机名>` 和一行 `uptime=<秒数>`
- 可执行权限

编写脚本:

```
cat > ~/work/sysinfo.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
EOF
```

- `cat > 文件 <<'EOF'` … `EOF` — heredoc。把两个 `EOF` 之间的各行作为 `cat` 的输入,再用 `>` 保存到文件。像 `'EOF'` 这样加上引号,正文中的 `$(...)` 就不会现在执行,而是按原样保存。
- `#!/bin/bash` — shebang,告诉内核用哪个解释器来执行这个文件。
- `$(uname -n)` — 主机名,`awk '{print $1}' /proc/uptime` — 开机后经过的秒数(第一个字段)。

赋予执行权限:

```
chmod +x ~/work/sysinfo.sh
```

- `chmod +x` — 添加执行(x)权限。没有它,用 `./脚本` 执行时会报 `Permission denied`。

运行一下:

```
~/work/sysinfo.sh
```

- 通过路径直接执行时,由 shebang 中的 `/bin/bash` 来执行脚本(用 `bash 文件` 执行则不需要执行权限)。

确认运行正常后点击 **[校验]**。

## 参数处理与退出码

脚本的参数通过 `$1 $2 …` 接收,参数个数是 `$#`。惯例是:调用方式不对时,**把 usage 输出到 stderr,并以非 0 的退出码结束** — 因为调用方(其他脚本、CI)必须能察觉到失败。

任务:编写 `~/work/logcut.sh <日志文件> <状态码>`。

- 在 `/opt/lab/data/app.log` 格式(`… status=200 msg=…`)中,输出对应状态码的行数
- 参数不是 2 个时输出 usage + 退出码 2

编写脚本:

```
cat > ~/work/logcut.sh <<'EOF'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
grep -c "status=$2 " "$1" || true
EOF
```

- `usage() { …; }` — 定义函数。`>&2` 把消息输出到标准错误,`exit 2` 以退出码 2 结束。
- `[ $# -eq 2 ] || usage` — 参数个数(`$#`)不是 2 时(`||`)调用 usage。`[ ]` 是检查条件的命令(`test`)。
- `grep -c "status=$2 " "$1"` — 第二个参数所指状态码的行数。变量用双引号括起来,即使路径含空格也安全。

赋予执行权限:

```
chmod +x ~/work/logcut.sh
```

- 每个新脚本都要赋予执行权限。

> `grep -c` 匹配为 0 条时会返回 **退出码 1**。在 `set -e` 下脚本会因此直接终止,所以用 `|| true` 明确表示"0 条也是正常的" — 既要开启 fail-fast,又不能把不是失败的情况当成失败,这种分寸感很重要。

测试后点击 **[校验]**。

正常调用 — 输出 500 的行数:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

- 第一个参数进入 `$1`(日志文件),第二个参数进入 `$2`(状态码)。

不带参数调用 — 确认退出码为 2:

```
~/work/logcut.sh; echo "exit=$?"
```

- `$?` — 上一条命令的退出码。用 `;` 接着执行,确认 usage 之后的退出码是否为 2。

## 用 trap 保证清理

创建临时文件的脚本如果中途终止,就会留下垃圾。`trap '…' EXIT` 是一个清理钩子,**无论正常结束还是出错**,脚本结束时都一定会执行。

任务:编写 `~/work/withtmp.sh`。

- 用 `mktemp -d` 创建临时目录,并在其中随便创建一个文件
- 用 `trap` 在退出时删除临时目录
- 把临时目录的路径作为 **最后一行输出**(验证时会检查这个路径是否已被删除)

编写脚本:

```
cat > ~/work/withtmp.sh <<'EOF'
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
date > "$tmp/scratch.txt"
echo "$tmp"
EOF
```

- `mktemp -d` — 创建一个名称不会重复的临时目录,并输出其路径。
- `trap '命令' EXIT` — 无论脚本因何结束,都会在退出前执行该命令。这里是删除临时目录。
- `rm -rf "$tmp"` — 连同内容(`-r`)不经确认(`-f`)删除目录。trap 的正文用的是单引号,所以 `$tmp` 在执行时才展开。

赋予执行权限:

```
chmod +x ~/work/withtmp.sh
```

- 赋予执行权限。

运行后确认已删除:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # 出现 "No such file" 才是正常
```

- `d=$(脚本)` — 把脚本的输出(临时路径)存入变量 `d`。
- `ls -d "$d"` — 查询目录本身。用 `2>&1` 让错误信息也显示在屏幕上。目录已被删除,所以出现 `No such file` 是正常的。

确认后点击 **[校验]**。

## 修复出故障的脚本

最后是现实中最常做的事 — **修别人写的脚本**。`/opt/lab/bin/backup.sh` 是把目录备份到 /tmp 的脚本,但路径中 **一有空格** 就会失败。

查看脚本内容:

```
cat /opt/lab/bin/backup.sh
```

- 修之前先读。找找看没加引号就使用的 `$src`、`$dest`。

准备含空格路径的测试目录:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

- 路径中有空格,所以用双引号括起来作为一个参数传入。再用 `;` 接着创建一个测试文件。

用含空格的路径运行:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # 失败!
```

- 调用时用引号传入了一个参数,但脚本内部一旦不加引号使用 `$src`,它又会被拆成两个单词(单词拆分)。

原因是 **没有加引号(quoting)的变量展开**。`$src` 为 `/tmp/my app` 时,`cp -r $src/*` 会被拆成 `/tmp/my` 和 `app/*` 两个参数。这是 shell 脚本 bug 中经典中的经典。

任务:复制为 `~/work/backup-fixed.sh` 后修复。

- 所有变量展开都用 `"…"` 括起来(`"$dest"`、`"$src"/*` — 通配符 `*` 要放在引号外面!)
- 添加 `set -euo pipefail`
- 用含空格的路径运行,确认成功

创建副本:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

- `cp <源> <目标>` — 保留原文件不动,在自己的工作目录中创建副本。

用编辑器修改:

```
vim ~/work/backup-fixed.sh
```

- vim:按 `i` 进入输入模式,改完后 `Esc` → `:wq` 保存并退出。不熟悉的话也可以用 `nano`(`Ctrl+O` 保存,`Ctrl+X` 退出)。

用含空格的路径运行确认:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

- `A && B` — 只有 A 成功(退出码 0)时才执行 B。看到 `OK` 就说明修复成功。

成功后点击 **[校验]** — 模块完成。
