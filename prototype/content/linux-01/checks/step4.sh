#!/bin/bash
[ -f ~/work/suid.txt ] || { labmsg step4m1; exit 1; }
grep -q '/usr/bin/passwd' ~/work/suid.txt || { labmsg step4m2; exit 1; }
perm=$(stat -c %a /opt/lab/perm/danger.conf)
[ "$perm" = "640" ] || { labmsg step4m3 "$perm"; exit 1; }
labmsg step4m4
