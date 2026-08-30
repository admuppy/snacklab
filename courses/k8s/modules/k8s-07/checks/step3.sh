#!/bin/bash
# step3: StatefulSet 'web' 가 volumeClaimTemplates 로 PVC(www-web-0)를 자동 생성·Bound 하고 파드 Ready
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get statefulset web -n default >/dev/null 2>&1 || { labmsg step3m1; exit 1; }
rdy=$(kubectl get statefulset web -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${rdy:-0}" -ge 1 ] 2>/dev/null || { labmsg step3m2 "${rdy:-0}"; exit 1; }
phase=$(kubectl get pvc www-web-0 -n default -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$phase" = "Bound" ] || { labmsg step3m3 "${phase:-?}"; exit 1; }
labmsg step3m4
