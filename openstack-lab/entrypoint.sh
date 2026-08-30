#!/bin/sh
# SnackLab — openstack-lab container entrypoint (cgroup isolation before systemd).
#
# Privileged pods inherit the **host cgroup namespace** from the runtime. Unlike
# k8s-lab there is no in-pod kubelet here to go on a killing spree, but systemd
# still behaves best managing its own subtree, and keeping the same guard makes
# the two lab images uniform. We unshare cgroup+mount namespaces and remount
# /sys/fs/cgroup so this container's cgroup becomes the root of the tree
# (`/proc/self/cgroup` = `0::/`) — the same result as docker's --cgroupns=private.
#
# PID 1 is preserved: unshare without --fork keeps the exec chain on PID 1.
set -eu

CGROUP_MNT=/sys/fs/cgroup

# Only attempt isolation on a cgroup v2 unified tree.
if [ ! -f "$CGROUP_MNT/cgroup.controllers" ]; then
  echo "lab-init: not a cgroup v2 unified tree — skipping isolation" >&2
  exec /lib/systemd/systemd
fi

if ! command -v unshare >/dev/null 2>&1; then
  echo "lab-init: unshare not available — skipping isolation" >&2
  exec /lib/systemd/systemd
fi

# Remount note: overlaying the existing mount fails with EBUSY; inside the new
# mount namespace we umount first (private propagation — the host and other
# pods are unaffected), then mount fresh. On failure, boot without isolation.
exec unshare --cgroup --mount --propagation private -- /bin/sh -c '
  mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null \
    || { umount /sys/fs/cgroup 2>/dev/null && mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null; }
  if [ "$(cat /proc/self/cgroup 2>/dev/null)" = "0::/" ]; then
    echo "lab-init: cgroup namespace isolated ($(readlink /proc/self/ns/cgroup))" >&2
  else
    echo "lab-init: warning — /sys/fs/cgroup remount failed, host cgroup tree visible" >&2
  fi
  exec /lib/systemd/systemd
' || exec /lib/systemd/systemd
