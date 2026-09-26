#!/bin/bash
getent hosts api.lab.local >/dev/null || { labmsg step4m1; exit 1; }
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://api.lab.local:9090/status.json)
[ "$code" = "200" ] || { labmsg step4m2 "$code"; exit 1; }
labmsg step4m3
