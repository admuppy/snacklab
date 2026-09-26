# Network Diagnostics

"I can't reach the service" almost always comes down to one of four causes — **wrong IP, port not open, wrong binding, or name not resolving.** In this module you'll learn the tools that diagnose those four in order: ip, ss, curl, getent.

The lab environment runs an API service called `lab-api` — and there's an open report that "it can't be reached from outside". By the end you'll have found and fixed the cause.

## Inspecting interfaces and IPs

Network diagnosis starts with **who am I** (my IP). The modern standard tool is `ip` (ifconfig has retired).

List the interfaces:

```
ip link
```

- `ip link` — network interfaces (L2) with state (`UP`/`DOWN`), MAC address and MTU.

Show IPv4 addresses:

```
ip -4 addr show
```

- `ip addr show` — IP addresses per interface; `-4` for IPv4 only. Shown as address/prefix length (CIDR), e.g. `inet 10.x.x.x/24`.

Show the routing table:

```
ip route
```

- `ip route` — the routing table; the `default via <gateway>` line is the default route out.

A container usually shows two interfaces: `lo` (loopback) and `eth0`. A script-friendly one-line extraction:

Print eth0 on one line:

```
ip -4 -o addr show eth0
```

- `-o` — one interface per **line** (oneline), easy to post-process with `grep`/`awk`.
- `show eth0` — just that interface.

Extract just the CIDR field:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

- `awk '{print $4}'` — keeps only the 4th whitespace-separated field (`10.x.x.x/24`).

Task: save eth0's IPv4 address — **address only, no CIDR** — to `~/work/myip.txt`. Strip suffixes like `/24` with `cut -d/ -f1`.

Strip the suffix and save:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

- `cut -d/ -f1` — split on `/` (`-d`) and keep field 1 (`-f1`) → the address.
- `> ~/work/myip.txt` — saves the result to a file.

Verify the saved content:

```
cat ~/work/myip.txt
```

- Prints the saved address. Later commands reuse it as `$(cat ~/work/myip.txt)`.

Once saved, press **[Check]**.

## Tracking listening sockets

Next question: **what is listening on which port.** The essential `ss` options:

| Option | Meaning |
|---|---|
| `-l` | listening sockets only |
| `-t` / `-u` | TCP / UDP |
| `-n` | numeric ports (skip service-name lookup) |
| `-p` | show processes (sudo needed for other users') |

```
sudo ss -ltnp
```

- The option combo from the table. `Local Address:Port` tells where it listens and `users:((…))` which process.

Task: find the **port number** `lab-api.service` is listening on and save it to `~/work/api-port.txt`. Starting from the unit's main PID is a good route.

Show lab-api's main PID:

```
systemctl show -p MainPID --value lab-api
```

- `systemctl show -p MainPID --value <unit>` — prints just the PID of the unit's main process.

Find that PID's listening socket:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

- `$( … )` expands inside double quotes too → it becomes `grep "pid=1234"`, keeping only that PID's socket lines.

Read the port from `127.0.0.1:port` in the Local Address column. Save it and press **[Check]**.

## Diagnosing and fixing a binding issue

You may have already noticed it in the ss output — lab-api's Local Address is `127.0.0.1:9090`. It is **bound to loopback only**, so it works inside this container but gives connection refused from outside (other pods, the node). Reproduce it.

Connect via loopback:

```
curl -s http://127.0.0.1:9090/status.json        # succeeds
```

- `curl -s <URL>` — quiet request, prints only the body. Via loopback (`127.0.0.1`) it connects.

Connect via the container IP:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # fails!
```

- `--max-time 3` — caps the whole request at 3 s instead of waiting.
- `$(cat ~/work/myip.txt)` — inserts the saved container IP into the URL.

Same process, different result depending on **which address the request comes in on**. The binding must change to `0.0.0.0` (all interfaces).

Task: change `--bind 127.0.0.1` to `--bind 0.0.0.0` in the unit file and restart.

Edit the unit file:

```
sudo vim /etc/systemd/system/lab-api.service
```

- Find `--bind 127.0.0.1` on the `ExecStart=` line and change it. vim: `i` to insert, `Esc` → `:wq` to save and quit.

Reload systemd:

```
sudo systemctl daemon-reload
```

- You edited the unit file, so make systemd re-read it.

Restart the service:

```
sudo systemctl restart lab-api
```

- Restarts the process with the new bind address.

Check the binding address:

```
sudo ss -ltn | grep 9090
```

- No need for process names, so no `-p`. `0.0.0.0:9090` means it accepts on every interface.

Connect via the container IP again:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # now succeeds
```

- Send the same request again; this time it should answer.

When it shows `0.0.0.0:9090` and responds on the container IP, press **[Check]**.

## Name resolution — hosts and DNS

The last piece is **name → IP**. Resolution order is usually `/etc/hosts` → DNS (the nameservers in `/etc/resolv.conf`), and that order is governed by the `hosts:` line in `/etc/nsswitch.conf`.

Check the DNS server settings:

```
cat /etc/resolv.conf
```

- `nameserver` — DNS servers to query; `search` — domains tried in turn after short names.

Check the resolution order rule:

```
grep hosts /etc/nsswitch.conf
```

- `hosts: files dns` — resolve names from `files` (=`/etc/hosts`) first, then `dns`.

The lookup tools serve different purposes: `nslookup`/`dig` ask a **DNS server directly**, while `getent hosts` follows the **system's actual resolution path** (including the hosts file). What applications see is the getent result.

Task: make lab-api reachable by the name `api.lab.local`. You can't change the DNS server, so register it in `/etc/hosts`.

Register the name in hosts:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

- `tee -a` — **appends** instead of overwriting. Forget `-a` and the whole hosts file becomes one line!
- Format: `<IP> <name> [aliases…]`.

Resolve via the system path:

```
getent hosts api.lab.local
```

- `getent hosts <name>` — resolves in nsswitch order (hosts file included) — the same answer applications get.

Connect by name:

```
curl -s http://api.lab.local:9090/status.json
```

- Requests by name instead of IP; curl uses the system resolver, so the `/etc/hosts` entry applies.

When you get a response, press **[Check]** — module complete.
