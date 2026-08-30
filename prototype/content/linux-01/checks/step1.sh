#!/bin/bash
# stat %a는 ACL이 붙으면 group 자리에 mask가 보이므로(스텝3에서 ~/work에 setfacl 예정),
# 소유자·other 비트와 실제 group 엔트리(getfacl group::)로 검사한다.
cd ~ || exit 1
[ -d work ] || { labmsg step1m1; exit 1; }
p=$(printf '%03d' "$(stat -c %a work)")
{ [ "${p:0:1}" = "7" ] && [ "${p:2:1}" = "0" ]; } || { labmsg step1m2 "$p"; exit 1; }
getfacl -c work 2>/dev/null | grep -q '^group::---' || { labmsg step1m3; exit 1; }
[ -f work/secret.txt ] || { labmsg step1m4; exit 1; }
f=$(printf '%03d' "$(stat -c %a work/secret.txt)")
{ [ "${f:0:1}" = "6" ] && [ "${f:2:1}" = "0" ]; } || { labmsg step1m5 "$f"; exit 1; }
getfacl -c work/secret.txt 2>/dev/null | grep -q '^group::---' || { labmsg step1m6; exit 1; }
labmsg step1m7
