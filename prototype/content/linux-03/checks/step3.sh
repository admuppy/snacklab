#!/bin/bash
f=~/work/access-redacted.log
[ -f $f ] || { labmsg step3m1; exit 1; }
orig=$(wc -l < /var/log/lab/access.log); red=$(wc -l < $f)
[ "$orig" = "$red" ] || { labmsg step3m2 "$orig" "$red"; exit 1; }
grep -Eq '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ' $f && { labmsg step3m3; exit 1; }
grep -q '^REDACTED ' $f || { labmsg step3m4; exit 1; }
labmsg step3m5
