#!/bin/bash
# step2: Service 'shop' 의 셀렉터 수리로 엔드포인트가 채워졌는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get svc shop -n default >/dev/null 2>&1 || { labmsg step2m1; exit 1; }
sel=$(kubectl get svc shop -n default -o jsonpath='{.spec.selector.app}' 2>/dev/null)
[ "$sel" = "shop" ] || { labmsg step2m2 "${sel:-?}"; exit 1; }
eps=$(kubectl get endpoints shop -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
[ -n "$eps" ] || { labmsg step2m3; exit 1; }
labmsg step2m4 "$eps"
