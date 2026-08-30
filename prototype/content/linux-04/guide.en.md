# Bash Scripting

When a one-liner starts getting repeated, it's time to make it a script. In this module you'll learn to write **not scripts that never die, but scripts that die immediately when something goes wrong (fail-fast)** — because a script that quietly produces wrong results is the most dangerous kind.

Everything goes under `~/work/`. Use vim or nano as you like, or create files with a `cat > file <<'EOF'` heredoc.

## A safe script skeleton

The first two lines of every script are practically fixed.

```
#!/bin/bash
set -euo pipefail
```

| Option | Effect |
|---|---|
| `-e` | exit immediately when a command fails |
| `-u` | error on referencing undefined variables (catches typos) |
| `-o pipefail` | a failure in the middle of a pipe counts as a failure |

Task: write `~/work/sysinfo.sh`. Requirements:

- bash shebang + `set -euo pipefail`
- output one line `host=<hostname>` and one line `uptime=<seconds>`
- executable permission

Write the script:

```
cat > ~/work/sysinfo.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
EOF
```

Make it executable:

```
chmod +x ~/work/sysinfo.sh
```

Run it:

```
~/work/sysinfo.sh
```

Confirm it works and press **[Check]**.

## Arguments and exit codes

Script arguments arrive as `$1 $2 …`, and their count as `$#`. The convention on bad invocation is to **print usage to stderr and exit with a non-zero code** — callers (other scripts, CI) must be able to detect the failure.

Task: write `~/work/logcut.sh <logfile> <status>`.

- print the number of lines with the given status code in the `/opt/lab/data/app.log` format (`… status=200 msg=…`)
- if there aren't exactly 2 arguments: print usage + exit code 2

Write the script:

```
cat > ~/work/logcut.sh <<'EOF'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
grep -c "status=$2 " "$1" || true
EOF
```

Make it executable:

```
chmod +x ~/work/logcut.sh
```

> `grep -c` exits with **code 1** when there are zero matches. Under `set -e` that kills the script, so `|| true` states explicitly that "zero matches is fine" — keep fail-fast on, but don't treat non-failures as failures.

Test it and press **[Check]**.

Normal call — count the 500 lines:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

Call without arguments — expect exit code 2:

```
~/work/logcut.sh; echo "exit=$?"
```

## Guaranteed cleanup with trap

A script that creates temp files leaves garbage behind if it dies midway. `trap '…' EXIT` is a cleanup hook that always runs when the script ends — **whether it exits normally or on error**.

Task: write `~/work/withtmp.sh`.

- create a temp directory with `mktemp -d`, create any file inside it
- delete the temp directory on exit via `trap`
- print the temp directory path as the **last line of output** (verification checks that this path is gone)

Write the script:

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

Make it executable:

```
chmod +x ~/work/withtmp.sh
```

Run it and confirm the deletion:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # "No such file" means it worked
```

Once confirmed, press **[Check]**.

## Fixing a broken script

The finale is what you'll do most often in real life — **fixing someone else's script**. `/opt/lab/bin/backup.sh` backs up a directory to /tmp, but it dies when the path **contains a space**.

View the script:

```
cat /opt/lab/bin/backup.sh
```

Prepare a spaced-path test directory:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

Run it with the spaced path:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # fails!
```

The cause is **unquoted variable expansion**. When `$src` is `/tmp/my app`, `cp -r $src/*` splits into two arguments: `/tmp/my` and `app/*`. This is the most classic of classic shell script bugs.

Task: copy it to `~/work/backup-fixed.sh` and fix it.

- quote every variable expansion with `"…"` (`"$dest"`, `"$src"/*` — the glob `*` stays outside the quotes!)
- add `set -euo pipefail`
- run it with the spaced path and confirm success

Make a copy:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

Fix it in the editor:

```
vim ~/work/backup-fixed.sh
```

Run with the spaced path to confirm:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

On success, press **[Check]** — module complete.
