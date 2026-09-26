# systemd Services and journald

In linux-02 we launched a daemon with nohup, but real-world daemons are all **systemd units** — automatic start at boot, restart on death, and logs collected by journald. In this module you'll write units yourself, diagnose and repair a broken unit with the journal, and replace cron with a timer.

Scan the units on the system now.

List the service units:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — units loaded in memory; `--type=service` for services only, `--no-pager` to print without less.
- `| head -15` — first 15 lines. Columns: LOAD (file loaded), ACTIVE (high-level state), SUB (detailed state).

Check the cron service status:

```
systemctl status cron --no-pager
```

- `systemctl status <unit>` — state (`Active:`), main PID, cgroup process tree and the last few log lines on one screen.

## Writing a service unit

The smallest service unit needs just three sections.

| Section | Role |
|---|---|
| `[Unit]` | description, dependencies (Description, After, …) |
| `[Service]` | how to run (ExecStart, Restart, User, …) |
| `[Install]` | where it hooks in when enabled (WantedBy) |

Task: create `hello-web.service`, running a static HTTP server on port 8080.

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

- `sudo tee <file> <<'EOF'` — the here-doc body is written by `tee` running as root (`sudo cat > file` fails because your own shell does the redirect).
- `/etc/systemd/system/` — where admin-made unit files live; they take precedence over packaged units (`/usr/lib/systemd/system/`).
- `ExecStart=` — the command to run (absolute path). `WantedBy=multi-user.target` — enabling hooks it into the normal boot target.

After creating or editing a unit file, **always daemon-reload** — systemd doesn't read the files directly; it uses the copy loaded in memory.

Reload systemd:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — makes systemd re-read unit files. It does not restart services.

Enable and start now:

```
sudo systemctl enable --now hello-web
```

- `enable` — symlinks the unit into its `WantedBy` target so it starts at boot; `--now` — also `start` it right away.
- The `.service` suffix may be omitted.

Check the service status:

```
systemctl status hello-web --no-pager
```

- `Active: active (running)` with a main PID (`python3`) means it started correctly.

Test the response:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — sends the HTTP request without a progress bar and prints the body; `| head -3` keeps the first 3 lines (directory-listing HTML).

`enable --now` means "register for boot-time start + start now". Once you see a response, press **[Check]**.

## Fixing a broken unit with journald

A unit named `lab-report.service` is deployed but fails to start. See for yourself.

Try starting the service:

```
sudo systemctl start lab-report
```

- `systemctl start` — starts the service now (independent of boot enablement). On failure it prints `Job … failed` and suggests commands to inspect it.

See the failed status:

```
systemctl status lab-report --no-pager
```

- Look at `Active: failed` and the `code=exited, status=…` line for the failure code.

Investigation happens with **journalctl**. Use `-u` to select the unit, along with `-e` (jump to end) or `--no-pager`.

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — reads journald logs. `-u <unit>` only that unit, `--no-pager` print directly, `| tail -20` last 20 lines.
- Follow live with `-f`, this boot only with `-b`, a time window with `--since "10 min ago"`.

You should see `status=203/EXEC` — a classic systemd exit code meaning **the ExecStart executable cannot be executed** (path typo, missing execute permission, shebang problem). Compare the path the unit points at with the actual files.

Show the path the unit points at:

```
systemctl cat lab-report
```

- `systemctl cat <unit>` — the unit file(s) systemd actually uses (including drop-ins), with their paths. Check the `ExecStart=` line.

Check the actual files:

```
ls -l /opt/lab/bin/
```

- `ls -l` — file names together with permissions (is `x` set?). Compare with the unit's path character by character.

Task: fix the ExecStart path (don't forget daemon-reload) and start the service.

Edit the unit file:

```
sudo vim /etc/systemd/system/lab-report.service
```

- Unit files are root-owned, so open with `sudo`. vim: `i` to insert, `Esc` → `:wq` to save and quit.
- Forget `daemon-reload` afterwards and systemd keeps failing with the old path.

Reload systemd:

```
sudo systemctl daemon-reload
```

Start the service:

```
sudo systemctl start lab-report
```

Follow the log:

```
tail -f /var/log/lab/report.log   # exit with Ctrl-C
```

- `tail -f` — follows the end of the file and prints new lines as they appear — proof the service is actually working.

When it's active (running), press **[Check]**.

## Self-healing with Restart policy

Processes die — OOM, bugs, mistakes. systemd's `Restart=` is the safety net that brings them back automatically.

| Value | Restart condition |
|---|---|
| `no` (default) | never |
| `on-failure` | only on abnormal exit (code≠0, signal) |
| `always` | unconditionally, even after a clean exit |

Task: add `Restart=on-failure` and `RestartSec=1` to hello-web. You can edit the unit file directly, or better, use a **drop-in** that leaves the original untouched (`systemctl edit` is interactive, so here we write the file directly).

Create the drop-in directory:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<unit>.d/` — a drop-in directory; `*.conf` files inside override the original unit, and survive package updates to it.

Write the drop-in file:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- Only the keys to add under `[Service]`. `Restart=on-failure` restarts after abnormal exits, `RestartSec=1` waits 1 s first.

Reload systemd:

```
sudo systemctl daemon-reload
```

Restart the service:

```
sudo systemctl restart hello-web
```

- `restart` — stop then start, so the process comes back with the new drop-in applied.

Let's test that it really comes back. Kill the main PID with SIGKILL and check the status a few seconds later.

Show the main PID:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — prints unit properties as `key=value`; `-p MainPID` picks one, `--value` drops the `MainPID=` prefix.

Kill the process:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- `kill -9` (SIGKILL) on the main PID from `$( ... )` — an uncatchable forced kill. That is an abnormal exit, so `on-failure` applies.

Check the status after a moment:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- `sleep 3` gives the restart (RestartSec=1) time, then shows the first 5 status lines. `Main PID` should differ from before.

If it's active again with a new PID, it worked — press **[Check]**. (The check performs the same experiment once more.)

## Periodic jobs with timers

The systemd replacement for cron is the **timer**. Logs land in the journal and failures are managed as units, so most periodic jobs on modern distros are timers. The setup is a pair: **a service (what to do) + a timer (when)**.

Task: create a `lab-tick` timer that records the time to `/var/log/lab/tick.log` every minute.

Write the service unit (what to do):

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — a run-to-completion job; when the command exits it counts as success and goes back to inactive.
- `bash -c '…'` — redirection (`>>`, append) is a shell feature, so it runs through bash. `date -Is` prints an ISO 8601 timestamp.

Write the timer unit (when):

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

- `OnCalendar=*-*-* *:*:00` — calendar syntax `year-month-day hour:minute:second`: second 0 of every minute = every minute.
- `AccuracySec=1s` — tightens the allowed start delay (default 1 min) to 1 s.
- A timer starts the `.service` of the same name (`lab-tick.service`); `WantedBy=timers.target` is used when enabling.

Reload systemd:

```
sudo systemctl daemon-reload
```

Enable and start the timer:

```
sudo systemctl enable --now lab-tick.timer
```

- Spell out `.timer`; without a suffix the name is taken as `.service`.

`Type=oneshot` is for jobs that "run once and finish". Note that what you enable is **the timer, not the service**. Confirm it's registered and press **[Check]** to complete the module.

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — active timers with their `NEXT` and `LAST` run times.
- `grep -E 'NEXT|lab-tick'` — keeps the header and the lab-tick line (`|` is OR in extended regex).
