#!/bin/bash
# step3: DaemonSet 'node-agent' 가 모든 노드(=1개)에 배치되어 Ready 인지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get ds node-agent -n default -o json > /tmp/d.json 2>/dev/null || { labmsg step3m1; exit 1; }
des=$(jq -r '.status.desiredNumberScheduled // 0' /tmp/d.json)
rdy=$(jq -r '.status.numberReady // 0' /tmp/d.json)
[ "${des:-0}" -ge 1 ] 2>/dev/null || { labmsg step3m2 "$des"; exit 1; }
[ "$rdy" = "$des" ] || { labmsg step3m3 "$rdy" "$des"; exit 1; }
labmsg step3m4 "${des}"
