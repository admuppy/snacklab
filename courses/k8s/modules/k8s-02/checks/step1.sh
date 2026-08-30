#!/bin/bash
# step1: ClusterIP Service 'web' 가 app=web 을 선택하고 엔드포인트가 채워졌는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
type=$(kubectl get svc web -n default -o jsonpath='{.spec.type}' 2>/dev/null)
[ -n "$type" ] || { labmsg step1m1; exit 1; }
[ "$type" = "ClusterIP" ] || { labmsg step1m2 "$type"; exit 1; }
sel=$(kubectl get svc web -n default -o jsonpath='{.spec.selector.app}' 2>/dev/null)
[ "$sel" = "web" ] || { labmsg step1m3 "${sel:-?}"; exit 1; }
eps=$(kubectl get endpoints web -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
[ -n "$eps" ] || { labmsg step1m4; exit 1; }
labmsg step1m5 "$eps"
