#!/bin/bash
# Q1 sidecar (7 pts) — pod shape (2 containers, shared emptyDir) plus the thing
# that actually matters: the sidecar really streams the main container's log.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get pod logger -n dev >/dev/null 2>&1; then
  part 0 1 step1m1
  part 0 1 step1m1
  part 0 2 step1m1
  part 0 1 step1m1
  part 0 2 step1m1
  exit 0
fi
P=$(kubectl get pod logger -n dev -o json)
part 1 1 q1c1     # pod exists

names=$(echo "$P" | jq -r '[.spec.containers[].name] | sort | join(",")')
if [ "$names" = "app,streamer" ]; then part 1 1 q1c2; else part 0 1 step1m2 "$names"; fi

# both containers must mount the same emptyDir volume at /var/log/app
vol=$(echo "$P" | jq -r '.spec.volumes[] | select(.emptyDir != null) | .name' | head -1)
okm=0
if [ -n "$vol" ]; then
  a=$(echo "$P" | jq -r --arg v "$vol" '.spec.containers[] | select(.name=="app") | .volumeMounts[]? | select(.name==$v) | .mountPath' | head -1)
  s=$(echo "$P" | jq -r --arg v "$vol" '.spec.containers[] | select(.name=="streamer") | .volumeMounts[]? | select(.name==$v) | .mountPath' | head -1)
  [ "$a" = "/var/log/app" ] && [ "$s" = "/var/log/app" ] && okm=1
fi
if [ $okm = 1 ]; then part 2 2 q1c3; else part 0 2 step1m3; fi

phase=$(echo "$P" | jq -r .status.phase)
if [ "$phase" = "Running" ]; then part 1 1 q1c4; else part 0 1 step1m4 "$phase"; fi

# the sidecar's own log stream must show the ticks written by the main container
if timeout 15 kubectl logs logger -n dev -c streamer --tail=5 2>/dev/null | grep -q "tick"; then
  part 2 2 q1c5
else
  part 0 2 step1m5
fi
exit 0
