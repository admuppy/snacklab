#!/bin/bash
# Q2 TLS Secret + TLS Ingress (4 pts) — resource-only grading (no controller).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

S=$(kubectl get secret web-cert -n prod -o json 2>/dev/null)
if [ -z "$S" ]; then
  part 0 1 step2m1
  part 0 1 step2m1
elif [ "$(echo "$S" | jq -r .type)" != "kubernetes.io/tls" ]; then
  part 0 1 step2m2 "$(echo "$S" | jq -r .type)"
  part 0 1 step2m2 "$(echo "$S" | jq -r .type)"
else
  part 1 1 q2c1
  cn=$(echo "$S" | jq -r '.data."tls.crt" // ""' | base64 -d 2>/dev/null \
       | openssl x509 -noout -subject 2>/dev/null)
  if echo "$cn" | grep -q "web\.snacklab\.local"; then part 1 1 q2c2; else part 0 1 step2m3; fi
fi

I=$(kubectl get ingress web-tls -n prod -o json 2>/dev/null)
if [ -z "$I" ]; then
  part 0 1 step2m4
  part 0 1 step2m4
else
  if echo "$I" | jq -e '.spec.tls[]? | select(.secretName=="web-cert")' >/dev/null 2>&1; then
    part 1 1 q2c3
  else
    part 0 1 step2m5
  fi
  ok=$(echo "$I" | jq -r '[.spec.rules[]? | select(.host=="web.snacklab.local")
        | .http.paths[]? | select(.backend.service.name=="web-svc"
          and (.backend.service.port.number==80 or .backend.service.port.name=="80"))] | length')
  if [ "${ok:-0}" -ge 1 ]; then part 1 1 q2c4; else part 0 1 step2m6; fi
fi
exit 0
