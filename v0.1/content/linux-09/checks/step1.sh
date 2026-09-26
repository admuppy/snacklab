#!/bin/bash
# step1: ~/work/snapshot.txt 에 현재 MemTotal 과 CPU 수가 기록되었는지
f="$HOME/work/snapshot.txt"
[ -f "$f" ] || { labmsg step1m1; exit 1; }
memtotal=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
grep -q "MemTotal" "$f" && grep -q "\b${memtotal}\b" "$f" \
  || { labmsg step1m2 "${memtotal}"; exit 1; }
cpus=$(nproc)
grep -q "cpus=${cpus}\b" "$f" \
  || { labmsg step1m3 "${cpus}"; exit 1; }
labmsg step1m4
