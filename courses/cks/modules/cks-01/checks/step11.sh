#!/bin/bash
# Q11 Secrets (6 pts) — decoded value in the answer file, new secret, read-only mount.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ ! -s ~/answers/q11.txt ]; then
  part 0 2 step11m1
else
  ans=$(head -n1 ~/answers/q11.txt | tr -d '[:space:]')
  if [ "$ans" = 'S3cr3t-CKS!' ]; then part 2 2 q11c1; else part 0 2 step11m2; fi
fi

tok=$(kubectl get secret api-token -n apps -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)
if [ -z "$tok" ]; then
  part 0 2 step11m3
elif [ "$tok" = "cks-2026" ]; then
  part 2 2 q11c2
else
  part 0 2 step11m4
fi

P=$(kubectl get pod secret-user -n apps -o json 2>/dev/null)
if [ -z "$P" ]; then
  part 0 2 step11m5
elif [ "$(echo "$P" | jq -r .status.phase)" != "Running" ]; then
  part 0 2 step11m6 "$(echo "$P" | jq -r .status.phase)"
else
  okvol=$(echo "$P" | jq -r '[.spec.volumes[]? | select(.secret.secretName=="db-creds")] | length')
  okmnt=$(echo "$P" | jq -r '[.spec.containers[].volumeMounts[]? | select(.mountPath=="/etc/creds")] | length')
  if [ "${okvol:-0}" -ge 1 ] && [ "${okmnt:-0}" -ge 1 ]; then
    part 2 2 q11c3
  else
    part 0 2 step11m7
  fi
fi
exit 0
