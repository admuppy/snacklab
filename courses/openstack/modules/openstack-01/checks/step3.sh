#!/bin/bash
# step3: server 'vm1' is SHUTOFF
status=$(openstack server show vm1 -f value -c status 2>/dev/null)
[ -n "$status" ] || { labmsg step3m1; exit 1; }
[ "$status" = "SHUTOFF" ] || { labmsg step3m2 "$status"; exit 1; }
labmsg step3m3
