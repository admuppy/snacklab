#!/bin/bash
# Q6 dangerous ClusterRoleBinding (4 pts) — name recorded, binding gone,
# the default cluster-admin binding untouched.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ ! -s ~/answers/q6.txt ]; then
  part 0 2 step6m1
else
  ans=$(tr -d '[:space:]' < ~/answers/q6.txt)
  if [ "$ans" = "debug-admin-binding" ] || [ "$ans" = "clusterrolebinding/debug-admin-binding" ]; then
    part 2 2 q6c1
  else
    part 0 2 step6m2 "$(head -c 80 ~/answers/q6.txt | tr -d '\n')"
  fi
fi

if kubectl get clusterrolebinding debug-admin-binding >/dev/null 2>&1; then
  part 0 1 step6m3
else
  part 1 1 q6c2
fi

if kubectl get clusterrolebinding cluster-admin >/dev/null 2>&1; then
  part 1 1 q6c3
else
  part 0 1 step6m4
fi
exit 0
