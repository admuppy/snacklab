#!/bin/bash
# step3: Headless Service 'web-h' (clusterIP: None) + 엔드포인트(파드 IP) 존재
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cip=$(kubectl get svc web-h -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
[ -n "$cip" ] || { labmsg step3m1; exit 1; }
[ "$cip" = "None" ] || { labmsg step3m2 "$cip"; exit 1; }
eps=$(kubectl get endpoints web-h -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
[ -n "$eps" ] || { labmsg step3m3; exit 1; }
n=$(echo "$eps" | wc -w)
labmsg step3m4 "${n}" "$eps"
