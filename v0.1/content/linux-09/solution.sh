#!/bin/bash
# linux-09 모범답안 — 3단계 전부 수행 (멱등하게 재실행 가능)
set -e
mkdir -p ~/work

# step1: 자원 스냅샷
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
echo "cpus=$(nproc)" >> ~/work/snapshot.txt

# step2: CPU 0 고정 + nice 19 로 부하 프로세스 (기존 것 정리 후 재기동)
pkill -u "$(id -u)" -f 'stress-ng' 2>/dev/null || true
sleep 1
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
sleep 1

# step3: 메모리 상한 cgroup(lab.slice) 생성 → OOM 유도
# systemd 로 슬라이스에 상한을 건다 → cgroup 이 파드 자신의 컨테이너 스코프 하위에 생기고
# (호스트 cgroup 루트를 건드리지 않음) 파드 종료와 함께 정리된다. k8s 가 파드에 memory.max 를
# 거는 것과 같은 메커니즘이다.
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
# 그 슬라이스 안에서 200MB 할당 → 커널 OOM Killer 발동 (Killed 는 정상)
sudo systemd-run --slice=lab.slice --scope -q \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]" >/dev/null 2>&1 || true

echo "solution applied"
