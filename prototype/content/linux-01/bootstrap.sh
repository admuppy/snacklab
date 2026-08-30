#!/bin/bash
# 멱등: audit 계정 + 감사 대상 파일 배치
set -e
id audit >/dev/null 2>&1 || sudo useradd -m -s /bin/bash audit
sudo mkdir -p /opt/lab/perm
echo "db_password=changeme" | sudo tee /opt/lab/perm/danger.conf >/dev/null
sudo chmod 666 /opt/lab/perm/danger.conf
sudo touch /opt/lab/perm/app.log /opt/lab/perm/readme.txt
sudo chmod 644 /opt/lab/perm/app.log /opt/lab/perm/readme.txt
mkdir -p ~/work
echo "PASS"
