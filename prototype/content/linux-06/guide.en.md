# systemd Services and journald

In linux-02 we launched a daemon with nohup, but real-world daemons are all **systemd units** — automatic start at boot, restart on death, and logs collected by journald. In this module you'll write units yourself, diagnose and repair a broken unit with the journal, and replace cron with a timer.

Scan the units on the system now.

List the service units:

```
systemctl list-units --type=service --no-pager | head -15
```

Check the cron service status:

```
systemctl status cron --no-pager
```

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

After creating or editing a unit file, **always daemon-reload** — systemd doesn't read the files directly; it uses the copy loaded in memory.

Reload systemd:

```
sudo systemctl daemon-reload
```

Enable and start now:

```
sudo systemctl enable --now hello-web
```

Check the service status:

```
systemctl status hello-web --no-pager
```

Test the response:

```
curl -s http://127.0.0.1:8080/ | head -3
```

`enable --now` means "register for boot-time start + start now". Once you see a response, press **[Check]**.

## Fixing a broken unit with journald

A unit named `lab-report.service` is deployed but fails to start. See for yourself.

Try starting the service:

```
sudo systemctl start lab-report
```

See the failed status:

```
systemctl status lab-report --no-pager
```

Investigation happens with **journalctl**. Use `-u` to select the unit, along with `-e` (jump to end) or `--no-pager`.

```
journalctl -u lab-report --no-pager | tail -20
```

You should see `status=203/EXEC` — a classic systemd exit code meaning **the ExecStart executable cannot be executed** (path typo, missing execute permission, shebang problem). Compare the path the unit points at with the actual files.

Show the path the unit points at:

```
systemctl cat lab-report
```

Check the actual files:

```
ls -l /opt/lab/bin/
```

Task: fix the ExecStart path (don't forget daemon-reload) and start the service.

Edit the unit file:

```
sudo vim /etc/systemd/system/lab-report.service
```

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

Write the drop-in file:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

Reload systemd:

```
sudo systemctl daemon-reload
```

Restart the service:

```
sudo systemctl restart hello-web
```

Let's test that it really comes back. Kill the main PID with SIGKILL and check the status a few seconds later.

Show the main PID:

```
systemctl show -p MainPID --value hello-web
```

Kill the process:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

Check the status after a moment:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

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

Reload systemd:

```
sudo systemctl daemon-reload
```

Enable and start the timer:

```
sudo systemctl enable --now lab-tick.timer
```

`Type=oneshot` is for jobs that "run once and finish". Note that what you enable is **the timer, not the service**. Confirm it's registered and press **[Check]** to complete the module.

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```
