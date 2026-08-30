#!/bin/bash
# Q16 etcd backup + offline restore (6 pts). The datastore is k3s embedded etcd
# (course.json clusterInit). Backup is the real-exam etcdctl flow; restore is graded
# as the offline half only (etcdutl --data-dir) so the running cluster — and the rest
# of the exam — is never touched. Files may be root-owned (sudo), so every test goes
# through sudo.
BK=/home/learner/backup
SNAP=$BK/etcd-snap.db
RESTORED=$BK/restored

# [1] snapshot file exists and is non-empty
if sudo test -s "$SNAP"; then part 1 1 q16c1; else part 0 1 step16m1; fi

# [2] it is a valid etcd snapshot with actual data (etcdutl parses it and reports
#     a positive revision — a random file or an empty db fails here)
rev=$(sudo etcdutl snapshot status "$SNAP" --write-out=json 2>/dev/null | jq -r '.revision // 0')
if [ "${rev:-0}" -gt 0 ] 2>/dev/null; then part 2 2 q16c2; else part 0 2 step16m2; fi

# [3] offline restore produced a real etcd data dir (member/snap/db is written by
#     etcdutl/etcdctl restore; a hand-made empty dir fails)
if sudo test -s "$RESTORED/member/snap/db"; then part 3 3 q16c3; else part 0 3 step16m3; fi
exit 0
