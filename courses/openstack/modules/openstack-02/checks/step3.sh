#!/bin/bash
# step3: the converted qcow2 is a usable glance image — right formats, active,
# sizing hints and os_distro property set — and an instance booted from it.
img=$(openstack image show cirros-lab -f json 2>/dev/null)
[ -n "$img" ] || { labmsg step3m1; exit 1; }
val() { printf '%s' "$img" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('$1',''))" 2>/dev/null; }
[ "$(val disk_format)" = "qcow2" ] || { labmsg step3m2 "$(val disk_format)"; exit 1; }
[ "$(val container_format)" = "bare" ] || { labmsg step3m3 "$(val container_format)"; exit 1; }
[ "$(val status)" = "active" ] || { labmsg step3m4 "$(val status)"; exit 1; }
[ "$(val min_disk)" = "1" ] || { labmsg step3m5 "$(val min_disk)"; exit 1; }
[ "$(val min_ram)" = "64" ] || { labmsg step3m6 "$(val min_ram)"; exit 1; }
printf '%s' "$img" | grep -q 'os_distro' || { labmsg step3m7; exit 1; }

status=$(openstack server show vm2 -f value -c status 2>/dev/null)
[ -n "$status" ] || { labmsg step3m8; exit 1; }
case "$status" in ACTIVE|SHUTOFF) ;; *) labmsg step3m9 "$status"; exit 1 ;; esac
image_used=$(openstack server show vm2 -f value -c image 2>/dev/null)
echo "$image_used" | grep -q 'cirros-lab' || { labmsg step3m10 "$image_used"; exit 1; }
labmsg step3m11
