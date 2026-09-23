#!/bin/bash
# openstack-01 solution — idempotent
set -e

openstack network show net1 >/dev/null 2>&1 || openstack network create net1 >/dev/null
openstack subnet show subnet1 >/dev/null 2>&1 \
  || openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1 >/dev/null

# Boot it. Under heavy node load the first attempt can land in ERROR (the scheduler
# gives up before the just-started compute reports), so retry once from scratch.
for attempt in 1 2; do
  openstack server show vm1 >/dev/null 2>&1 \
    || openstack server create --flavor m1.tiny --image cirros --network net1 vm1 >/dev/null

  # Wait for ACTIVE (fake driver: usually a few seconds)
  status=""
  for i in $(seq 1 45); do
    status=$(openstack server show vm1 -f value -c status 2>/dev/null)
    case "$status" in ACTIVE|SHUTOFF|ERROR) break ;; esac
    sleep 2
  done

  [ "$status" = "ERROR" ] || break
  echo "vm1 landed in ERROR (attempt $attempt):" >&2
  openstack server show vm1 -f value -c fault 2>/dev/null | head -3 >&2
  [ "$attempt" = 2 ] && { echo "FAIL: vm1 stayed in ERROR"; exit 1; }
  openstack server delete --wait vm1 >/dev/null 2>&1 || true
done

# step 3: the all-projects listing the learner is asked to save
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt

status=$(openstack server show vm1 -f value -c status)
[ "$status" = "SHUTOFF" ] || openstack server stop vm1
for i in $(seq 1 30); do
  [ "$(openstack server show vm1 -f value -c status)" = "SHUTOFF" ] && break
  sleep 2
done

echo "PASS"
