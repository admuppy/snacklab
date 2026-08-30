#!/bin/bash
r=$(systemctl show -p Restart --value hello-web.service 2>/dev/null)
case "$r" in on-failure|always) ;; *) labmsg step3m1 "$r"; exit 1;; esac
pid=$(systemctl show -p MainPID --value hello-web.service)
[ "$pid" -gt 0 ] 2>/dev/null || { labmsg step3m2; exit 1; }
sudo kill -9 "$pid"
sleep 4
newpid=$(systemctl show -p MainPID --value hello-web.service)
{ [ "$newpid" -gt 0 ] 2>/dev/null && [ "$newpid" != "$pid" ]; } || { labmsg step3m3; exit 1; }
labmsg step3m4 "$pid" "$newpid"
