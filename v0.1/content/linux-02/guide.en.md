# Processes and Signals

When a server is slow or acting strangely, the first thing you do is **look at its processes**. In this module you'll explore processes with ps and /proc, control them with signals, run jobs detached from the terminal, and track down the process holding a port.

Three daemons are already running in the lab environment as systemd units.

| Process | What it is |
|---|---|
| `lab-worker` | An ordinary worker — your target for step 1 |
| `lab-stubborn` | A zombie-like thing that **ignores SIGTERM** — dispatched in step 2 |
| `lab-listener` | Something occupying 127.0.0.1:5555 — tracked down in step 4 |

## Exploring processes — ps and /proc

Start by scanning all processes.

Scan the full list:

```
ps aux | head
```

- `ps aux` — processes of all users (`a`, and `x`: also those without a terminal), with user, CPU%, MEM% and command (`u`).
- `| head` — only the first 10 lines.

View as a tree:

```
ps -ef --forest | head -30
```

- `ps -ef` — every process (`-e`) in full format (`-f`) including PID and PPID.
- `--forest` — draws parent/child relations as an indented tree; `head -30` keeps the first 30 lines.

Let's find `lab-worker`. `pgrep -f` matches the pattern against the full command line and returns PIDs.

```
pgrep -f /opt/lab/bin/lab-worker
```

- `pgrep <pattern>` — prints only the PIDs of matching processes.
- `-f` — match against the **full command line** (path and arguments), not just the process name.

Everything ps shows you comes from the **/proc filesystem**. Look inside the PID directory yourself (cmdline is NUL(\0)-separated, so convert it with tr to read it).

Save the PID to a variable:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

- `$( ... )` — command substitution; stores the output (the PID) in the shell variable `pid`, used later as `$pid`.
- `| head -1` — keep just the first PID if several match.

List the PID directory:

```
ls /proc/$pid/
```

- `/proc/<PID>/` — a virtual directory where the kernel exposes process info as files: `cmdline` (arguments), `status` (state, memory), `fd/` (open files), `environ` (environment), …

Read cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

- `tr '\0' ' '` — translates NUL characters in the input to spaces.
- `< file` — feeds the file on stdin; `; echo` adds a final newline.

Task: save the results to files.

- `~/work/worker.pid` — the PID of lab-worker
- `~/work/worker.cmdline` — the contents of `/proc/<PID>/cmdline` (tr-converted)

Create the work directory:

```
mkdir -p ~/work
```

- `mkdir -p` — creates parent directories as needed and doesn't fail if it already exists.

Save the PID:

```
echo "$pid" > ~/work/worker.pid
```

- `echo "$pid"` prints the variable; `> file` saves that output to the file (overwrite).

Save the cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

- The same `tr` command you ran above, this time saved to a file with `>`.

Once saved, press **[Check]**.

## Controlling processes with signals

`kill` is not a command that kills processes — it **sends signals**.

| Signal | Number | Behavior |
|---|---|---|
| SIGTERM | 15 | The default. A process **may ignore it or clean up before exiting** |
| SIGKILL | 9 | The kernel removes the process immediately. **Cannot be ignored**, no chance to clean up |
| SIGHUP | 1 | By convention, often used for "reload configuration" |

`lab-stubborn` is written to trap and ignore TERM and INT. See for yourself.

Confirm it's running:

```
pgrep -f /opt/lab/bin/lab-stubborn
```

- A PID means it is alive; no output (exit code 1) means no such process.

Send SIGTERM:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

- `pkill` — sends a signal to matching processes (`pgrep` + `kill`).
- `-TERM` — the signal (SIGTERM, 15); `-f` matches the full command line.
- `sudo` — the process belongs to another user (root), so admin rights are needed.

Check it's still alive:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # still alive
```

- `sleep 1` — wait a second for the signal to be handled, then `;` runs the check again.

One caveat: this process is managed by a **systemd unit** (lab-stubborn.service). You could just kill -9 the process, but a unit-managed process should properly be handled at the unit level. However, `systemctl stop` sends TERM first and waits for the timeout (90s by default), which is too slow for this one — instead, **send SIGKILL directly through the unit**.

Send SIGKILL through the unit:

```
sudo systemctl kill -s KILL lab-stubborn
```

- `systemctl kill <unit>` — sends a signal to **every process** in the unit.
- `-s KILL` — the signal is SIGKILL (9), which a process cannot catch, so it is removed immediately.

Confirm termination:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "terminated"
```

- `A || B` — runs B only if A fails (exit code ≠ 0); when `pgrep` finds nothing, the message is printed.

Once it's dead, press **[Check]**.

## Detached background execution

A process started with `&` in a terminal receives SIGHUP and dies when the terminal disconnects. To survive the end of the session, use **nohup** (ignore HUP + redirect output) or **setsid** (detach into a new session).

`/opt/lab/bin/lab-batch` is a batch job that writes a timestamp every 10 seconds to the file given as its first argument. Launch it detached from the terminal, sending its log to `~/work/batch.log`.

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

- `nohup <cmd>` — ignores SIGHUP so the command keeps running after the terminal closes.
- `>/dev/null 2>&1` — discard stdout, and send stderr (2) to the same place as stdout (1).
- The trailing `&` runs it in the background and returns the prompt immediately.

Check the parent process. Once detached from the shell and orphaned, PID 1 (systemd in this pod) adopts it.

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

- `ps -o pid,ppid,cmd` — choose the columns: PID, parent PID and command.
- `-p $(pgrep ...)` — only the PID(s) produced by the command substitution.

Check the log:

```
tail ~/work/batch.log
```

- `tail <file>` — the last 10 lines; use `tail -f` to keep following (Ctrl+C to stop).

If PPID is 1 and the log is accumulating, press **[Check]**.

> In production, the right answer for daemons like this is a systemd unit (or `systemd-run`) — covered in module linux-06.

## Tracking the process holding a port

"Who's holding this port?" is the most common diagnostic question. Use `ss` (socket statistics) to find the owner of port 5555. You need `-p` to see process names, and sudo to see other users' processes.

List all listening sockets:

```
sudo ss -ltnp
```

- `ss` — socket statistics (successor of netstat). `-l` listening only, `-t` TCP, `-n` numeric ports, `-p` show the owning process.

Query only port 5555:

```
sudo ss -ltnp sport = :5555
```

- `sport = :5555` — a filter expression: only sockets whose source (local) port is 5555.

`lsof` gives the same answer.

```
sudo lsof -i :5555
```

- `lsof` — lists open files (sockets are files on Linux); `-i :5555` — only network connections on port 5555.

Task: save the **process name** occupying port 5555 to `~/work/port-owner.txt`.

Extract and save the process name:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

- `grep -o` — prints **only the matched part**, not the whole line — pulls the name out of `users:(("python3",pid=…))`.
- `head -1` keeps one, and `>` saves it.

Verify the saved content:

```
cat ~/work/port-owner.txt
```

- `cat <file>` — prints the file's contents.

If you're curious what this python3 actually is, dig through /proc by its PID — exactly the technique from step 1. Once saved, press **[Check]**.
