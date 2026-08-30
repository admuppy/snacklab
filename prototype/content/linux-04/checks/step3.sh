#!/bin/bash
f=~/work/withtmp.sh
[ -x $f ] || { labmsg step3m1; exit 1; }
grep -q 'trap' $f || { labmsg step3m2; exit 1; }
out=$($f 2>/dev/null | tail -1)
case "$out" in /tmp/*) ;; *) labmsg step3m3 "$out"; exit 1;; esac
[ ! -e "$out" ] || { labmsg step3m4 "$out"; exit 1; }
labmsg step3m5
