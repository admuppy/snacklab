#!/bin/bash
systemctl is-active hello-web.service >/dev/null 2>&1 || { labmsg step1m1; exit 1; }
systemctl is-enabled hello-web.service >/dev/null 2>&1 || { labmsg step1m2; exit 1; }
curl -sf -o /dev/null --max-time 5 http://127.0.0.1:8080/ || { labmsg step1m3; exit 1; }
labmsg step1m4
