#!/bin/bash
# step3: nginx:1.25(최초 버전)로 롤백 + 리비전 3개 이상(생성→업데이트→undo)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
img=$(kubectl get deploy web -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$img" in
  *nginx:1.25*) ;;
  *) labmsg step3m1 "${img:-?}"; exit 1 ;;
esac
# 리비전 "개수"가 아니라 **최신 리비전 번호**로 판정한다 — undo 는 되돌린 ReplicaSet 에 새 리비전
# 번호를 부여하므로(1→2→3) 히스토리 줄 수는 2개로 유지된다. 줄 수로 세면 정상 수행도 FAIL 이다.
rev=$(kubectl rollout history deploy/web -n default 2>/dev/null | awk '/^[0-9]+/{n=$1} END{print n+0}')
[ "${rev:-0}" -ge 3 ] 2>/dev/null \
  || { labmsg step3m2 "${rev:-0}"; exit 1; }
ready=$(kubectl get deploy web -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${ready:-0}" = "3" ] || { labmsg step3m3 "${ready:-0}"; exit 1; }
labmsg step3m4
