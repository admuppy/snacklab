# CPU and Memory Management

When a server is reported "slow," the first things you look at are **CPU and memory**. This module covers the tools to observe resources, adjusting process priority, and the real ceiling that **cgroup memory limits and the OOM killer** impose on a container/pod.

> This lab environment is a **container (pod)** running systemd. Resource limits are handled the same way a real k8s pod handles them (cgroup v2 managed by systemd) — we point out where a physical server differs as it comes up.

First, a quick look at the current state.

Check the CPU count:

```
nproc
```

- `nproc` — number of CPUs (cores) available to the current process; inside a container it reflects cgroup and affinity limits.

Check memory status:

```
free -h
```

- `free` — memory and swap usage; `-h` for Gi/Mi units.
- The `available` column — what new processes can really get (including reclaimable cache) — matters more than `free`.

Three 1-second summaries:

```
vmstat 1 3
```

- `vmstat <interval> <count>` — 3 samples 1 s apart. The first line is the average since boot, so read from the second.
- `r` runnable processes, `si/so` swap in/out, `us/sy/id/wa` CPU user/kernel/idle/IO-wait %.

One top snapshot:

```
top -b -n1 | head -12
```

- `top -b` — plain-text (batch) output instead of the interactive screen, `-n1` — one iteration. `| head -12` keeps the summary and the top few processes.

## Observing resources

`free` summarizes memory; `vmstat` folds memory, swap, and CPU into one line. The raw numbers live in `/proc/meminfo` and `/proc/cpuinfo`.

| Command | What it shows |
|---|---|
| `free -h` | total/used/available memory, swap |
| `vmstat 1` | 1-second memory, swap in/out (si/so), CPU |
| `nproc` | number of CPUs available here |
| `cat /proc/meminfo` | raw MemTotal, MemAvailable, ... |

Task: capture a snapshot of the current memory total and CPU count. Save the **MemTotal line from /proc/meminfo** and a **`cpus=<nproc>`** line into `~/work/snapshot.txt`.

Prepare the work directory:

```
mkdir -p ~/work
```

- `mkdir -p` — creates parent directories as needed and doesn't fail if it already exists.

Save the MemTotal line:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — picks the total-memory line and saves it with `>` (new file).

Append the cpus line:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — `$( )` expands inside double quotes, giving a string like `cpus=4`.
- `>>` — **appends** to the file (`>` would overwrite).

Verify the saved content:

```
cat ~/work/snapshot.txt
```

- Confirm both lines (MemTotal, cpus=…) are there.

Once saved, press **[Check]**.

## Priority and CPU affinity

When CPU is scarce you can't treat every process equally. The **nice value** (-20 high … 19 low) sets scheduler priority, and **taskset** pins which cores a process runs on (CPU affinity).

| Command | Role |
|---|---|
| `nice -n 19 CMD` | start a new process at low priority |
| `renice -n 5 -p PID` | change the nice value of a running process |
| `taskset -c 0 CMD` | run pinned to CPU 0 |
| `taskset -pc PID` | view/change affinity of a running process |

Task: run a CPU load (`stress-ng --cpu 1`) **pinned to CPU 0** at **nice 19** (the most yielding priority), in the background. This is the classic pattern for running batch work without disturbing other services.

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <cmd>` — runs the command pinned to CPU 0 (`-c` takes a CPU list such as `0,2` or `0-3`).
- `nice -n 19 <cmd>` — runs with nice 19 (lowest priority). The two wrappers can be stacked.
- `stress-ng --cpu 1 --timeout 1800s` — load generator that burns one CPU at 100% for 30 minutes.
- `>/dev/null 2>&1 &` — discard output and run in the background.

Confirm it really launched that way — check that `top` shows `NI` of 19 and the affinity is CPU 0.

Save the load process PID:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — regex match on the full command line (`.*` = any characters). `head -1` keeps the first PID in `pid`.

Check the nice value:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — only the PID, nice value (`NI`) and command-name columns; `-p "$pid"` for that one process.

Check the CPU affinity:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — shows a running process's affinity; `-c` prints a CPU list instead of a bitmask.

Cross-check via /proc:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `Cpus_allowed_list` in `/proc/<PID>/status` — the kernel's record of which CPUs the process may run on; it should match taskset.

If `NI=19` and affinity is `0`, press **[Check]**. (Leave the load running — it does not affect the next step.)

## cgroup memory limits and OOM

On Linux, the CPU/memory ceilings for a group of processes are enforced by **cgroup v2**. Container resource limits, a systemd service's `MemoryMax=`, and **a k8s pod's `resources.limits.memory` all ride on this**. Here you'll **create a memory-limited cgroup**, overrun it, and watch the kernel's **OOM Killer** fire.

First look at the cgroup tree and its controllers.

Check the filesystem type:

```
stat -fc %T /sys/fs/cgroup        # must be cgroup2fs
```

- `stat -f` — info about the **filesystem** holding the path rather than the file; `-c %T` prints just the type name. `cgroup2fs` means cgroup v2.

Check the available controllers:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- Controllers available in this cgroup (`cpu`, `memory`, `io`, `pids`, …). `memory` must be present to set a memory limit.

> 💡 This pod shares the **host cgroup namespace**, so `/sys/fs/cgroup` is the whole node's tree. Hand-`mkdir`ing into it would **pollute the node** and collide with other pods. So we let systemd create the limited cgroup **inside the pod's own slice** — exactly how k8s carves out a cgroup per pod.

Task: put a **24M memory, 0 swap** cap on a slice named `lab.slice`, then run a process inside it that allocates 200MB to trigger an OOM.

```
# put a memory ceiling on the slice (--runtime = until reboot, not written to disk)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <unit> key=value…` — changes resource properties of a running unit (a slice here).
- `MemoryMax=24M` — the cgroup `memory.max` hard limit; `MemorySwapMax=0` — no escaping into swap.
- `--runtime` — temporary; stored under `/run` and gone after reboot.

Now over-allocate inside that slice. `systemd-run --slice=lab.slice --scope` creates a transient scope under the slice and runs your command there.

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — runs the command in your terminal but inside a new transient scope (cgroup); `--slice=lab.slice` puts it under the limited slice.
- `python3 -c "…"` — a one-liner allocating 200 byte arrays of 4 MB (≈800 MB). The trailing `\` continues the line.

You'll see `Killed` — the kernel killed the process the moment it crossed the 24M cap. The trace is recorded in the slice's `memory.events`. systemd tells you the slice's actual cgroup path.

Save the slice's cgroup path:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — prints the slice's cgroup path (`/…/lab.slice`); prefixing `/sys/fs/cgroup` gives the real directory, stored in `cg`.

Check the memory cap:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — the cgroup's hard memory limit in bytes: 24M = 24×1024×1024 = 25165824.

Check the OOM events:

```
cat "$cg/memory.events"     # look for the oom_kill line
```

- `memory.events` — cumulative memory-event counters: `max` limit hits, `oom` OOM events, `oom_kill` processes killed by OOM.

If you see `oom_kill 1` (or more), an OOM really occurred. Once confirmed, press **[Check]** to complete the module. (`lab.slice` stays for the life of the pod and is cleaned up automatically when the pod goes away.)
