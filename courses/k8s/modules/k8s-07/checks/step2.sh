#!/bin/bash
# step2: 파드 'writer' 가 PVC data 를 마운트해 Bound 를 유발하고 /data/marker.txt 를 기록했는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pod writer -n default >/dev/null 2>&1 || { labmsg step2m1; exit 1; }
phase=$(kubectl get pvc data -n default -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$phase" = "Bound" ] || { labmsg step2m2 "${phase:-?}"; exit 1; }
pp=$(kubectl get pod writer -n default -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$pp" = "Running" ] || { labmsg step2m3 "$pp"; exit 1; }
data=$(kubectl exec writer -n default -- cat /data/marker.txt 2>/dev/null)
[ -n "$data" ] || { labmsg step2m4; exit 1; }
labmsg step2m5 "$data"
