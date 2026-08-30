# File Permissions and Special Bits

The first step in Linux security is **file permissions**. This module covers basic permissions (rwx) and umask, special bits like setgid and sticky, fine-grained access control with ACLs, and finally a hands-on audit: finding and fixing dangerous permissions on a real system.

Let's check the current user. `learner` is a regular user with sudo access.

```
id
```

You should be able to move between the two permission notations.

| Notation | Example | Meaning |
|---|---|---|
| Symbolic | `rwxr-x---` | owner rwx / group r-x / others none |
| Octal | `750` | sum of r=4, w=2, x=1 |

## Basic permissions and umask

When a file is created, its default permissions are decided by the **umask**.

Check the current umask:

```
umask
```

Create a file and see what permissions it actually gets:

```
touch /tmp/t1 && stat -c %a /tmp/t1
```

Now create a workspace only you can access. Requirements:

- `~/work` directory — mode **700** (owner-only rwx)
- `~/work/secret.txt` file — any content, mode **600** (owner-only rw)

Create the work directory with mode 700:

```
mkdir -p ~/work && chmod 700 ~/work
```

Create the secret file:

```
echo "top secret" > ~/work/secret.txt
```

Set the file mode to 600:

```
chmod 600 ~/work/secret.txt
```

Confirm with `stat` and press **[Check]**.

```
stat -c '%a %n' ~/work ~/work/secret.txt
```

> The `x` bit on a directory means "traverse (enter) permission". Even with `r` on a directory, you cannot reach the files inside without `x` — we'll meet this again in the ACL step.

## setgid and the sticky bit

Two special bits you'll often use for team-shared directories:

| Bit | Octal | Effect on a directory |
|---|---|---|
| setgid | 2000 | files created inside **inherit the directory's group** |
| sticky | 1000 | only the **owner** can delete a file (like `/tmp`) |

Create the shared directory `/srv/share` for the `share` group. Requirements:

- Create the group: `share`
- `/srv/share` directory, owning group `share`
- Mode **3775** = setgid(2000) + sticky(1000) + 775

Create the group:

```
sudo groupadd -f share
```

Create the shared directory:

```
sudo mkdir -p /srv/share
```

Set the owning group to share:

```
sudo chgrp share /srv/share
```

Set mode 3775 with the special bits:

```
sudo chmod 3775 /srv/share
```

Check the result. In symbolic notation, setgid shows as `s` in the group position and sticky as `t` in the last position (`drwxrwsr-t`).

Check mode and owning group:

```
stat -c '%a %G %n' /srv/share
```

See the symbolic notation:

```
ls -ld /srv/share
```

When it looks right, press **[Check]**.

## Fine-grained access with ACLs

`rwx` only has three slots: owner/group/others. "Allow **exactly one specific user** to read this file" is solved with an **ACL** (Access Control List).

An audit account named `audit` is already set up on the system. Open up `~/work/secret.txt` from step 1 to `audit`, **read-only**.

Grant audit a read ACL:

```
setfacl -m u:audit:r ~/work/secret.txt
```

Check the ACL entries:

```
getfacl ~/work/secret.txt
```

But that alone isn't enough — for `audit` to actually **reach** the file, it must be able to traverse the directories on the path (`~` and `~/work`). A 700 directory blocks audit.

Grant just the traverse (x) permission via ACL:

```
setfacl -m u:audit:x ~ ~/work
```

Verify it from audit's point of view.

Reading — should succeed:

```
sudo -u audit cat ~/work/secret.txt
```

Writing — should fail:

```
sudo -u audit sh -c 'echo x >> ~learner/work/secret.txt'
```

Files with an ACL show a `+` after the permission bits in `ls -l`. Confirm, then press **[Check]**.

## Permission audit and repair

Finally, a real-world task. Executables with the **SUID** bit (4000) run with the owner's privileges (usually root), making them the top priority in any audit.

Find all SUID files across the system and save the list:

```
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt
```

View the list:

```
cat ~/work/suid.txt
```

Think about why `passwd` is SUID — a regular user has to be able to update the root-owned `/etc/shadow`.

Second task: `/opt/lab/perm/danger.conf` is a config file containing a DB password, but it shipped with mode **666** (world-readable and writable!).

Check the current permissions:

```
ls -l /opt/lab/perm/
```

Repair to 640:

```
sudo chmod 640 /opt/lab/perm/danger.conf
```

After the repair, press **[Check]** to complete the module.
