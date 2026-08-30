#!/bin/bash
# step2: NodePort Service 'web-np' 가 type=NodePort + 엔드포인트 채워짐
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
type=$(kubectl get svc web-np -n default -o jsonpath='{.spec.type}' 2>/dev/null)
[ -n "$type" ] || { labmsg step2m1; exit 1; }
[ "$type" = "NodePort" ] || { labmsg step2m2 "$type"; exit 1; }
np=$(kubectl get svc web-np -n default -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
[ -n "$np" ] || { labmsg step2m3; exit 1; }
eps=$(kubectl get endpoints web-np -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
[ -n "$eps" ] || { labmsg step2m4; exit 1; }
labmsg step2m5 "${np}"
