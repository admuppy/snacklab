# Network Diagnostics

"I can't reach the service" almost always comes down to one of four causes — **wrong IP, port not open, wrong binding, or name not resolving.** In this module you'll learn the tools that diagnose those four in order: ip, ss, curl, getent.

The lab environment runs an API service called `lab-api` — and there's an open report that "it can't be reached from outside". By the end you'll have found and fixed the cause.

## Inspecting interfaces and IPs

Network diagnosis starts with **who am I** (my IP). The modern standard tool is `ip` (ifconfig has retired).

List the interfaces:

```
ip link
```

Show IPv4 addresses:

```
ip -4 addr show
```

Show the routing table:

```
ip route
```

A container usually shows two interfaces: `lo` (loopback) and `eth0`. A script-friendly one-line extraction:

Print eth0 on one line:

```
ip -4 -o addr show eth0
```

Extract just the CIDR field:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

Task: save eth0's IPv4 address — **address only, no CIDR** — to `~/work/myip.txt`. Strip suffixes like `/24` with `cut -d/ -f1`.

Strip the suffix and save:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

Verify the saved content:

```
cat ~/work/myip.txt
```

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

Task: find the **port number** `lab-api.service` is listening on and save it to `~/work/api-port.txt`. Starting from the unit's main PID is a good route.

Show lab-api's main PID:

```
systemctl show -p MainPID --value lab-api
```

Find that PID's listening socket:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

Read the port from `127.0.0.1:port` in the Local Address column. Save it and press **[Check]**.

## Diagnosing and fixing a binding issue

You may have already noticed it in the ss output — lab-api's Local Address is `127.0.0.1:9090`. It is **bound to loopback only**, so it works inside this container but gives connection refused from outside (other pods, the node). Reproduce it.

Connect via loopback:

```
curl -s http://127.0.0.1:9090/status.json        # succeeds
```

Connect via the container IP:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # fails!
```

Same process, different result depending on **which address the request comes in on**. The binding must change to `0.0.0.0` (all interfaces).

Task: change `--bind 127.0.0.1` to `--bind 0.0.0.0` in the unit file and restart.

Edit the unit file:

```
sudo vim /etc/systemd/system/lab-api.service
```

Reload systemd:

```
sudo systemctl daemon-reload
```

Restart the service:

```
sudo systemctl restart lab-api
```

Check the binding address:

```
sudo ss -ltn | grep 9090
```

Connect via the container IP again:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # now succeeds
```

When it shows `0.0.0.0:9090` and responds on the container IP, press **[Check]**.

## Name resolution — hosts and DNS

The last piece is **name → IP**. Resolution order is usually `/etc/hosts` → DNS (the nameservers in `/etc/resolv.conf`), and that order is governed by the `hosts:` line in `/etc/nsswitch.conf`.

Check the DNS server settings:

```
cat /etc/resolv.conf
```

Check the resolution order rule:

```
grep hosts /etc/nsswitch.conf
```

The lookup tools serve different purposes: `nslookup`/`dig` ask a **DNS server directly**, while `getent hosts` follows the **system's actual resolution path** (including the hosts file). What applications see is the getent result.

Task: make lab-api reachable by the name `api.lab.local`. You can't change the DNS server, so register it in `/etc/hosts`.

Register the name in hosts:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

Resolve via the system path:

```
getent hosts api.lab.local
```

Connect by name:

```
curl -s http://api.lab.local:9090/status.json
```

When you get a response, press **[Check]** — module complete.
