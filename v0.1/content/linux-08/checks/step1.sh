#!/bin/bash
exec_path=$(systemctl cat lab-app.service 2>/dev/null | grep '^ExecStart=' | tail -1 | sed 's/^ExecStart=//;s/ .*//')
[ -n "$exec_path" ] || { labmsg step1m1; exit 1; }
[ -x "$exec_path" ] || { labmsg step1m2 "$exec_path"; exit 1; }
labmsg step1m3 "$exec_path"
