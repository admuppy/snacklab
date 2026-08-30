#!/bin/bash
# Q4 rolling update (7 pts) — strategy fields, new image, and a finished rollout
# (revision bumped, every replica updated and Ready).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get deploy api -n prod >/dev/null 2>&1; then
  part 0 2 step4m1
  part 0 2 step4m1
  part 0 1 step4m1
  part 0 2 step4m1
  exit 0
fi
D=$(kubectl get deploy api -n prod -o json)
g() { echo "$D" | jq -r "$1 // \"\""; }

if [ "$(g .spec.strategy.type)" != "RollingUpdate" ]; then
  part 0 2 step4m2
elif [ "$(g '.spec.strategy.rollingUpdate.maxSurge')" != "1" ]; then
  part 0 2 step4m3 "maxSurge" "1" "$(g '.spec.strategy.rollingUpdate.maxSurge')"
elif [ "$(g '.spec.strategy.rollingUpdate.maxUnavailable')" != "0" ]; then
  part 0 2 step4m3 "maxUnavailable" "0" "$(g '.spec.strategy.rollingUpdate.maxUnavailable')"
else
  part 2 2 q4c1
fi

img=$(g '.spec.template.spec.containers[0].image')
okimg=0
case "$img" in nginx:1.26|docker.io/nginx:1.26|docker.io/library/nginx:1.26) okimg=1 ;; esac
if [ $okimg = 1 ]; then part 2 2 q4c2; else part 0 2 step4m4 "$img"; fi

rev=$(echo "$D" | jq -r '.metadata.annotations["deployment.kubernetes.io/revision"] // "0"')
if [ "$rev" -ge 2 ] 2>/dev/null; then part 1 1 q4c3; else part 0 1 step4m5 "$rev"; fi

# updatedReplicas is relative to the current template, so the untouched initial
# state already reports 2/2 — gate this item on the new image to avoid free points
ready=$(g .status.readyReplicas); upd=$(g .status.updatedReplicas)
if [ $okimg = 1 ] && [ "${ready:-0}" = "2" ] && [ "${upd:-0}" = "2" ]; then part 2 2 q4c4; else part 0 2 step4m6 "${ready:-0}" "${upd:-0}"; fi
exit 0
