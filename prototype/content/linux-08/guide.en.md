# Capstone — Reviving a Dead Service

2 a.m., the pager goes off: **"lab-app won't start."** This module is a capstone scenario where you handle a real incident end to end, using everything you've learned so far (systemd, journald, signal and port tracking, file permissions).

This time you won't be given every command — the **order of diagnosis** is the learning objective. If you get stuck, recall the tools from earlier modules: `systemctl status/cat`, `journalctl -u`, `sudo ss -ltnp`, `ls -l`, `sudo -u <user>`.

Start by assessing the situation.

```
systemctl status lab-app --no-pager
```

## Diagnosing startup failure — 203/EXEC

When status isn't enough, the journal knows the answer.

```
journalctl -u lab-app --no-pager | tail -20
```

`status=203/EXEC` — the code you met in linux-06. Find out **what the unit was trying to execute** when it failed.

```
systemctl cat lab-app
```

Compare the interpreter path in ExecStart against what actually exists on this system (`ls /usr/bin/python3*`). It will be pointing at a version that doesn't exist — a common accident when a deploy script was written for a different server.

Task: fix ExecStart to an interpreter that exists and `daemon-reload`. Once fixed, press **[Check]**.

> start still won't succeed — incidents are rarely a single layer. On to the next step.

## Resolving a port conflict

Now starting it produces a different error.

Try starting the service:

```
sudo systemctl start lab-app
```

Check the error log:

```
journalctl -u lab-app --no-pager | tail -5
```

`Address already in use` — **something else has claimed** the 8080 that lab-app needs. Use the port-tracking skills from linux-02 and linux-07 to find the culprit.

```
sudo ss -ltnp | grep 8080
```

To trace a PID back to its unit, `systemctl status <PID>` is convenient. The culprit is a legacy unit slated for decommissioning. Stopping it isn't enough — it will come back on reboot, so you must **disable it too**.

Task: take the squatter down with `disable --now` and start lab-app. When lab-app is active, press **[Check]**.

## Resolving a permission problem

The service is up... but we're not done yet.

```
curl -i http://127.0.0.1:8080/index.html
```

**404** — yet the file clearly exists (`ls -l /srv/lab-app/`). Why?

Two clues. ① The unit has `User=labapp` — the service runs as labapp, not root. ② index.html is `root:root 600` — **labapp cannot read it.** This server (http.server) returns 404 when it can't open a file. A textbook "file exists but 404" permission problem.

Build the habit of verifying suspicions — read the file as that user.

```
sudo -u labapp cat /srv/lab-app/index.html
```

Task: fix the ownership or permissions so labapp can read it (with the linux-01 mindset — don't open it wider than necessary). When curl returns `LAB APP OK`, press **[Check]**.

## Preventing recurrence and wrap-up

Recovery is a set of two: "make it work now" + **"make it survive next time."** The checklist:

1. Is lab-app **enabled**? (a recovery that dies again on reboot is not a recovery)
2. Preserve the final response as evidence — save it to `~/work/final.txt`

Enable start at boot:

```
sudo systemctl enable lab-app
```

Save the final response:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

Verify the saved content:

```
cat ~/work/final.txt
```

Press **[Check]** and you've completed the Linux track. Remember: the triple failure you resolved today (wrong path → port conflict → permissions) is the most common combination in real incident reports — and all three were **known first by journal, ss, and ls -l**.
