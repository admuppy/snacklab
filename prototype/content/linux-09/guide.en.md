# CPU and Memory Management

When a server is reported "slow," the first things you look at are **CPU and memory**. This module covers the tools to observe resources, adjusting process priority, and the real ceiling that **cgroup memory limits and the OOM killer** impose on a container/pod.

> This lab environment is a **container (pod)** running systemd. Resource limits are handled the same way a real k8s pod handles them (cgroup v2 managed by systemd) — we point out where a physical server differs as it comes up.

First, a quick look at the current state.

Check the CPU count:

```
nproc
```

Check memory status:

```
free -h
```

Three 1-second summaries:

```
vmstat 1 3
```

One top snapshot:

```
top -b -n1 | head -12
```

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

Save the MemTotal line:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

Append the cpus line:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

Verify the saved content:

```
cat ~/work/snapshot.txt
```

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

Confirm it really launched that way — check that `top` shows `NI` of 19 and the affinity is CPU 0.

Save the load process PID:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

Check the nice value:

```
ps -o pid,ni,comm -p "$pid"
```

Check the CPU affinity:

```
taskset -pc "$pid"
```

Cross-check via /proc:

```
grep Cpus_allowed_list /proc/$pid/status
```

If `NI=19` and affinity is `0`, press **[Check]**. (Leave the load running — it does not affect the next step.)

## cgroup memory limits and OOM

On Linux, the CPU/memory ceilings for a group of processes are enforced by **cgroup v2**. Container resource limits, a systemd service's `MemoryMax=`, and **a k8s pod's `resources.limits.memory` all ride on this**. Here you'll **create a memory-limited cgroup**, overrun it, and watch the kernel's **OOM Killer** fire.

First look at the cgroup tree and its controllers.

Check the filesystem type:

```
stat -fc %T /sys/fs/cgroup        # must be cgroup2fs
```

Check the available controllers:

```
cat /sys/fs/cgroup/cgroup.controllers
```

> 💡 This pod shares the **host cgroup namespace**, so `/sys/fs/cgroup` is the whole node's tree. Hand-`mkdir`ing into it would **pollute the node** and collide with other pods. So we let systemd create the limited cgroup **inside the pod's own slice** — exactly how k8s carves out a cgroup per pod.

Task: put a **24M memory, 0 swap** cap on a slice named `lab.slice`, then run a process inside it that allocates 200MB to trigger an OOM.

```
# put a memory ceiling on the slice (--runtime = until reboot, not written to disk)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

Now over-allocate inside that slice. `systemd-run --slice=lab.slice --scope` creates a transient scope under the slice and runs your command there.

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

You'll see `Killed` — the kernel killed the process the moment it crossed the 24M cap. The trace is recorded in the slice's `memory.events`. systemd tells you the slice's actual cgroup path.

Save the slice's cgroup path:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

Check the memory cap:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

Check the OOM events:

```
cat "$cg/memory.events"     # look for the oom_kill line
```

If you see `oom_kill 1` (or more), an OOM really occurred. Once confirmed, press **[Check]** to complete the module. (`lab.slice` stays for the life of the pod and is cleaned up automatically when the pod goes away.)
