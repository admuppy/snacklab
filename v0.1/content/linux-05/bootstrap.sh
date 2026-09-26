#!/bin/bash
# 멱등: 퇴사자 계정(잠금 대상) 준비
set -e
id olduser >/dev/null 2>&1 || sudo useradd -m -s /bin/bash olduser
echo 'olduser:LegacyPass123' | sudo chpasswd
sudo usermod -U olduser 2>/dev/null || true
mkdir -p ~/work
echo "PASS"
