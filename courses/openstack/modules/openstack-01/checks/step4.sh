#!/bin/bash
# step4: server 'vm1' is SHUTOFF
status=$(openstack server show vm1 -f value -c status 2>/dev/null)
[ -n "$status" ] || { labmsg step4m1; exit 1; }
[ "$status" = "SHUTOFF" ] || { labmsg step4m2 "$status"; exit 1; }
labmsg step4m3
