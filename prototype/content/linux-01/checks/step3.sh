#!/bin/bash
acl=$(getfacl -p ~/work/secret.txt 2>/dev/null)
echo "$acl" | grep -q '^user:audit:r--' || { labmsg step3m1; exit 1; }
sudo -u audit cat ~/work/secret.txt >/dev/null 2>&1 || { labmsg step3m2; exit 1; }
sudo -u audit test -w ~/work/secret.txt && { labmsg step3m3; exit 1; }
labmsg step3m4
