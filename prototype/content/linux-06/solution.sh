#!/bin/bash
set -e
mkdir -p ~/work
# step1: hello-web
sudo tee /etc/systemd/system/hello-web.service >/dev/null <<'S'
[Unit]
Description=hello web
[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 127.0.0.1
Restart=on-failure
RestartSec=1
[Install]
WantedBy=multi-user.target
S
sudo systemctl daemon-reload
sudo systemctl enable --now hello-web.service >/dev/null 2>&1
# step2: lab-report ExecStart 경로 수리
sudo sed -i 's|^ExecStart=/opt/lab/bin/lab-report.sh|ExecStart=/opt/lab/bin/lab-report|' /etc/systemd/system/lab-report.service
sudo systemctl daemon-reload
sudo systemctl start lab-report.service
# step4: 타이머
sudo tee /etc/systemd/system/lab-tick.service >/dev/null <<'S'
[Unit]
Description=lab tick
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
S
sudo tee /etc/systemd/system/lab-tick.timer >/dev/null <<'S'
[Unit]
Description=lab tick every minute
[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s
[Install]
WantedBy=timers.target
S
sudo systemctl daemon-reload
sudo systemctl enable --now lab-tick.timer >/dev/null 2>&1
# 서비스 기동 대기
for i in $(seq 1 10); do curl -sf -o /dev/null http://127.0.0.1:8080/ && break; sleep 1; done
