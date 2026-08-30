#!/bin/bash
systemctl is-active lab-squatter.service >/dev/null 2>&1 && { labmsg step2m1; exit 1; }
en=$(systemctl is-enabled lab-squatter.service 2>/dev/null)
[ "$en" = "enabled" ] && { labmsg step2m2; exit 1; }
systemctl is-active lab-app.service >/dev/null 2>&1 || { labmsg step2m3; exit 1; }
labmsg step2m4
