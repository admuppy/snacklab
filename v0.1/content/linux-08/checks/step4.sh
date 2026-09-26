#!/bin/bash
en=$(systemctl is-enabled lab-app.service 2>/dev/null)
[ "$en" = "enabled" ] || { labmsg step4m1 "$en"; exit 1; }
[ -f ~/work/final.txt ] || { labmsg step4m2; exit 1; }
grep -q 'LAB APP OK' ~/work/final.txt || { labmsg step4m3; exit 1; }
labmsg step4m4
