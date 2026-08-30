#!/bin/bash
# step3: LimitRange 'mem-defaults' 가 있고, 명시 없이 만든 파드 'defaulted' 가 그 기본 limit 을 물려받았는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get limitrange mem-defaults -n default >/dev/null 2>&1 \
  || { labmsg step3m1; exit 1; }
kubectl get pod defaulted -n default >/dev/null 2>&1 \
  || { labmsg step3m2; exit 1; }
lim=$(kubectl get pod defaulted -n default -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)
[ -n "$lim" ] || { labmsg step3m3; exit 1; }
labmsg step3m4 "${lim}"
