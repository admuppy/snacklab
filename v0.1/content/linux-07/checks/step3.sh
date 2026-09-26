#!/bin/bash
systemctl is-active lab-api.service >/dev/null 2>&1 || { labmsg step3m1; exit 1; }
sudo ss -ltn 2>/dev/null | grep -Eq '(0\.0\.0\.0|\*):9090 ' || { labmsg step3m2; exit 1; }
myip=$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
curl -sf -o /dev/null --max-time 5 "http://$myip:9090/status.json" || { labmsg step3m3 "$myip"; exit 1; }
labmsg step3m4
