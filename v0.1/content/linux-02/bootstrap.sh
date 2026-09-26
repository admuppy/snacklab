#!/bin/bash
# 멱등: 실습용 프로세스 3종 설치·기동 (systemd 유닛으로 관리해 세션 내내 유지)
set -e
sudo mkdir -p /opt/lab/bin
sudo tee /opt/lab/bin/lab-worker >/dev/null <<'S'
#!/bin/bash
while true; do sleep 5; done
S
sudo tee /opt/lab/bin/lab-stubborn >/dev/null <<'S'
#!/bin/bash
trap '' TERM INT
while true; do sleep 5; done
S
sudo tee /opt/lab/bin/lab-batch >/dev/null <<'S'
#!/bin/bash
while true; do date >> "${1:-/dev/null}"; sleep 10; done
S
sudo chmod +x /opt/lab/bin/lab-*
for u in lab-worker lab-stubborn; do
  sudo tee /etc/systemd/system/$u.service >/dev/null <<S
[Unit]
Description=$u
[Service]
ExecStart=/opt/lab/bin/$u
[Install]
WantedBy=multi-user.target
S
done
sudo tee /etc/systemd/system/lab-listener.service >/dev/null <<'S'
[Unit]
Description=lab-listener
[Service]
ExecStart=/usr/bin/python3 -m http.server 5555 --bind 127.0.0.1
[Install]
WantedBy=multi-user.target
S
sudo systemctl daemon-reload
sudo systemctl enable --now lab-worker lab-stubborn lab-listener >/dev/null 2>&1
mkdir -p ~/work
echo "PASS"
