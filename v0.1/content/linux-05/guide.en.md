# Users, Groups, and Least-Privilege sudo

When a new teammate arrives on a server, you create their account, add them to the team group, and open up **only as much** sudo as they need. When they leave, you lock the account. This module covers that whole lifecycle.

First, where account information lives.

| File | Contents |
|---|---|
| `/etc/passwd` | user list (name:x:UID:GID:comment:home:shell) |
| `/etc/shadow` | password hashes + expiry policy (root-readable only) |
| `/etc/group` | groups and their members |
| `/etc/sudoers`, `/etc/sudoers.d/` | sudo permission rules |

Look up the learner account:

```
getent passwd learner
```

- `getent <database> <key>` — looks up one entry via NSS; prints the `learner` line from the `passwd` database.

Peek at the top of shadow:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` is readable only by root, hence `sudo`. The second field is the password hash (`*` or `!` means no password login).

> `getent` queries through NSS (including external sources like LDAP) instead of opening files directly — a more accurate habit than `cat /etc/passwd`.

## Creating users

Create the deployment account `deploy`. Requirements:

- create a home directory (`-m` — without it you get a home-less account)
- login shell `/bin/bash` (`-s` — many distros default to sh)

Create the deploy user:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — creates a user: `-m` creates the home directory (copying `/etc/skel`), `-s /bin/bash` sets the login shell, the last argument is the user name.
- The password is set separately with `passwd deploy` (not needed in this lab).

Check the passwd entry:

```
getent passwd deploy
```

- Of the colon-separated fields, the last two are the home directory and shell — check for `/home/deploy` and `/bin/bash`.

Check the home directory:

```
ls -ld /home/deploy
```

- `ls -ld` — shows the directory **itself** (`-d`), not its contents: permissions and owner. The owner should be `deploy`.

`useradd` is a low-level tool and **asks you nothing**. If you omit an option it just creates the account as-is, so verifying afterwards is mandatory. Once verified, press **[Check]**.

## Setting up groups

Create the operations group `ops` and add deploy to it. Here lies a classic trap —

| Command | Result |
|---|---|
| `usermod -aG ops deploy` | **adds** ops as a supplementary group ✔ |
| `usermod -G ops deploy` | **replaces** all supplementary groups with just ops (everything else drops off!) |
| `usermod -g ops deploy` | **replaces the primary group** (changes the default group of new files) |

`-G` without `-a` (append) is a shortcut to an incident. Add it as a supplementary group.

Create the ops group:

```
sudo groupadd ops
```

- `groupadd <group>` — creates a new group; one line is added to `/etc/group`.

Add as a supplementary group:

```
sudo usermod -aG ops deploy
```

- `usermod` — changes an existing user. `-G ops` sets supplementary groups, `-a` **appends** to the existing ones.
- Sessions already logged in only see the new group after logging in again.

Verify the groups:

```
id deploy
```

- `id <user>` — UID, primary group (`gid=`) and all groups (`groups=`) on one line.

In the `id` output, learn to distinguish `gid=` (primary) from `groups=` (all). Once verified, press **[Check]**.

## Least-privilege sudoers

We want to allow deploy to query service status but **nothing more**. The convention is to not edit `/etc/sudoers` directly but to create drop-ins under `/etc/sudoers.d/`.

Syntax: `who where=(as-whom) [NOPASSWD:] commands`

Write the drop-in rule:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo 'rule' | sudo tee <file>` — with `sudo echo … > file` your own shell does the redirect and hits a permission error, so `tee`, running as root, writes the file.
- The rule: `deploy` on any host (`ALL`), as anyone (`(ALL)`), without a password (`NOPASSWD:`) may run only `systemctl status *`.

Set mode 440:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — read-only for owner (root) and group. sudo refuses sudoers files writable by others.

**Syntax validation is mandatory.** A broken sudoers breaks sudo itself, making recovery painful. `visudo -cf` is the safety net.

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — syntax check only, `-f <file>` — the file to check; it should print `parsed OK`.
- The normal way to edit sudoers is `sudo visudo`, which checks before saving.

Check what deploy can actually do.

List deploy's sudo rights:

```
sudo -l -U deploy
```

- `sudo -l` — list allowed sudo commands; `-U deploy` — for another user (needs root).

Allowed command — should succeed:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # allowed
```

- `sudo -u deploy <cmd>` — runs the command as deploy; inside, `sudo` is called again to test deploy's sudo rights.
- `sudo -n` — never prompt for a password (non-interactive); fails at once if one would be needed.
- `--no-pager` — print directly instead of piping into less.

Denied command — should be refused:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # denied
```

- `restart` is not in the rule, so it is refused. `2>&1` sends the error into the pipe too and `tail -1` shows the last line.

If allow/deny behaves as intended, press **[Check]**.

## Account locking and password policy

`olduser` belongs to someone who left. Deleting (`userdel`) raises file-ownership cleanup issues, so the usual first step is **locking**.

Lock the account:

```
sudo usermod -L olduser
```

- `usermod -L` — locks the account by prefixing the shadow hash with `!`, blocking password logins. Unlock with `-U`.

Check the lock status:

```
sudo passwd -S olduser
```

- `passwd -S <user>` — password status summary; second field `L` locked, `P` usable, `NP` no password.

If the second field of `passwd -S` is `L` (locked), it worked. Locking merely prepends `!` to the hash in shadow, so it can always be reversed with `-U`.

Next, apply a **maximum password age of 90 days** to deploy.

Apply the 90-day maximum:

```
sudo chage -M 90 deploy
```

- `chage` — changes password aging policy; `-M 90` — maximum age of 90 days.

Verify the policy:

```
sudo chage -l deploy
```

- `chage -l` — lists the current policy: last change, expiry, min/max days, …

Once both are confirmed, press **[Check]** — module complete.
