#!/bin/bash
f=/etc/sudoers.d/deploy
sudo test -f $f || { labmsg step3m1; exit 1; }
sudo visudo -cf $f >/dev/null 2>&1 || { labmsg step3m2; exit 1; }
lst=$(sudo -l -U deploy 2>/dev/null)
echo "$lst" | grep -q 'systemctl status' || { labmsg step3m3; exit 1; }
echo "$lst" | grep -Eq '\(ALL\) *ALL|ALL *: *ALL' && { labmsg step3m4; exit 1; }
labmsg step3m5
