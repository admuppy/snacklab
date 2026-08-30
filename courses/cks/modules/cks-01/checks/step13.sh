#!/bin/bash
# Q13 vulnerable-image triage (7 pts) — answer file must name exactly the two
# CRITICAL deployments; those scaled to 0, the clean one untouched.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ ! -s ~/answers/q13.txt ]; then
  part 0 3 step13m1
else
  # normalize: lowercase, strip blanks/prefixes, sort
  norm=$(tr 'A-Z' 'a-z' < ~/answers/q13.txt | sed 's/^deployment\///; s/[[:space:]]//g' | grep -v '^$' | sort -u | tr '\n' ' ')
  if [ "$norm" = "frontend-app report-app " ]; then
    part 3 3 q13c1
  else
    part 0 3 step13m2 "$norm"
  fi
fi

bad=
for d in frontend-app report-app; do
  r=$(kubectl get deploy "$d" -n supply -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [ "$r" = "0" ] || bad="$d"
done
if [ -z "$bad" ]; then part 2 2 q13c2; else part 0 2 step13m3 "$bad"; fi

ready=$(kubectl get deploy batch-app -n supply -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "${ready:-0}" -ge 1 ]; then part 2 2 q13c3; else part 0 2 step13m4; fi
exit 0
