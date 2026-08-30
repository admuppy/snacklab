#!/bin/bash
exec_path=$(systemctl cat lab-report.service 2>/dev/null | grep '^ExecStart=' | tail -1 | sed 's/^ExecStart=//;s/ .*//')
[ -x "$exec_path" ] || { labmsg step2m1 "$exec_path"; exit 1; }
systemctl is-active lab-report.service >/dev/null 2>&1 || { labmsg step2m2; exit 1; }
labmsg step2m3
