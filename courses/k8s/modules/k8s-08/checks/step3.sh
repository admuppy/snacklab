#!/bin/bash
# step3: deployer 는 pods 를 list 할 수 있어야(yes) 하고, delete 는 할 수 없어야(no) 한다 — 최소권한
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SA=system:serviceaccount:default:deployer
can_list=$(kubectl auth can-i list pods --as="$SA" -n default 2>/dev/null)
can_del=$(kubectl auth can-i delete pods --as="$SA" -n default 2>/dev/null)
[ "$can_list" = "yes" ] || { labmsg step3m1 "${can_list:-?}"; exit 1; }
[ "$can_del" = "no" ]  || { labmsg step3m2 "${can_del:-?}"; exit 1; }
labmsg step3m3
