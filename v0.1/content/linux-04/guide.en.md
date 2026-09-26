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

- `cat > file <<'EOF'` … `EOF` — a here-doc: the lines between the two `EOF`s are fed to `cat` and saved to the file with `>`. Quoting `'EOF'` keeps `$(...)` from running now, so it is saved literally.
- `#!/bin/bash` — the shebang; tells the kernel which interpreter runs the file.
- `$(uname -n)` — host name; `awk '{print $1}' /proc/uptime` — seconds since boot (first field).

Make it executable:

```
chmod +x ~/work/sysinfo.sh
```

- `chmod +x` — adds execute (x) permission; without it `./script` fails with `Permission denied`.

Run it:

```
~/work/sysinfo.sh
```

- Running it by path lets the shebang's `/bin/bash` execute it (`bash file` works even without the execute bit).

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

- `usage() { …; }` — a function. `>&2` sends the message to stderr, `exit 2` ends with exit code 2.
- `[ $# -eq 2 ] || usage` — if the argument count (`$#`) isn't 2, call usage (`||`). `[ ]` is the condition command (`test`).
- `grep -c "status=$2 " "$1"` — count lines with the status code from argument 2. Variables are double-quoted so paths with spaces stay safe.

Make it executable:

```
chmod +x ~/work/logcut.sh
```

- Every new script needs the execute bit.

> `grep -c` exits with **code 1** when there are zero matches. Under `set -e` that kills the script, so `|| true` states explicitly that "zero matches is fine" — keep fail-fast on, but don't treat non-failures as failures.

Test it and press **[Check]**.

Normal call — count the 500 lines:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

- The first argument becomes `$1` (log file), the second `$2` (status code).

Call without arguments — expect exit code 2:

```
~/work/logcut.sh; echo "exit=$?"
```

- `$?` — exit code of the previous command; `;` runs this right after to confirm usage exited with 2.

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

- `mktemp -d` — creates a uniquely named temporary directory and prints its path.
- `trap 'cmd' EXIT` — runs the command right before the script exits, for whatever reason — here, deleting the temp dir.
- `rm -rf "$tmp"` — removes the directory with its contents (`-r`) without prompting (`-f`). The trap body is single-quoted, so `$tmp` expands when it runs.

Make it executable:

```
chmod +x ~/work/withtmp.sh
```

- Add the execute bit.

Run it and confirm the deletion:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # "No such file" means it worked
```

- `d=$(script)` — stores the script's output (the temp path) in `d`.
- `ls -d "$d"` — looks up the directory itself; `2>&1` shows the error message too. It should already be gone, so `No such file` is expected.

Once confirmed, press **[Check]**.

## Fixing a broken script

The finale is what you'll do most often in real life — **fixing someone else's script**. `/opt/lab/bin/backup.sh` backs up a directory to /tmp, but it dies when the path **contains a space**.

View the script:

```
cat /opt/lab/bin/backup.sh
```

- Read before you fix: look for `$src` and `$dest` used without quotes.

Prepare a spaced-path test directory:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

- The path contains a space, so it is double-quoted to stay one argument; `;` then creates a test file in it.

Run it with the spaced path:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # fails!
```

- You pass one quoted argument, but the moment the script uses `$src` unquoted it is split into two words again (word splitting).

The cause is **unquoted variable expansion**. When `$src` is `/tmp/my app`, `cp -r $src/*` splits into two arguments: `/tmp/my` and `app/*`. This is the most classic of classic shell script bugs.

Task: copy it to `~/work/backup-fixed.sh` and fix it.

- quote every variable expansion with `"…"` (`"$dest"`, `"$src"/*` — the glob `*` stays outside the quotes!)
- add `set -euo pipefail`
- run it with the spaced path and confirm success

Make a copy:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

- `cp <source> <dest>` — leaves the original alone and puts a copy in your work directory.

Fix it in the editor:

```
vim ~/work/backup-fixed.sh
```

- vim: `i` for insert mode, then `Esc` → `:wq` to save and quit. Prefer `nano` if you like (`Ctrl+O` save, `Ctrl+X` exit).

Run with the spaced path to confirm:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

- `A && B` — runs B only if A succeeded (exit code 0); seeing `OK` means the fix works.

On success, press **[Check]** — module complete.
