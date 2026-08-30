#!/bin/bash
# Q3 static pod (4 pts) — the mirror pod is named <name>-<node> and must come from a
# file (config.source=file); a same-named pod created via the apiserver is wrong.
# Rebalanced 6→4 (2026-08-06): dropped the manifest-file part (the mirror pod implies
# it), mirror-pod weight 2→1. Node is picked by control-plane label, not list order —
# KWOK fake workers (Q17) also appear in `get nodes`.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
POD="ops-static-${NODE}"

if kubectl get pod "$POD" -n default >/dev/null 2>&1; then
  part 1 1 q3c2
  P=$(kubectl get pod "$POD" -n default -o json 2>/dev/null)
  src=$(echo "$P" | jq -r '.metadata.annotations["kubernetes.io/config.source"] // ""')
  if [ "$src" = file ]; then part 1 1 q3c3; else part 0 1 step3m3; fi
  img=$(echo "$P" | jq -r '.spec.containers[0].image // ""')
  case "$img" in busybox:1.36|docker.io/busybox:1.36|docker.io/library/busybox:1.36) part 1 1 q3c4 ;;
    *) part 0 1 step3m4 "$img" ;; esac
  phase=$(echo "$P" | jq -r '.status.phase // ""')
  if [ "$phase" = Running ]; then part 1 1 q3c5; else part 0 1 step3m5 "${phase:-없음}"; fi
else
  part 0 1 step3m2 "$POD"
  part 0 1 step3m2 "$POD"
  part 0 1 step3m2 "$POD"
  part 0 1 step3m2 "$POD"
fi
exit 0
