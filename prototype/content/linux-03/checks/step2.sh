#!/bin/bash
[ -f ~/work/top-ip.txt ] || { labmsg step2m1; exit 1; }
want=$(awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
got=$(tr -d '[:space:]' < ~/work/top-ip.txt)
[ "$got" = "$want" ] || { labmsg step2m2 "$got" "$want"; exit 1; }
labmsg step2m3 "$want"
