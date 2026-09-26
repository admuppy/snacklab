# CPU 与内存管理

接到服务器变慢的报告时,首先要看的就是 **CPU 和内存**。本模块从观察资源的工具开始,到调整进程优先级,再到容器/Pod 的实际上限 — **cgroup 内存限制与 OOM**。

> 这个实验环境是运行着 systemd 的 **容器(Pod)**。资源限制也以与真实 k8s Pod 相同的方式(由 systemd 管理的 cgroup v2)处理 — 与物理服务器不同的地方会随时指出。

先大致看看当前状态。

查看 CPU 数量:

```
nproc
```

- `nproc` — 当前进程可以使用的 CPU(核)数量。在容器中,这个值已反映了 cgroup 和亲和性限制。

查看内存情况:

```
free -h
```

- `free` — 内存与交换空间的使用量。`-h` 以 Gi/Mi 为单位显示。
- `available` 列表示"新进程实际能用到的量"(含可回收的缓存),比 `free` 列更重要。

每隔 1 秒汇总 3 次:

```
vmstat 1 3
```

- `vmstat <间隔> <次数>` — 每隔 1 秒输出一次,共 3 次。第一行是开机以来的平均值,所以从第二行开始看。
- `r` 等待运行的进程数,`si/so` 交换换入/换出,`us/sy/id/wa` CPU 用户态/内核态/空闲/IO 等待的比例。

来一张 top 快照:

```
top -b -n1 | head -12
```

- `top -b` — 以文本方式输出(batch),而不是交互界面,`-n1` — 只输出一次。`| head -12` 只看汇总区和前几个进程。

## 观察资源

`free` 汇总内存,`vmstat` 把内存、交换空间和 CPU 汇总成一行。原始数值在 `/proc/meminfo` 和 `/proc/cpuinfo` 中。

| 命令 | 看什么 |
|---|---|
| `free -h` | 总/已用/可用内存、swap |
| `vmstat 1` | 每秒的内存、swap in/out(si/so)、CPU |
| `nproc` | 此环境中可用的 CPU 数量 |
| `cat /proc/meminfo` | MemTotal、MemAvailable 等原始数据 |

任务:把当前内存总量和 CPU 数量保存为快照。在 `~/work/snapshot.txt` 中保存 **/proc/meminfo 的 MemTotal 行** 和 **`cpus=<nproc 的值>`** 行。

准备工作目录:

```
mkdir -p ~/work
```

- `mkdir -p` — 连同上级目录一起创建,已存在也不报错。

保存 MemTotal 行:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — 只挑出总内存那一行,用 `>` 保存到文件(新写入)。

追加 cpus 行:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — 双引号中的 `$( )` 同样会被替换,得到 `cpus=4` 这样的字符串。
- `>>` — **追加** 到文件末尾(`>` 是覆盖)。

查看保存的内容:

```
cat ~/work/snapshot.txt
```

- 确认是否包含两行(MemTotal、cpus=…)。

记录好后点击 **[校验]**。

## 优先级与 CPU 亲和性

CPU 不够用时,不可能对所有进程一视同仁。用 **nice 值**(-20 最高 ~ 19 最低)设定调度优先级,用 **taskset** 决定进程在哪个核上运行(CPU 亲和性)。

| 命令 | 作用 |
|---|---|
| `nice -n 19 CMD` | 以低优先级启动新进程 |
| `renice -n 5 -p PID` | 修改运行中进程的 nice 值 |
| `taskset -c 0 CMD` | 固定在 0 号 CPU 上运行 |
| `taskset -pc PID` | 查看/修改运行中进程的亲和性 |

