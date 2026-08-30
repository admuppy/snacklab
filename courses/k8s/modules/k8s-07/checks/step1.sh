#!/bin/bash
# step1: PVC 'data' 가 존재하고 스토리지 용량을 요청하는지 (local-path 는 WaitForFirstConsumer 라
# 소비 파드가 붙기 전엔 Pending 이 정상 — 여기선 Bound 를 요구하지 않는다)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pvc data -n default >/dev/null 2>&1 || { labmsg step1m1; exit 1; }
req=$(kubectl get pvc data -n default -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
[ -n "$req" ] || { labmsg step1m2; exit 1; }
phase=$(kubectl get pvc data -n default -o jsonpath='{.status.phase}' 2>/dev/null)
labmsg step1m3 "${req}" "${phase}"
