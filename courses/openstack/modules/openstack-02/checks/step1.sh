#!/bin/bash
# step1: an empty qcow2 disk of 1 GiB virtual size at ~/images/blank.qcow2
img=~/images/blank.qcow2
[ -f "$img" ] || { labmsg step1m1; exit 1; }
fmt=$(qemu-img info --output=json "$img" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["format"])' 2>/dev/null)
[ "$fmt" = "qcow2" ] || { labmsg step1m2 "${fmt:-unknown}"; exit 1; }
vsize=$(qemu-img info --output=json "$img" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["virtual-size"])' 2>/dev/null)
[ "$vsize" = "1073741824" ] || { labmsg step1m3 "${vsize:-0}"; exit 1; }
labmsg step1m4
