#!/bin/bash
# Q5 Deployment web (6점) — 레플리카·이미지·요청량·롤아웃 전략·기동 상태를 항목별로 본다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get deploy web -n app-prod >/dev/null 2>&1; then
  for i in 1 2 3 4 5 6; do part 0 1 step5m1; done
  exit 0
fi
D=$(kubectl get deploy web -n app-prod -o json 2>/dev/null)
g() { echo "$D" | jq -r "$1 // \"\""; }

part 1 1 q5c1     # 디플로이먼트 존재
if [ "$(g .spec.replicas)" = "3" ]; then part 1 1 q5c2; else part 0 1 step5m2 "$(g .spec.replicas)"; fi

img=$(g '.spec.template.spec.containers[0].image')
case "$img" in nginx:1.26|docker.io/nginx:1.26|docker.io/library/nginx:1.26) part 1 1 q5c3 ;;
  *) part 0 1 step5m3 "$img" ;; esac

if [ "$(g '.spec.template.spec.containers[0].resources.requests.cpu')" != "50m" ]; then
  part 0 1 step5m4 "cpu" "50m"
elif [ "$(g '.spec.template.spec.containers[0].resources.requests.memory')" != "64Mi" ]; then
  part 0 1 step5m4 "memory" "64Mi"
else
  part 1 1 q5c4
fi

if [ "$(g .spec.strategy.type)" != "RollingUpdate" ]; then
  part 0 1 step5m5
elif [ "$(g '.spec.strategy.rollingUpdate.maxSurge')" != "1" ]; then
  part 0 1 step5m6 "maxSurge" "1" "$(g '.spec.strategy.rollingUpdate.maxSurge')"
elif [ "$(g '.spec.strategy.rollingUpdate.maxUnavailable')" != "0" ]; then
  part 0 1 step5m6 "maxUnavailable" "0" "$(g '.spec.strategy.rollingUpdate.maxUnavailable')"
else
  part 1 1 q5c5
fi

ready=$(g .status.readyReplicas)
if [ "${ready:-0}" = "3" ]; then part 1 1 q5c6; else part 0 1 step5m7 "${ready:-0}"; fi
exit 0
