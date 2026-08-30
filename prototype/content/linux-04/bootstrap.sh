#!/bin/bash
# 멱등: 수리 대상 스크립트 + 샘플 로그 배치
set -e
sudo mkdir -p /opt/lab/bin /opt/lab/data
sudo tee /opt/lab/bin/backup.sh >/dev/null <<'S'
#!/bin/bash
# 지정한 디렉터리를 /tmp 아래로 백업한다 — 그런데 버그가 있다
src=$1
dest=/tmp/backup-$(date +%s%N)
mkdir -p $dest
cp -r $src/* $dest/
echo "backup of $src complete: $dest"
S
sudo chmod +x /opt/lab/bin/backup.sh
if [ ! -s /opt/lab/data/app.log ]; then
  sudo bash -c '
    RANDOM=7
    for i in $(seq 1 300); do
      c=$((RANDOM % 10)); [ $c -lt 7 ] && s=200 || { [ $c -lt 9 ] && s=404 || s=500; }
      echo "2026-07-16T10:$((i/60%60)):$((i%60)) status=$s msg=request-$i"
    done > /opt/lab/data/app.log
  '
fi
mkdir -p ~/work
echo "PASS"
