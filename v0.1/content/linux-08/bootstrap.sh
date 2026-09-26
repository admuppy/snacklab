#!/bin/bash
# 멱등: 3중 고장 시나리오 배치 — ①잘못된 인터프리터 경로 ②포트 선점 ③파일 권한
set -e
id labapp >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin labapp
sudo mkdir -p /srv/lab-app
if [ ! -f /srv/lab-app/index.html ]; then
  echo '<h1>LAB APP OK</h1><p>congratulations — service restored</p>' | sudo tee /srv/lab-app/index.html >/dev/null
  sudo chown root:root /srv/lab-app/index.html
  sudo chmod 600 /srv/lab-app/index.html
fi
first_run=0
if [ ! -f /etc/systemd/system/lab-squatter.service ]; then
  first_run=1
  sudo tee /etc/systemd/system/lab-squatter.service >/dev/null <<'S'
[Unit]
Description=legacy placeholder (decommission me)
[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0 --directory /tmp
[Install]
WantedBy=multi-user.target
S
fi
if [ ! -f /etc/systemd/system/lab-app.service ]; then
  sudo tee /etc/systemd/system/lab-app.service >/dev/null <<'S'
[Unit]
Description=lab application
[Service]
User=labapp
ExecStart=/usr/bin/python3.99 -m http.server 8080 --bind 0.0.0.0 --directory /srv/lab-app
[Install]
WantedBy=multi-user.target
S
fi
sudo systemctl daemon-reload
if [ "$first_run" = 1 ]; then
  sudo systemctl enable --now lab-squatter.service >/dev/null 2>&1 || true
  # 실패 이력을 journal에 남긴다
  sudo systemctl start lab-app.service >/dev/null 2>&1 || true
fi
mkdir -p ~/work
echo "PASS"
