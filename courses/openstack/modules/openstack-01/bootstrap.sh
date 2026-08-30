#!/bin/bash
# openstack-01 bootstrap — wait until the all-in-one control plane is usable
# (idempotent; portal bootstrap timeout is 180s, warm-pool boots absorb the rest).
# Usable means: keystone answers, the fake nova-compute host has been discovered
# (nova.conf discover_hosts_in_cells_interval), and neutron has live agents.
set -e
for i in $(seq 1 85); do
  if openstack token issue >/dev/null 2>&1 \
     && openstack compute service list --service nova-compute -f value -c State 2>/dev/null | grep -q up \
     && openstack network agent list -f value -c Alive 2>/dev/null | grep -q True; then
    echo "PASS"
    exit 0
  fi
  sleep 2
done
echo "FAIL: OpenStack control plane did not become ready" >&2
exit 1
