#!/bin/bash
ent=$(getent passwd deploy) || { labmsg step1m1; exit 1; }
echo "$ent" | grep -q ':/bin/bash$' || { labmsg step1m2; exit 1; }
home=$(echo "$ent" | cut -d: -f6)
[ -d "$home" ] || { labmsg step1m3 "$home"; exit 1; }
labmsg step1m4
