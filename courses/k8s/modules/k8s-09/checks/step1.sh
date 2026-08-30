#!/bin/bash
# step1: 정책 적용 전 베이스라인(client → web 통신 성공)을 ~/work/baseline.txt 로 기록했는지.
#
# "그냥 눈으로 확인" 만 시키면 체크가 아무 조작 없이도 통과해(거짓 PASS) 의미가 없다. 그래서
# 베이스라인 응답을 파일로 남기게 한다. 파일은 이후 단계(default-deny·allow)에서 정책을 걸어도
# 그대로 남으므로 이 체크는 **순서에 무관하게** 유효하다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pod client -n default >/dev/null 2>&1 || { labmsg step1m1; exit 1; }
f=$HOME/work/baseline.txt
[ -s "$f" ] || { labmsg step1m2 "$f"; exit 1; }
grep -qi '<!DOCTYPE html>\|nginx' "$f" \
  || { labmsg step1m3 "$f"; exit 1; }
labmsg step1m4
