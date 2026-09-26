#!/bin/bash
[ -f ~/work/port-owner.txt ] || { labmsg step4m1; exit 1; }
grep -qi 'python3\|http.server' ~/work/port-owner.txt || { labmsg step4m2; exit 1; }
labmsg step4m3
