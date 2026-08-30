#!/bin/bash
# Q7 사이드카 (5점) — "두 컨테이너가 같은 emptyDir 을 실제로 공유하는가" 를 파일로 확인한다.
# 스펙만 보면 마운트만 걸어두고 공유가 안 되는 답도 통과하므로, sidecar 쪽에서 읽는다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get pod logger -n app-prod >/dev/null 2>&1; then
  for i in 1 2 3 4 5; do part 0 1 step7m1; done
  exit 0
fi
P=$(kubectl get pod logger -n app-prod -o json 2>/dev/null)
g() { echo "$P" | jq -r "$1 // \"\""; }
has() { echo "$P" | jq -e "$1" >/dev/null 2>&1; }

part 1 1 q7c1     # 파드 존재

n=$(g '.spec.containers | length')
missc=
for c in app sidecar; do
  echo "$P" | jq -e --arg c "$c" '.spec.containers[] | select(.name==$c)' >/dev/null 2>&1 || missc="$c"
done
if [ "$n" != "2" ]; then part 0 1 step7m2 "$n"
elif [ -n "$missc" ]; then part 0 1 step7m3 "$missc"
else part 1 1 q7c2; fi

missm=
for c in app sidecar; do
  echo "$P" | jq -e --arg c "$c" \
    '.spec.containers[] | select(.name==$c) | .volumeMounts[] | select(.mountPath=="/var/log/app")' >/dev/null 2>&1 \
    || missm="$c"
done
if ! has '.spec.volumes[] | select(.emptyDir != null)'; then part 0 1 step7m4
elif [ -n "$missm" ]; then part 0 1 step7m5 "$missm"
else part 1 1 q7c3; fi

if [ "$(g .status.phase)" = Running ]; then part 1 1 q7c4; else part 0 1 step7m6 "$(g .status.phase)"; fi

# 공유 확인: app 이 쓴 파일을 sidecar 에서 읽을 수 있어야 한다
out=$(timeout 12 kubectl exec -n app-prod logger -c sidecar -- sh -c 'cat /var/log/app/app.log 2>/dev/null | head -c 200' 2>/dev/null)
if [ -n "$out" ]; then part 1 1 q7c5; else part 0 1 step7m7; fi
exit 0
