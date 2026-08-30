#!/bin/bash
f=~/work/sysinfo.sh
[ -f $f ] || { labmsg step1m1; exit 1; }
[ -x $f ] || { labmsg step1m2; exit 1; }
head -1 $f | grep -q '^#!.*bash' || { labmsg step1m3; exit 1; }
grep -q 'set -euo pipefail' $f || { labmsg step1m4; exit 1; }
out=$($f 2>/dev/null) || { labmsg step1m5; exit 1; }
echo "$out" | grep -q '^host=' || { labmsg step1m6; exit 1; }
echo "$out" | grep -q '^uptime=' || { labmsg step1m7; exit 1; }
labmsg step1m8
