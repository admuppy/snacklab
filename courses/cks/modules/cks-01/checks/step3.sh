#!/bin/bash
# Q3 binary verification (4 pts) — the tampered file is kubelet (bootstrap appends
# a byte after computing checksums.txt).
if [ ! -s ~/answers/q3.txt ]; then
  part 0 1 step3m1
  part 0 3 step3m1
  exit 0
fi
part 1 1 q3c1
ans=$(tr -d '[:space:]' < ~/answers/q3.txt | tr 'A-Z' 'a-z')
if [ "$ans" = "kubelet" ] || [ "$ans" = "./kubelet" ]; then
  part 3 3 q3c2
else
  part 0 3 step3m2 "$(head -c 80 ~/answers/q3.txt | tr -d '\n')"
fi
exit 0
