#!/bin/bash
# step1: 파드 'guaranteed' 의 QoS 클래스가 Guaranteed 인지 (requests==limits, cpu+memory 모두)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
q=$(kubectl get pod guaranteed -n default -o jsonpath='{.status.qosClass}' 2>/dev/null)
[ -n "$q" ] || { labmsg step1m1; exit 1; }
[ "$q" = "Guaranteed" ] || { labmsg step1m2 "$q"; exit 1; }
labmsg step1m3
