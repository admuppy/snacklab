#!/bin/bash
systemctl is-active lab-app.service >/dev/null 2>&1 || { labmsg step3m1; exit 1; }
body=$(curl -sf --max-time 5 http://127.0.0.1:8080/index.html) || { labmsg step3m2; exit 1; }
echo "$body" | grep -q 'LAB APP OK' || { labmsg step3m3; exit 1; }
labmsg step3m4
