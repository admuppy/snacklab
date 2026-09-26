#!/bin/bash
[ -d /srv/share ] || { labmsg step2m1; exit 1; }
perm=$(stat -c %a /srv/share)
[ "$perm" = "3775" ] || { labmsg step2m2 "$perm"; exit 1; }
grp=$(stat -c %G /srv/share)
[ "$grp" = "share" ] || { labmsg step2m3 "$grp"; exit 1; }
labmsg step2m4
