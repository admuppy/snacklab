#!/bin/bash
systemctl is-active lab-tick.timer >/dev/null 2>&1 || { labmsg step4m1; exit 1; }
systemctl is-enabled lab-tick.timer >/dev/null 2>&1 || { labmsg step4m2; exit 1; }
t=$(systemctl show -p Type --value lab-tick.service 2>/dev/null)
[ "$t" = "oneshot" ] || { labmsg step4m3 "$t"; exit 1; }
systemctl list-timers 2>/dev/null | grep -q lab-tick || { labmsg step4m4; exit 1; }
labmsg step4m5
