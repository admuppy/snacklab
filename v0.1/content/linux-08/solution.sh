#!/bin/bash
set -e
mkdir -p ~/work
sudo sed -i 's|^ExecStart=/usr/bin/python3\.99|ExecStart=/usr/bin/python3|' /etc/systemd/system/lab-app.service
sudo systemctl daemon-reload
sudo systemctl disable --now lab-squatter.service >/dev/null 2>&1 || true
sudo chown labapp:labapp /srv/lab-app/index.html
sudo chmod 644 /srv/lab-app/index.html
sudo systemctl enable --now lab-app.service >/dev/null 2>&1
sudo systemctl restart lab-app.service
for i in $(seq 1 10); do curl -sf -o /dev/null http://127.0.0.1:8080/index.html && break; sleep 1; done
curl -sf http://127.0.0.1:8080/index.html > ~/work/final.txt
