#!/bin/bash
st=$(sudo passwd -S olduser 2>/dev/null | awk '{print $2}')
[ "$st" = "L" ] || { labmsg step4m1 "$st"; exit 1; }
max=$(sudo chage -l deploy 2>/dev/null | awk -F': ' '/Maximum/ {print $2}' | tr -d ' ')
[ "$max" = "90" ] || { labmsg step4m2 "$max"; exit 1; }
labmsg step4m3
