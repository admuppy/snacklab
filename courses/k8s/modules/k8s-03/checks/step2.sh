#!/bin/bash
# step2: Secret 'app-secret'(Opaque) 에 DB_PASSWORD 키가 있는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get secret app-secret -n default >/dev/null 2>&1 || { labmsg step2m1; exit 1; }
type=$(kubectl get secret app-secret -n default -o jsonpath='{.type}' 2>/dev/null)
[ "$type" = "Opaque" ] || { labmsg step2m2 "$type"; exit 1; }
v=$(kubectl get secret app-secret -n default -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null)
[ -n "$v" ] || { labmsg step2m3; exit 1; }
labmsg step2m4
