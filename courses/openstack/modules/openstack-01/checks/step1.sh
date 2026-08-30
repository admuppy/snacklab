#!/bin/bash
# step1: network 'net1' exists and has subnet 'subnet1' with 192.168.100.0/24
net=$(openstack network show net1 -f value -c id 2>/dev/null)
[ -n "$net" ] || { labmsg step1m1; exit 1; }
range=$(openstack subnet show subnet1 -f value -c cidr 2>/dev/null)
[ -n "$range" ] || { labmsg step1m2; exit 1; }
[ "$range" = "192.168.100.0/24" ] || { labmsg step1m3 "$range"; exit 1; }
subnet_net=$(openstack subnet show subnet1 -f value -c network_id 2>/dev/null)
[ "$subnet_net" = "$net" ] || { labmsg step1m4; exit 1; }
labmsg step1m5
