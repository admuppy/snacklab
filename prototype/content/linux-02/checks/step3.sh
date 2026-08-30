#!/bin/bash
pgrep -f '/opt/lab/bin/lab-batch' >/dev/null || { labmsg step3m1; exit 1; }
[ -f ~/work/batch.log ] || { labmsg step3m2; exit 1; }
ppid=$(ps -o ppid= -p "$(pgrep -f '/opt/lab/bin/lab-batch' | head -1)" | tr -d ' ')
[ "$ppid" = "1" ] || { labmsg step3m3 "$ppid"; exit 1; }
labmsg step3m4
