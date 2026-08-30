#!/bin/bash
# 멱등: 분석 대상 웹 액세스 로그 생성 (2000줄)
set -e
sudo mkdir -p /var/log/lab
if [ ! -s /var/log/lab/access.log ]; then
  sudo bash -c '
    RANDOM=42
    ips=(10.0.0.5 10.0.0.9 172.16.3.7 192.168.14.23 192.168.14.87 203.0.113.50)
    paths=(/index.html /api/users /api/orders /api/health /static/app.js /login)
    methods=(GET GET GET POST PUT)
    codes=(200 200 200 200 301 404 404 500 502 503)
    for i in $(seq 1 2000); do
      ip=${ips[RANDOM % 6]}; p=${paths[RANDOM % 6]}; m=${methods[RANDOM % 5]}; c=${codes[RANDOM % 10]}
      b=$((RANDOM % 5000 + 100))
      printf "%s - - [16/Jul/2026:%02d:%02d:%02d +0900] \"%s %s HTTP/1.1\" %s %s\n" \
        "$ip" $((i/3600%24)) $((i/60%60)) $((i%60)) "$m" "$p" "$c" "$b"
    done > /var/log/lab/access.log
  '
fi
mkdir -p ~/work
echo "PASS"
