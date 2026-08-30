#!/bin/bash
# 멱등: 고장난 유닛(lab-report) 배치 — ExecStart 경로 오타로 203/EXEC 실패
set -e
sudo mkdir -p /opt/lab/bin /var/log/lab
sudo tee /opt/lab/bin/lab-report >/dev/null <<'S'
#!/bin/bash
while true; do echo "$(date -Is) report ok" >> /var/log/lab/report.log; sleep 10; done
S
sudo chmod +x /opt/lab/bin/lab-report
sudo tee /etc/systemd/system/lab-report.service >/dev/null <<'S'
[Unit]
Description=lab report daemon
[Service]
ExecStart=/opt/lab/bin/lab-report.sh
[Install]
WantedBy=multi-user.target
S
sudo systemctl daemon-reload
# 실패 이력을 journal에 남긴다 (start는 당연히 실패)
sudo systemctl start lab-report.service >/dev/null 2>&1 || true
mkdir -p ~/work
echo "PASS"
