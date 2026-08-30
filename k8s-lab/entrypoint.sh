#!/bin/sh
# SnackLab — k8s-lab 컨테이너 엔트리포인트 (systemd 기동 전 cgroup 격리)
#
# 왜 필요한가:
#   privileged 파드는 containerd 로부터 **호스트 cgroup 네임스페이스**를 받는다. 그 상태로 파드 안
#   k3s 를 띄우면 내부 kubelet 이 /sys/fs/cgroup 에서 **바깥 클러스터의 kubepods.slice 전체**를 보고,
#   "API 서버에 없는 고아 파드 cgroup" 으로 판정해 그 안의 프로세스를 몰살한다(pod_container_manager
#   "Failed to kill all the processes attached to cgroup"). 실제로 자기 컨테이너의 dbus·journald·
#   containerd 가 SIGKILL 되어 k3s 가 무한 재기동했고(2026-08-02 실측 47회), 같은 노드의 다른 파드까지
#   사정권이었다.
#
# 무엇을 하는가:
#   systemd 를 띄우기 전에 cgroup + mount 네임스페이스를 unshare 하고 /sys/fs/cgroup 을 새로 마운트한다.
#   그러면 컨테이너 자신의 cgroup 이 트리의 루트가 되어(`/proc/self/cgroup` = `0::/`), 내부 kubelet 이
#   만드는 kubepods.slice 도 자기 subtree 안에만 생긴다. docker 의 `--cgroupns=private`(kind/k3d 가
#   컨테이너 안 k8s 를 돌리는 방식)와 동일한 결과를, 파드에서 직접 얻는다.
#
# PID 1 유지: unshare 에 --fork 를 주지 않으므로 exec 체인이 PID 1 을 그대로 물려준다.
set -eu

# Per-course datastore switch: when the pod is started with K3S_CLUSTER_INIT=true
# (course.json `clusterInit`, injected by the portal pod driver), persist it into the
# unit's EnvironmentFile before systemd takes over — k3s then boots with embedded etcd
# instead of sqlite, which the CKA etcd backup/restore question needs. Container env
# is visible here (we are PID 1) but not to systemd services, hence the file hand-off.
# Measured 2026-08-06: no boot-time or RSS penalty vs sqlite, +115MiB disk.
if [ "${K3S_CLUSTER_INIT:-}" = "true" ]; then
  echo "K3S_CLUSTER_INIT=true" > /etc/systemd/system/k3s.service.env
fi

CGROUP_MNT=/sys/fs/cgroup

# cgroup v2 단일 계층이 아니면(v1 하이브리드) 격리 방식이 달라 위험 — 격리 없이 그대로 진행한다.
if [ ! -f "$CGROUP_MNT/cgroup.controllers" ]; then
  echo "lab-init: cgroup v2 unified tree 아님 — cgroup 격리 생략" >&2
  exec /lib/systemd/systemd
fi

if ! command -v unshare >/dev/null 2>&1; then
  echo "lab-init: unshare 없음 — cgroup 격리 생략" >&2
  exec /lib/systemd/systemd
fi

# 격리 시도. 실패하면(권한 부족 등) 경고 후 격리 없이 부팅 — 리눅스 트랙처럼 k3s 를 쓰지 않는
# 용도로도 이 이미지가 뜰 수 있어야 하므로 하드 실패시키지 않는다.
#
# /sys/fs/cgroup 재마운트 주의: 그냥 겹쳐 mount 하면 "already mounted or mount point busy"(EBUSY)로
# 실패한다. 새 mount 네임스페이스 안에서 기존 마운트를 **먼저 umount** 한 뒤 새로 걸어야 한다
# (private 전파라 호스트/다른 파드에는 영향 없음). umount 실패 시엔 격리를 포기하고 그대로 부팅.
exec unshare --cgroup --mount --propagation private -- /bin/sh -c '
  mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null \
    || { umount /sys/fs/cgroup 2>/dev/null && mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null; }
  if [ "$(cat /proc/self/cgroup 2>/dev/null)" = "0::/" ]; then
    echo "lab-init: cgroup 네임스페이스 격리 완료 ($(readlink /proc/self/ns/cgroup))" >&2
  else
    echo "lab-init: 경고 — /sys/fs/cgroup 재마운트 실패, 호스트 cgroup 트리가 그대로 보인다" >&2
  fi
  exec /lib/systemd/systemd
' || exec /lib/systemd/systemd
