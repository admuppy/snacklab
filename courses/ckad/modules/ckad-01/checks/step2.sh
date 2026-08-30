#!/bin/bash
# Q2 Job / CronJob (7 pts) — Job spec and actual completion count, CronJob
# schedule and policies. The CronJob never fires during the session (03:00),
# so only its spec can be graded — same as the real exam.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get job pi -n batch >/dev/null 2>&1; then
  J=$(kubectl get job pi -n batch -o json)
  comp=$(echo "$J" | jq -r '.spec.completions // ""')
  para=$(echo "$J" | jq -r '.spec.parallelism // ""')
  if [ "$comp" = "3" ] && [ "$para" = "2" ]; then part 2 2 q2c1; else part 0 2 step2m2 "${comp:-(none)}" "${para:-(none)}"; fi
  suc=$(echo "$J" | jq -r '.status.succeeded // 0')
  if [ "$suc" = "3" ]; then part 2 2 q2c2; else part 0 2 step2m3 "$suc"; fi
else
  part 0 2 step2m1 "Job" "pi"
  part 0 2 step2m1 "Job" "pi"
fi

if kubectl get cronjob cleanup -n batch >/dev/null 2>&1; then
  C=$(kubectl get cronjob cleanup -n batch -o json)
  sch=$(echo "$C" | jq -r '.spec.schedule // ""')
  if [ "$sch" = "0 3 * * *" ]; then part 1 1 q2c3; else part 0 1 step2m4 "${sch:-(none)}"; fi
  pol=$(echo "$C" | jq -r '.spec.concurrencyPolicy // ""')
  if [ "$pol" = "Forbid" ]; then part 1 1 q2c4; else part 0 1 step2m5 "${pol:-(none)}"; fi
  # no // fallback: the field must compare as the number 1 even though 3 is the default
  hist=$(echo "$C" | jq -r '.spec.successfulJobsHistoryLimit')
  if [ "$hist" = "1" ]; then part 1 1 q2c5; else part 0 1 step2m6 "$hist"; fi
else
  part 0 1 step2m1 "CronJob" "cleanup"
  part 0 1 step2m1 "CronJob" "cleanup"
  part 0 1 step2m1 "CronJob" "cleanup"
fi
exit 0
