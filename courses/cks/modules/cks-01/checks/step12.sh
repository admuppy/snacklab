#!/bin/bash
# Q12 Dockerfile fixes (7 pts) — grade the edited file. Ignore comment lines so a
# commented-out ENV API_KEY still counts as removed.
F=~/work/audit/Dockerfile
if [ ! -s "$F" ]; then
  part 0 2 step12m1
  part 0 2 step12m1
  part 0 2 step12m1
  part 0 1 step12m1
  exit 0
fi
LIVE=$(grep -v '^[[:space:]]*#' "$F")

if echo "$LIVE" | grep -Eq '^FROM[[:space:]]+nginx:1\.26([[:space:]]|$)'; then
  part 2 2 q12c1
elif echo "$LIVE" | grep -Eq '^FROM.*latest'; then
  part 0 2 step12m2
else
  part 0 2 step12m3 "$(echo "$LIVE" | grep '^FROM' | head -n1)"
fi

if echo "$LIVE" | grep -q 'API_KEY'; then part 0 2 step12m4; else part 2 2 q12c2; fi

user=$(echo "$LIVE" | grep -E '^USER[[:space:]]' | tail -n1 | awk '{print $2}')
if [ -z "$user" ]; then
  part 0 2 step12m5
elif [ "$user" = "root" ] || [ "$user" = "0" ]; then
  part 0 2 step12m6
else
  part 2 2 q12c3
fi

if echo "$LIVE" | grep -q '^COPY' && echo "$LIVE" | grep -q '^CMD'; then
  part 1 1 q12c4
else
  part 0 1 step12m7
fi
exit 0
