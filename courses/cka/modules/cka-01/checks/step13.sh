#!/bin/bash
# Q13 기동하지 않는 Deployment (10점) — 원인(없는 이미지 태그)을 고쳐 2개가 Ready 여야 한다.
# 배포를 지우고 새로 만든 답도 인정하되, 이름/레플리카/네임스페이스는 그대로여야 한다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get deploy api -n broken >/dev/null 2>&1; then
  part 0 2 step13m1
  part 0 3 step13m1
  part 0 1 step13m1
  part 0 3 step13m1
  part 0 1 step13m1
  exit 0
fi
part 2 2 q13c1     # 디플로이먼트 유지
D=$(kubectl get deploy api -n broken -o json)
img=$(echo "$D" | jq -r '.spec.template.spec.containers[0].image // ""')
case "$img" in *does-not-exist*|*1.99*) part 0 3 step13m2 "$img" ;; *) part 3 3 q13c2 ;; esac

rep=$(echo "$D" | jq -r '.spec.replicas // 0')
if [ "$rep" = "2" ]; then part 1 1 q13c3; else part 0 1 step13m3 "$rep"; fi

ready=$(echo "$D" | jq -r '.status.readyReplicas // 0')
if [ "$ready" = "2" ]; then part 3 3 q13c4; else part 0 3 step13m4 "$ready"; fi

# 남아 있는 실패 파드가 없어야 한다(구 ReplicaSet 정리 확인)
bad=$(kubectl get pod -n broken -l app=api --no-headers 2>/dev/null | grep -cvE ' Running | Completed ' || true)
if [ "${bad:-0}" -eq 0 ]; then part 1 1 q13c5; else part 0 1 step13m5 "$bad"; fi
exit 0
