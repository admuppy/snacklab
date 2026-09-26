#!/bin/bash
# 멱등: 127.0.0.1에만 바인딩된 API 서비스 배치 (3단계 수리 대상)
set -e
sudo mkdir -p /srv/lab-api
[ -f /srv/lab-api/status.json ] || echo '{"service":"lab-api","status":"ok"}' | sudo tee /srv/lab-api/status.json >/dev/null
if [ ! -f /etc/systemd/system/lab-api.service ]; then
  sudo tee /etc/systemd/system/lab-api.service >/dev/null <<'S'
[Unit]
Description=lab api
[Service]
ExecStart=/usr/bin/python3 -m http.server 9090 --bind 127.0.0.1 --directory /srv/lab-api
Restart=on-failure
[Install]
WantedBy=multi-user.target
S
  sudo systemctl daemon-reload
fi
sudo systemctl enable --now lab-api.service >/dev/null 2>&1 || true
mkdir -p ~/work
echo "PASS"
