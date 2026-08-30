#!/bin/bash
# Q16 runtime forensics (12 pts) — right deployment named, quarantined to 0 replicas,
# innocent workloads untouched.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ ! -s ~/answers/q16.txt ]; then
  part 0 4 step16m1
else
  ans=$(tr -d '[:space:]' < ~/answers/q16.txt | tr 'A-Z' 'a-z' | sed 's/^deployment\///')
  if [ "$ans" = "logshipper" ]; then
    part 4 4 q16c1
  else
    part 0 4 step16m2 "$(head -c 80 ~/answers/q16.txt | tr -d '\n')"
  fi
fi

r=$(kubectl get deploy logshipper -n runtime -o jsonpath='{.spec.replicas}' 2>/dev/null)
left=$(kubectl get pod -n runtime -l app=logshipper --no-headers 2>/dev/null | grep -cv Terminating)
if [ "$r" = "0" ] && [ "${left:-0}" = "0" ]; then
  part 4 4 q16c2
elif [ "$r" = "0" ]; then
  part 0 4 step16m3
else
  part 0 4 step16m4 "${r:-missing}"
fi

bad=
for d in web metrics; do
  ready=$(kubectl get deploy "$d" -n runtime -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${ready:-0}" -ge 1 ] || bad="$d"
done
if [ -z "$bad" ]; then part 4 4 q16c3; else part 0 4 step16m5 "$bad"; fi
exit 0
