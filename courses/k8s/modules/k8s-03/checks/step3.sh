#!/bin/bash
# step3: 파드 'app' 이 Running + ConfigMap 을 env(envFrom)로, Secret 을 볼륨으로 소비하는지
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pod app -n default -o json > /tmp/app.json 2>/dev/null \
  || { labmsg step3m1; exit 1; }
phase=$(jq -r '.status.phase' /tmp/app.json)
[ "$phase" = "Running" ] || { labmsg step3m2 "$phase"; exit 1; }
jq -e '.spec.containers[0].envFrom[]? | select(.configMapRef.name=="app-config")' /tmp/app.json >/dev/null \
  || jq -e '.spec.containers[0].env[]? | select(.valueFrom.configMapKeyRef.name=="app-config")' /tmp/app.json >/dev/null \
  || { labmsg step3m3; exit 1; }
jq -e '.spec.volumes[]? | select(.secret.secretName=="app-secret")' /tmp/app.json >/dev/null \
  || { labmsg step3m4; exit 1; }
jq -e '.spec.containers[0].volumeMounts[]?' /tmp/app.json >/dev/null \
  || { labmsg step3m5; exit 1; }
labmsg step3m6
