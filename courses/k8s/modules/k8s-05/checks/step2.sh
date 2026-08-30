#!/bin/bash
# step2: 파드 'burstable' 의 QoS 클래스가 Burstable 인지 (requests < limits, 또는 일부만 설정)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
q=$(kubectl get pod burstable -n default -o jsonpath='{.status.qosClass}' 2>/dev/null)
[ -n "$q" ] || { labmsg step2m1; exit 1; }
[ "$q" = "Burstable" ] || { labmsg step2m2 "$q"; exit 1; }
labmsg step2m3
