#!/bin/bash
[ -f ~/work/myip.txt ] || { labmsg step1m1; exit 1; }
want=$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
[ -n "$want" ] || want=$(hostname -I 2>/dev/null | awk '{print $1}')
got=$(tr -d '[:space:]' < ~/work/myip.txt)
[ "$got" = "$want" ] || { labmsg step1m2 "$got" "$want"; exit 1; }
labmsg step1m3 "$want"
