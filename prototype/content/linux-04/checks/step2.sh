#!/bin/bash
f=~/work/logcut.sh
[ -x $f ] || { labmsg step2m1; exit 1; }
want=$(grep -c 'status=500 ' /opt/lab/data/app.log)
got=$($f /opt/lab/data/app.log 500 2>/dev/null | tail -1 | tr -d '[:space:]')
[ "$got" = "$want" ] || { labmsg step2m2 "$got" "$want"; exit 1; }
want404=$(grep -c 'status=404 ' /opt/lab/data/app.log)
got404=$($f /opt/lab/data/app.log 404 2>/dev/null | tail -1 | tr -d '[:space:]')
[ "$got404" = "$want404" ] || { labmsg step2m3 "$got404" "$want404"; exit 1; }
$f >/dev/null 2>&1 && { labmsg step2m4; exit 1; }
labmsg step2m5
