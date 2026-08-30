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

Peek at the top of shadow:

```
sudo head -3 /etc/shadow
```

> `getent` queries through NSS (including external sources like LDAP) instead of opening files directly — a more accurate habit than `cat /etc/passwd`.

## Creating users

Create the deployment account `deploy`. Requirements:

- create a home directory (`-m` — without it you get a home-less account)
- login shell `/bin/bash` (`-s` — many distros default to sh)

Create the deploy user:

```
sudo useradd -m -s /bin/bash deploy
```

Check the passwd entry:

```
getent passwd deploy
```

Check the home directory:

```
ls -ld /home/deploy
```

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

Add as a supplementary group:

```
sudo usermod -aG ops deploy
```

Verify the groups:

```
id deploy
```

In the `id` output, learn to distinguish `gid=` (primary) from `groups=` (all). Once verified, press **[Check]**.

## Least-privilege sudoers

We want to allow deploy to query service status but **nothing more**. The convention is to not edit `/etc/sudoers` directly but to create drop-ins under `/etc/sudoers.d/`.

Syntax: `who where=(as-whom) [NOPASSWD:] commands`

Write the drop-in rule:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

Set mode 440:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

**Syntax validation is mandatory.** A broken sudoers breaks sudo itself, making recovery painful. `visudo -cf` is the safety net.

```
sudo visudo -cf /etc/sudoers.d/deploy
```

Check what deploy can actually do.

List deploy's sudo rights:

```
sudo -l -U deploy
```

Allowed command — should succeed:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # allowed
```

Denied command — should be refused:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # denied
```

If allow/deny behaves as intended, press **[Check]**.

## Account locking and password policy

`olduser` belongs to someone who left. Deleting (`userdel`) raises file-ownership cleanup issues, so the usual first step is **locking**.

Lock the account:

```
sudo usermod -L olduser
```

Check the lock status:

```
sudo passwd -S olduser
```

If the second field of `passwd -S` is `L` (locked), it worked. Locking merely prepends `!` to the hash in shadow, so it can always be reversed with `-U`.

Next, apply a **maximum password age of 90 days** to deploy.

Apply the 90-day maximum:

```
sudo chage -M 90 deploy
```

Verify the policy:

```
sudo chage -l deploy
```

Once both are confirmed, press **[Check]** — module complete.
