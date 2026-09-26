#!/bin/bash
set -e
mkdir -p ~/work
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 | head -1 > ~/work/myip.txt
echo 9090 > ~/work/api-port.txt
sudo sed -i 's/--bind 127\.0\.0\.1/--bind 0.0.0.0/' /etc/systemd/system/lab-api.service
sudo systemctl daemon-reload
sudo systemctl restart lab-api.service
grep -q 'api.lab.local' /etc/hosts || echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts >/dev/null
for i in $(seq 1 10); do curl -sf -o /dev/null http://api.lab.local:9090/status.json && break; sleep 1; done
