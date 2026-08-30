#!/bin/bash
# Q11 정적 PV/PVC (5점) — PVC 가 "그 PV 에" 바인딩됐는지까지 확인한다(다른 SC 로 동적 생성된
# 볼륨에 붙어도 Bound 는 되므로 이름 대조가 필요하다).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get pv pv-data >/dev/null 2>&1; then
  V=$(kubectl get pv pv-data -o json)
  cap=$(echo "$V" | jq -r '.spec.capacity.storage // ""')
  sc=$(echo "$V" | jq -r '.spec.storageClassName // ""')
  if [ "$cap" != "1Gi" ]; then part 0 1 step11m2 "${cap:-(없음)}"
  elif ! echo "$V" | jq -e '.spec.accessModes | index("ReadWriteOnce")' >/dev/null 2>&1; then part 0 1 step11m3
  elif [ "$sc" != "manual" ]; then part 0 1 step11m4 "${sc:-(없음)}"
  else part 1 1 q11c1; fi
else
  part 0 1 step11m1
fi

if kubectl get pvc pvc-data -n app-prod >/dev/null 2>&1; then
  C=$(kubectl get pvc pvc-data -n app-prod -o json)
  ph=$(echo "$C" | jq -r '.status.phase // ""')
  vn=$(echo "$C" | jq -r '.spec.volumeName // ""')
  if [ "$ph" = Bound ]; then part 1 1 q11c2; else part 0 1 step11m6 "${ph:-(없음)}"; fi
  if [ "$vn" = "pv-data" ]; then part 1 1 q11c3; else part 0 1 step11m7 "${vn:-(없음)}"; fi
else
  part 0 1 step11m5
  part 0 1 step11m5
fi

if kubectl get pod data-user -n app-prod >/dev/null 2>&1; then
  P=$(kubectl get pod data-user -n app-prod -o json)
  if ! echo "$P" | jq -e '.spec.volumes[] | select(.persistentVolumeClaim.claimName=="pvc-data")' >/dev/null 2>&1; then
    part 0 1 step11m9
  elif ! echo "$P" | jq -e '.spec.containers[].volumeMounts[] | select(.mountPath=="/data")' >/dev/null 2>&1; then
    part 0 1 step11m10
  else
    part 1 1 q11c4
  fi
  ph=$(echo "$P" | jq -r '.status.phase // ""')
  if [ "$ph" = Running ]; then part 1 1 q11c5; else part 0 1 step11m11 "${ph:-(없음)}"; fi
else
  part 0 1 step11m8
  part 0 1 step11m8
fi
exit 0
