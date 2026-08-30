#!/bin/bash
# Q6 DaemonSet (4점) — 노드마다 하나씩 뜨는지(desired == ready)와 명시적 요청량을 본다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get ds node-agent -n ops >/dev/null 2>&1; then
  for i in 1 2 3 4; do part 0 1 step6m1; done
  exit 0
fi
S=$(kubectl get ds node-agent -n ops -o json 2>/dev/null)
g() { echo "$S" | jq -r "$1 // \"\""; }

part 1 1 q6c1     # 데몬셋 존재
img=$(g '.spec.template.spec.containers[0].image')
case "$img" in busybox:1.36|docker.io/busybox:1.36|docker.io/library/busybox:1.36) part 1 1 q6c2 ;;
  *) part 0 1 step6m2 "$img" ;; esac

if [ -n "$(g '.spec.template.spec.containers[0].resources.requests.cpu')" ] \
   && [ -n "$(g '.spec.template.spec.containers[0].resources.requests.memory')" ]; then
  part 1 1 q6c3
else
  part 0 1 step6m3
fi

want=$(g .status.desiredNumberScheduled); ready=$(g .status.numberReady)
if ! [ "${want:-0}" -ge 1 ] 2>/dev/null; then part 0 1 step6m4
elif [ "${ready:-0}" = "${want}" ]; then part 1 1 q6c4
else part 0 1 step6m5 "${ready:-0}" "${want}"; fi
exit 0
