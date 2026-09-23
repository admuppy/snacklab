#!/bin/bash
# openstack-02 solution — idempotent
set -e
mkdir -p ~/images

# step 1: an empty 1 GiB qcow2 disk
[ -f ~/images/blank.qcow2 ] || qemu-img create -f qcow2 ~/images/blank.qcow2 1G >/dev/null

# step 2: pull the cirros disk out of glance and convert qcow2 → raw → qcow2
[ -f ~/images/cirros-src.img ] || openstack image save cirros --file ~/images/cirros-src.img
[ -f ~/images/cirros-raw.img ] \
  || qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
[ -f ~/images/cirros-lab.qcow2 ] \
  || qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2

# step 3: upload it to glance and boot from it
openstack image show cirros-lab >/dev/null 2>&1 || openstack image create cirros-lab \
  --disk-format qcow2 --container-format bare \
  --min-disk 1 --min-ram 64 --property os_distro=cirros \
  --file ~/images/cirros-lab.qcow2 >/dev/null

# Boot it. Under heavy node load the first attempt can land in ERROR (the scheduler
# gives up before the just-started compute reports), so retry once from scratch.
for attempt in 1 2; do
  openstack server show vm2 >/dev/null 2>&1 \
    || openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2 >/dev/null

  status=""
  for i in $(seq 1 45); do
    status=$(openstack server show vm2 -f value -c status 2>/dev/null)
    case "$status" in ACTIVE|SHUTOFF|ERROR) break ;; esac
    sleep 2
  done

  [ "$status" = "ERROR" ] || break
  echo "vm2 landed in ERROR (attempt $attempt):" >&2
  openstack server show vm2 -f value -c fault 2>/dev/null | head -3 >&2
  [ "$attempt" = 2 ] && { echo "FAIL: vm2 stayed in ERROR"; exit 1; }
  openstack server delete --wait vm2 >/dev/null 2>&1 || true
done

echo "PASS"