任务:把消耗 CPU 的负载(`stress-ng --cpu 1`)**固定在 0 号 CPU** 上,以 **nice 19**(最谦让的优先级)在后台运行。这是在不影响其他服务的前提下运行批处理任务的典型做法。

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <命令>` — 把命令固定在 0 号 CPU 上运行(`-c` 是 CPU 编号列表,如 `0,2` 或 `0-3`)。
- `nice -n 19 <命令>` — 以 nice 值 19(最低优先级)运行。这两个包装命令可以叠加使用。
- `stress-ng --cpu 1 --timeout 1800s` — 让一个 CPU 以 100% 运行 30 分钟的负载生成器。
- `>/dev/null 2>&1 &` — 丢弃输出并在后台运行。

确认它是否真的这样启动了。看看 `top` 中 `NI` 列是否为 19、亲和性是否为 CPU 0。

保存负载进程的 PID:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — 在整条命令行中用正则表达式查找(`.*` 表示任意多个字符)。用 `head -1` 只把第一个 PID 存入 `pid`。

查看 nice 值:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — 只输出 PID、nice 值(`NI`)、命令名这几列。`-p "$pid"` 只看这一个进程。

查看 CPU 亲和性:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — 查看运行中进程的亲和性。加 `-c` 则以 CPU 编号列表而不是位掩码显示。

在 /proc 中交叉验证:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `/proc/<PID>/status` 中的 `Cpus_allowed_list` — 内核记录的"此进程可以运行的 CPU"列表,应与 taskset 的结果一致。

`NI=19` 且亲和性为 `0`,就点击 **[校验]**。(负载进程让它继续运行 — 不会影响下一步。)

## cgroup 内存限制与 OOM

在 Linux 中,强制执行进程组 CPU、内存上限的是 **cgroup v2**。容器的资源限制、systemd 服务的 `MemoryMax=`,以及 **k8s Pod 的 `resources.limits.memory`,全都运行在它之上**。这里我们 **创建一个设有内存上限的 cgroup**,让内存超限,亲眼看看内核的 **OOM Killer** 如何动作。

先看看 cgroup 树和控制器(controller)。

查看文件系统类型:

```
stat -fc %T /sys/fs/cgroup        # 应为 cgroup2fs
```

- `stat -f` — 显示的不是文件本身,而是该文件所在 **文件系统** 的信息,`-c %T` — 通过格式指定只输出类型名。`cgroup2fs` 即为 cgroup v2。

查看可用的控制器:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- 此 cgroup 中可用的控制器列表(`cpu`、`memory`、`io`、`pids` …)。必须有 `memory` 才能设置内存上限。

> 💡 这个 Pod 共享 **宿主机的 cgroup 命名空间**,也就是说 `/sys/fs/cgroup` 是整个节点的树。在这里手动 `mkdir` 会 **污染节点**,并与其他 Pod 冲突。所以设有上限的 cgroup 交给 systemd,**在 Pod 自己的 slice 内部** 创建 — 这与 k8s 为每个 Pod 创建 cgroup 的方式完全相同。

任务:给名为 `lab.slice` 的 slice 设置 **内存 24M、交换 0** 的上限,并在其中运行一个分配 200MB 的进程来触发 OOM。

```
# 给 slice 设置内存上限(--runtime = 只到重启为止,不写入磁盘)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <单元> 键=值…` — 修改运行中单元(这里是 slice)的资源属性。
- `MemoryMax=24M` — cgroup 的 `memory.max`(硬上限),`MemorySwapMax=0` — 不允许逃到交换空间。
- `--runtime` — 重启后即消失的临时设置(保存在 `/run` 中)。

接下来在这个 slice 中超额分配内存。`systemd-run --slice=lab.slice --scope` 会在指定的 slice 下创建临时 scope 并在其中执行命令。

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — 命令仍在当前终端中执行,但被放入一个新的临时 scope(cgroup)。`--slice=lab.slice` 把它放到设有上限的 slice 之下。
- `python3 -c "…"` — 一行程序,创建 200 个 4MB 的字节数组(≈800MB)。行尾的 `\` 表示接到下一行。

应该会看到 `Killed` — 超过 24M 上限的瞬间,内核就杀掉了进程。痕迹会留在该 slice 的 cgroup 的 `memory.events` 中。slice 的实际 cgroup 路径可以由 systemd 告诉你。

保存 slice 的 cgroup 路径:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — 输出 slice 的 cgroup 路径(`/…/lab.slice`)。在前面加上 `/sys/fs/cgroup`,把实际目录路径存入变量 `cg`。

查看内存上限:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — 该 cgroup 的内存硬上限(字节)。24M = 24×1024×1024 = 25165824。

查看 OOM 事件:

```
cat "$cg/memory.events"     # 查看 oom_kill 项
```

- `memory.events` — 该 cgroup 中发生的内存事件的累计次数。`max` 达到上限,`oom` 发生 OOM,`oom_kill` 因 OOM 被杀掉的进程数。

看到 `oom_kill 1`(或更多)就说明 OOM 确实发生了。确认后点击 **[校验]**,模块即完成。(`lab.slice` 在 Pod 存活期间一直保留,Pod 消失后会被自动清理。)
