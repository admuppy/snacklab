#!/bin/bash
# step3: 헬스 파일 소멸로 liveness 가 실패해 kubelet 이 컨테이너를 재시작했는지(restartCount>=1)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
pod=$(kubectl get pod -l app=web -n default -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$pod" ] || { labmsg step3m1; exit 1; }
rc=$(kubectl get pod "$pod" -n default -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
[ "${rc:-0}" -ge 1 ] 2>/dev/null \
  || { labmsg step3m2 "${rc:-0}"; exit 1; }
labmsg step3m3 "${rc}"
