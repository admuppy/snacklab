#!/bin/bash
# step2: nice 19 + CPU 0 고정으로 실행된 stress-ng 부하 프로세스 확인
pid=$(pgrep -u "$(id -u)" -f 'stress-ng' | head -1)
[ -n "$pid" ] || { labmsg step2m1; exit 1; }
# /proc/PID/stat: 'pid (comm) ' 접두 제거 후 17번째 토큰이 nice(전체 19번째 필드)
nv=$(awk '{ sub(/^[0-9]+ \([^)]*\) /,""); print $17 }' "/proc/$pid/stat" 2>/dev/null)
[ "$nv" = "19" ] || { labmsg step2m2 "${nv:-?}"; exit 1; }
al=$(awk '/^Cpus_allowed_list:/{print $2}' "/proc/$pid/status" 2>/dev/null)
case "$al" in
  *,*|*-*|"") labmsg step2m3 "${al:-?}"; exit 1 ;;
esac
labmsg step2m4 "${al}"
