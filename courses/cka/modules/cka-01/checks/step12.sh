#!/bin/bash
# Q12 동적 프로비저닝 (5점) — 기본 StorageClass(local-path)로 볼륨이 잡히고, 그 볼륨에
# 데이터가 실제로 쓰였는지 파일 내용으로 판정한다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get pvc pvc-dyn -n app-prod >/dev/null 2>&1; then
  part 1 1 q12c1
  C=$(kubectl get pvc pvc-dyn -n app-prod -o json)
  ph=$(echo "$C" | jq -r '.status.phase // ""')
  sc=$(echo "$C" | jq -r '.spec.storageClassName // ""')
  req=$(echo "$C" | jq -r '.spec.resources.requests.storage // ""')
  if [ "$ph" != Bound ]; then part 0 1 step12m2 "${ph:-(없음)}"
  elif [ "$sc" != "local-path" ]; then part 0 1 step12m3 "${sc:-(기본값)}"
  else part 1 1 q12c2; fi
  if [ "$req" = "500Mi" ]; then part 1 1 q12c3; else part 0 1 step12m4 "${req:-(없음)}"; fi
else
  part 0 1 step12m1
  part 0 1 step12m1
  part 0 1 step12m1
fi

if kubectl get pod writer -n app-prod >/dev/null 2>&1; then
  P=$(kubectl get pod writer -n app-prod -o json)
  ph=$(echo "$P" | jq -r '.status.phase // ""')
  if ! echo "$P" | jq -e '.spec.volumes[] | select(.persistentVolumeClaim.claimName=="pvc-dyn")' >/dev/null 2>&1; then
    part 0 1 step12m6
  elif [ "$ph" != Running ]; then
    part 0 1 step12m7 "${ph:-(없음)}"
  else
    part 1 1 q12c4
  fi
  out=$(timeout 12 kubectl exec -n app-prod writer -- sh -c 'cat /data/hello.txt 2>/dev/null' 2>/dev/null)
  if echo "$out" | grep -q "cka"; then part 1 1 q12c5; else part 0 1 step12m8; fi
else
  part 0 1 step12m5
  part 0 1 step12m5
fi
exit 0
