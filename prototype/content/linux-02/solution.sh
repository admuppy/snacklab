#!/bin/bash
set -e
mkdir -p ~/work
pid=$(pgrep -f '/opt/lab/bin/lab-worker' | head -1)
echo "$pid" > ~/work/worker.pid
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
sudo systemctl kill -s KILL lab-stubborn
sudo pkill -9 -f /opt/lab/bin/lab-stubborn || true
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
sleep 1
sudo ss -ltnp | grep 5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
