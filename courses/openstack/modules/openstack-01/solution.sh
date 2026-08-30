#!/bin/bash
# openstack-01 solution — idempotent
set -e

openstack network show net1 >/dev/null 2>&1 || openstack network create net1 >/dev/null
openstack subnet show subnet1 >/dev/null 2>&1 \
  || openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1 >/dev/null

openstack server show vm1 >/dev/null 2>&1 \
  || openstack server create --flavor m1.tiny --image cirros --network net1 vm1 >/dev/null

# Wait for ACTIVE (fake driver: usually a few seconds)
for i in $(seq 1 45); do
  status=$(openstack server show vm1 -f value -c status 2>/dev/null)
  [ "$status" = "ACTIVE" ] || [ "$status" = "SHUTOFF" ] && break
  [ "$status" = "ERROR" ] && { echo "FAIL: vm1 went to ERROR"; openstack server show vm1; exit 1; }
  sleep 2
done

status=$(openstack server show vm1 -f value -c status)
[ "$status" = "SHUTOFF" ] || openstack server stop vm1
for i in $(seq 1 30); do
  [ "$(openstack server show vm1 -f value -c status)" = "SHUTOFF" ] && break
  sleep 2
done

echo "PASS"
