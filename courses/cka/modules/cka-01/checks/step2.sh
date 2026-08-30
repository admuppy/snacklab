#!/bin/bash
# Q2 CSR approval + user access (4 pts) — approval must have produced an actual
# certificate (status.certificate). Rebalanced 7→4 (2026-08-06): approval and
# issuance merged into one part, can-i weight 2→1.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get csr dev-user >/dev/null 2>&1; then
  cond=$(kubectl get csr dev-user -o jsonpath='{.status.conditions[*].type}' 2>/dev/null)
  crt=$(kubectl get csr dev-user -o jsonpath='{.status.certificate}' 2>/dev/null)
  case "$cond" in
    *Denied*)   part 0 1 step2m2 ;;
    *Approved*) if [ ${#crt} -gt 100 ]; then part 1 1 q2a1; else part 0 1 step2m4; fi ;;
    *)          part 0 1 step2m3 ;;
  esac
else
  part 0 1 step2m1
fi

if kubectl get rolebinding dev-user-view -n app-prod >/dev/null 2>&1; then part 1 1 q2c3; else part 0 1 step2m5; fi

if [ "$(kubectl auth can-i list pods -n app-prod --as=dev-user 2>/dev/null)" = yes ]; then
  part 1 1 q2c4
else
  part 0 1 step2m6
fi
if [ "$(kubectl auth can-i delete pods -n app-prod --as=dev-user 2>/dev/null)" = no ]; then
  part 1 1 q2c5
else
  part 0 1 step2m7
fi
exit 0
