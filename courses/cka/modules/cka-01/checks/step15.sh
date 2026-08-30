#!/bin/bash
# Q15 CrashLoopBackOff (10점) — 복구(Ready) + 재시작이 멈췄는지 + 원인 리소스 보고 파일.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get deploy worker -n broken >/dev/null 2>&1; then
  part 0 2 step15m1
  part 0 3 step15m1
  part 0 2 step15m1
else
  ready=$(kubectl get deploy worker -n broken -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "${ready:-0}" -ge 1 ] 2>/dev/null; then part 2 2 q15c1; else part 0 2 step15m2 "${ready:-0}"; fi

  # 살아 있는 파드가 재시작 루프에 있지 않아야 한다 — 30초 간격으로 두 번 재보지 않고,
  # "지금 Ready 인 파드가 최근 20초 안에 재시작하지 않았다" 로 판정한다.
  pod=$(kubectl get pod -n broken -l app=worker \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
  if [ -z "$pod" ]; then
    part 0 3 step15m3
    part 0 2 step15m3
  else
    state=$(kubectl get pod "$pod" -n broken -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
    if [ -z "$state" ]; then part 3 3 q15c2; else part 0 3 step15m4 "$state"; fi
    started=$(kubectl get pod "$pod" -n broken -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)
    if [ -z "$started" ]; then
      part 0 2 step15m5
    else
      age=$(( $(date -u +%s) - $(date -u -d "$started" +%s) ))
      if [ "$age" -ge 20 ]; then part 2 2 q15c3; else part 0 2 step15m6 "$age"; fi
    fi
  fi
fi

# 원인 보고서
F=$HOME/answers/q15.txt
if [ ! -f "$F" ]; then
  part 0 3 step15m7
else
  ans=$(tr 'A-Z' 'a-z' < "$F" | tr -d ' \t\r' | head -1)
  if [ "$ans" = "configmap/worker-config" ]; then part 3 3 q15c4; else part 0 3 step15m8 "${ans:-(빈 파일)}"; fi
fi
exit 0
