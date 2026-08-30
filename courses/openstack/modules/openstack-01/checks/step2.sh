#!/bin/bash
# step2: server 'vm1' booted successfully (ACTIVE; SHUTOFF also accepted since
# it is only reachable from ACTIVE — keeps this check green after step 3),
# on net1, flavor m1.tiny
status=$(openstack server show vm1 -f value -c status 2>/dev/null)
[ -n "$status" ] || { labmsg step2m1; exit 1; }
case "$status" in ACTIVE|SHUTOFF) ;; *) labmsg step2m2 "$status"; exit 1 ;; esac
flavor=$(openstack server show vm1 -f value -c flavor 2>/dev/null)
echo "$flavor" | grep -q 'm1.tiny' || { labmsg step2m3 "$flavor"; exit 1; }
addresses=$(openstack server show vm1 -f value -c addresses 2>/dev/null)
echo "$addresses" | grep -q 'net1' || { labmsg step2m4; exit 1; }
labmsg step2m5
