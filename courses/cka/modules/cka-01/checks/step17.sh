#!/bin/bash
# Q17 drain worker-1 (3 pts). worker-1/worker-2 are KWOK fake nodes (bootstrap.sh);
# eviction and rescheduling behave like the real thing, so grading looks at outcomes:
# cordoned, emptied, and the workload still fully available on worker-2.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# [1] worker-1 is cordoned (drain implies cordon; cordon alone also earns this part)
if [ "$(kubectl get node worker-1 -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" = "true" ]; then
  part 1 1 q17c1
else
  part 0 1 step17m1
fi

# [2] no payments pods left on worker-1 (evicted, not stuck Terminating)
left=$(kubectl get pods -n maint -o json 2>/dev/null \
  | jq -r '[.items[] | select(.spec.nodeName=="worker-1")] | length')
if [ "${left:-1}" = "0" ]; then part 1 1 q17c2; else part 0 1 step17m2 "${left:-?}"; fi

# [3] the workload survived the move — 4/4 available on the remaining worker
avail=$(kubectl get deploy payments -n maint -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
if [ "${avail:-0}" = "4" ]; then part 1 1 q17c3; else part 0 1 step17m3 "${avail:-0}"; fi
exit 0
