#!/bin/bash
if pgrep -f '/opt/lab/bin/lab-stubborn' >/dev/null; then
  labmsg step2m1
  exit 1
fi
sudo systemctl is-active lab-stubborn >/dev/null 2>&1 && { labmsg step2m2; exit 1; }
labmsg step2m3
