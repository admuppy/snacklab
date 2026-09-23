#!/bin/bash
# openstack-02 bootstrap — wait for the all-in-one control plane, then prepare the
# pieces this module does not teach: a working tenant network and a scratch dir.
# (idempotent; same readiness rule as openstack-01, including placement inventory —
# without it an instance created right after boot lands in ERROR)
set -e
for i in $(seq 1 85); do
  if openstack token issue >/dev/null 2>&1 \
     && openstack compute service list --service nova-compute -f value -c State 2>/dev/null | grep -q up \
     && openstack network agent list -f value -c Alive 2>/dev/null | grep -q True \
     && rp=$(openstack resource provider list -f value -c uuid 2>/dev/null | head -1) \
     && [ -n "$rp" ] \
     && openstack resource provider inventory list "$rp" -f value -c resource_class 2>/dev/null | grep -q VCPU; then
    mkdir -p ~/images
    openstack network show net1 >/dev/null 2>&1 || openstack network create net1 >/dev/null
    openstack subnet show subnet1 >/dev/null 2>&1 \
      || openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1 >/dev/null
    echo "PASS"
    exit 0
  fi
  sleep 2
done
echo "FAIL: OpenStack control plane did not become ready" >&2
exit 1
