# Capstone — Reviving a Dead Service

2 a.m., the pager goes off: **"lab-app won't start."** This module is a capstone scenario where you handle a real incident end to end, using everything you've learned so far (systemd, journald, signal and port tracking, file permissions).

This time you won't be given every command — the **order of diagnosis** is the learning objective. If you get stuck, recall the tools from earlier modules: `systemctl status/cat`, `journalctl -u`, `sudo ss -ltnp`, `ls -l`, `sudo -u <user>`.

Start by assessing the situation.

```
systemctl status lab-app --no-pager
```

- Look for the first clue in the `Active:` line and the last few log lines. `--no-pager` prints without less.

## Diagnosing startup failure — 203/EXEC

When status isn't enough, the journal knows the answer.

```
journalctl -u lab-app --no-pager | tail -20
```

- `journalctl -u <unit>` — only that unit's logs; `| tail -20` focuses on the latest 20 lines.

`status=203/EXEC` — the code you met in linux-06. Find out **what the unit was trying to execute** when it failed.

```
systemctl cat lab-app
```

- Shows the unit file as-is. Watch `ExecStart=` (what runs) and `User=` (who runs it).

Compare the interpreter path in ExecStart against what actually exists on this system (`ls /usr/bin/python3*`). It will be pointing at a version that doesn't exist — a common accident when a deploy script was written for a different server.

Task: fix ExecStart to an interpreter that exists and `daemon-reload`. Once fixed, press **[Check]**.

> start still won't succeed — incidents are rarely a single layer. On to the next step.

## Resolving a port conflict

Now starting it produces a different error.

Try starting the service:

```
sudo systemctl start lab-app
```

- Try starting again after the fix; if it fails, the next log tells you the new cause.

Check the error log:

```
journalctl -u lab-app --no-pager | tail -5
```

- Only the log of that last attempt matters, so the final 5 lines.

`Address already in use` — **something else has claimed** the 8080 that lab-app needs. Use the port-tracking skills from linux-02 and linux-07 to find the culprit.

```
sudo ss -ltnp | grep 8080
```

- Finds the socket listening on 8080 and its process (`users:(("name",pid=…))`). Note the PID.

To trace a PID back to its unit, `systemctl status <PID>` is convenient. The culprit is a legacy unit slated for decommissioning. Stopping it isn't enough — it will come back on reboot, so you must **disable it too**.

Task: take the squatter down with `disable --now` and start lab-app. When lab-app is active, press **[Check]**.

## Resolving a permission problem

The service is up... but we're not done yet.

```
curl -i http://127.0.0.1:8080/index.html
```

- `curl -i` — includes the status line (`HTTP/1.0 404 …`) and headers before the body.

**404** — yet the file clearly exists (`ls -l /srv/lab-app/`). Why?

Two clues. ① The unit has `User=labapp` — the service runs as labapp, not root. ② index.html is `root:root 600` — **labapp cannot read it.** This server (http.server) returns 404 when it can't open a file. A textbook "file exists but 404" permission problem.

Build the habit of verifying suspicions — read the file as that user.

```
sudo -u labapp cat /srv/lab-app/index.html
```

- `sudo -u <user> <cmd>` — runs the command as that user: read the file with exactly the rights the service has.

Task: fix the ownership or permissions so labapp can read it (with the linux-01 mindset — don't open it wider than necessary). When curl returns `LAB APP OK`, press **[Check]**.

## Preventing recurrence and wrap-up

Recovery is a set of two: "make it work now" + **"make it survive next time."** The checklist:

1. Is lab-app **enabled**? (a recovery that dies again on reboot is not a recovery)
2. Preserve the final response as evidence — save it to `~/work/final.txt`

Enable start at boot:

```
sudo systemctl enable lab-app
```

- `enable` — registers autostart at boot (creates the symlink); the running service is unaffected. Check with `systemctl is-enabled lab-app`.

Save the final response:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

- Saves the body returned by `curl -s` to a file with `>`.

Verify the saved content:

```
cat ~/work/final.txt
```

- Confirm the saved response reads `LAB APP OK`.

Press **[Check]** and you've completed the Linux track. Remember: the triple failure you resolved today (wrong path → port conflict → permissions) is the most common combination in real incident reports — and all three were **known first by journal, ss, and ls -l**.
