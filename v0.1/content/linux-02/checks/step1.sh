#!/bin/bash
[ -f ~/work/worker.pid ] || { labmsg step1m1; exit 1; }
want=$(pgrep -f '/opt/lab/bin/lab-worker' | head -1)
got=$(tr -d '[:space:]' < ~/work/worker.pid)
[ -n "$want" ] || { labmsg step1m2; exit 1; }
[ "$got" = "$want" ] || { labmsg step1m3 "$got" "$want"; exit 1; }
[ -f ~/work/worker.cmdline ] || { labmsg step1m4; exit 1; }
grep -q 'lab-worker' ~/work/worker.cmdline || { labmsg step1m5; exit 1; }
labmsg step1m6
