#!/bin/bash
# step2: nginx:1.26 으로 롤링 업데이트가 완료되었는지 (이미지 갱신 + 3개 updated/ready)
#
# 순서 독립성: step3 에서 롤백하면 현재 이미지는 다시 nginx:1.25 가 된다. 그때 이 체크가 FAIL 로
# 뒤집히면 학습자가 step2 를 다시 확인할 때 혼란스럽다. 그래서 "지금 1.26 이거나(아직 롤백 전),
# 1.26 으로 만들어진 ReplicaSet 이 남아 있으면(=롤링 업데이트를 실제로 수행했음)" 통과로 본다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
img=$(kubectl get deploy web -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$img" in
  *nginx:1.26*)
    upd=$(kubectl get deploy web -n default -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
    ready=$(kubectl get deploy web -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    { [ "${upd:-0}" = "3" ] && [ "${ready:-0}" = "3" ]; } \
      || { labmsg step2m1 "${upd:-0}" "${ready:-0}"; exit 1; }
    labmsg step2m2
    ;;
  *)
    # 롤백 이후 — 1.26 리비전(ReplicaSet)이 남아 있으면 업데이트를 수행한 것으로 인정
    kubectl get rs -n default -l app=web \
      -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
      | grep -q 'nginx:1.26' \
      || { labmsg step2m3 "${img:-?}"; exit 1; }
    labmsg step2m4
    ;;
esac
