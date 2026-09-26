#!/bin/bash
[ -f ~/work/api-bytes.txt ] || { labmsg step4m1; exit 1; }
want=$(awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s+0}' /var/log/lab/access.log)
got=$(tr -d '[:space:]' < ~/work/api-bytes.txt)
[ "$got" = "$want" ] || { labmsg step4m2 "$got" "$want"; exit 1; }
labmsg step4m3 "$want"
