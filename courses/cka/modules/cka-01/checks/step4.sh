#!/bin/bash
# Q4 ResourceQuota / LimitRange (3 pts) — values are compared normalized (kubectl
# already returns 1 == 1000m, 1Gi == 1024Mi normalized, so string compare suffices).
# Rebalanced 5→3 (2026-08-06): existence and values merged per object (quota 2, LR 1).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get resourcequota ops-quota -n ops >/dev/null 2>&1; then
  q() { kubectl get resourcequota ops-quota -n ops -o jsonpath="{.spec.hard.$1}" 2>/dev/null; }
  bad=
  [ "$(q pods)" = "5" ] || bad="pods|5|$(q pods)"
  if [ -z "$bad" ]; then case "$(q 'requests\.cpu')" in 1|1000m) : ;; *) bad="requests.cpu|1|$(q 'requests\.cpu')" ;; esac; fi
  if [ -z "$bad" ]; then case "$(q 'requests\.memory')" in 1Gi|1024Mi) : ;; *) bad="requests.memory|1Gi|$(q 'requests\.memory')" ;; esac; fi
  if [ -z "$bad" ]; then part 2 2 q4c2; else
    IFS='|' read -r f w g <<<"$bad"; part 0 2 step4m2 "$f" "$w" "${g:-(없음)}"
  fi
else
  part 0 2 step4m1
fi

if kubectl get limitrange ops-limits -n ops >/dev/null 2>&1; then
  L=$(kubectl get limitrange ops-limits -n ops -o json 2>/dev/null)
  pick() { echo "$L" | jq -r --arg k "$1" --arg f "$2" \
    '[.spec.limits[] | select(.type=="Container") | .[$f][$k]] | first // ""'; }
  bad=
  [ "$(pick cpu defaultRequest)" = "100m" ]     || bad="defaultRequest.cpu|100m|$(pick cpu defaultRequest)"
  [ -n "$bad" ] || [ "$(pick memory defaultRequest)" = "128Mi" ] || bad="defaultRequest.memory|128Mi|$(pick memory defaultRequest)"
  [ -n "$bad" ] || [ "$(pick cpu default)" = "200m" ]            || bad="default.cpu|200m|$(pick cpu default)"
  [ -n "$bad" ] || [ "$(pick memory default)" = "256Mi" ]        || bad="default.memory|256Mi|$(pick memory default)"
  if [ -z "$bad" ]; then part 1 1 q4c4; else
    IFS='|' read -r f w g <<<"$bad"; part 0 1 step4m4 "$f" "$w" "${g:-(없음)}"
  fi
else
  part 0 1 step4m3
fi
exit 0
