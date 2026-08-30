#!/bin/bash
# step3: lab.slice 에 메모리 상한이 걸리고 그 안에서 OOM(oom_kill)이 발생했는지.
# 파드 자신의 cgroup 하위(.../<container>.scope/lab.slice)만 검사한다 — 호스트 cgroup 루트는 건드리지 않는다.
cgp=$(systemctl show -p ControlGroup --value lab.slice 2>/dev/null)
cg="/sys/fs/cgroup${cgp}"
[ -n "$cgp" ] && [ -d "$cg" ] \
  || { labmsg step3m1; exit 1; }
mx=$(cat "$cg/memory.max" 2>/dev/null)
[ -n "$mx" ] && [ "$mx" != "max" ] \
  || { labmsg step3m2 "${mx:-?}"; exit 1; }
ok=$(awk '/^oom_kill /{print $2}' "$cg/memory.events" 2>/dev/null)
[ "${ok:-0}" -ge 1 ] 2>/dev/null \
  || { labmsg step3m3; exit 1; }
labmsg step3m4 "${mx}" "${ok}"
