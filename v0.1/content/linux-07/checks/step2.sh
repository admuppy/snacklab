#!/bin/bash
[ -f ~/work/api-port.txt ] || { labmsg step2m1; exit 1; }
got=$(tr -d '[:space:]' < ~/work/api-port.txt)
[ "$got" = "9090" ] || { labmsg step2m2 "$got"; exit 1; }
labmsg step2m3
