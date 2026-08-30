#!/bin/bash
# step1: Deployment 'web' 가 replicas=3 으로 전부 Ready 인지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
want=$(kubectl get deploy web -n default -o jsonpath='{.spec.replicas}' 2>/dev/null)
[ -n "$want" ] || { labmsg step1m1; exit 1; }
[ "$want" = "3" ] || { labmsg step1m2 "$want"; exit 1; }
ready=$(kubectl get deploy web -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${ready:-0}" = "3" ] || { labmsg step1m3 "${ready:-0}"; exit 1; }
labmsg step1m4
