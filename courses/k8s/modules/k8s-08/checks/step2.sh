#!/bin/bash
# step2: Role 'pod-reader'(pods get/list/watch) + RoleBinding 'read-pods'(→ SA deployer)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get role pod-reader -n default -o json > /tmp/r.json 2>/dev/null \
  || { labmsg step2m1; exit 1; }
jq -e '.rules[]? | select((.resources//[]) | index("pods")) | select((.verbs//[]) | index("list"))' /tmp/r.json >/dev/null \
  || { labmsg step2m2; exit 1; }
kubectl get rolebinding read-pods -n default -o json > /tmp/rb.json 2>/dev/null \
  || { labmsg step2m3; exit 1; }
rr=$(jq -r '.roleRef.name' /tmp/rb.json)
[ "$rr" = "pod-reader" ] || { labmsg step2m4 "${rr:-?}"; exit 1; }
jq -e '.subjects[]? | select(.kind=="ServiceAccount" and .name=="deployer")' /tmp/rb.json >/dev/null \
  || { labmsg step2m5; exit 1; }
labmsg step2m6
