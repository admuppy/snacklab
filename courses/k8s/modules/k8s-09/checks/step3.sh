#!/bin/bash
# step3: web-allow-client(ingress from app=client) 정책이 있고, client → web 통신이 다시 열렸는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get netpol web-allow-client -n default >/dev/null 2>&1 \
  || { labmsg step3m1; exit 1; }
if ! kubectl exec client -n default -- wget -q -T 3 -t 1 -O- http://web >/dev/null 2>&1; then
  labmsg step3m2; exit 1
fi
labmsg step3m3
