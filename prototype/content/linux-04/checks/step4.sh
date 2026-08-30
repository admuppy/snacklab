#!/bin/bash
f=~/work/backup-fixed.sh
[ -x $f ] || { labmsg step4m1; exit 1; }
t=$(mktemp -d '/tmp/check4 src XXXX')   # 공백이 든 디렉터리 이름 — 원본 backup.sh는 여기서 죽는다
echo hello > "$t/a.txt"
out=$($f "$t" 2>/dev/null); rc=$?
rm -rf "$t"
[ $rc -eq 0 ] || { labmsg step4m2 "$rc"; exit 1; }
echo "$out" | grep -q 'complete' || { labmsg step4m3; exit 1; }
dest=$(echo "$out" | grep -o '/tmp/backup-[0-9]*' | tail -1)
[ -n "$dest" ] && [ -f "$dest/a.txt" ] || { labmsg step4m4; exit 1; }
rm -rf "$dest"
labmsg step4m5
