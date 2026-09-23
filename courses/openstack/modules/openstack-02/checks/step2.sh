#!/bin/bash
# step2: cirros pulled out of glance, converted to raw and back to qcow2 —
# both files exist, carry the right format and describe the same disk.
fmt_of() { qemu-img info --output=json "$1" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["format"])' 2>/dev/null; }
size_of() { qemu-img info --output=json "$1" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["virtual-size"])' 2>/dev/null; }

raw=~/images/cirros-raw.img
qcow=~/images/cirros-lab.qcow2
[ -f "$raw" ] || { labmsg step2m1; exit 1; }
[ "$(fmt_of "$raw")" = "raw" ] || { labmsg step2m2 "$(fmt_of "$raw")"; exit 1; }
[ -f "$qcow" ] || { labmsg step2m3; exit 1; }
[ "$(fmt_of "$qcow")" = "qcow2" ] || { labmsg step2m4 "$(fmt_of "$qcow")"; exit 1; }
[ "$(size_of "$raw")" = "$(size_of "$qcow")" ] || { labmsg step2m5; exit 1; }
labmsg step2m6
