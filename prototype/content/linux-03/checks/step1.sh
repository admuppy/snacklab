#!/bin/bash
[ -f ~/work/err5xx.count ] || { labmsg step1m1; exit 1; }
want=$(grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log)
got=$(tr -d '[:space:]' < ~/work/err5xx.count)
[ "$got" = "$want" ] || { labmsg step1m2 "$got" "$want"; exit 1; }
labmsg step1m3 "$want"
