# SnackLab 학습자 환경 이미지 (snacklab-linux)
# 세션 = systemd 가 PID 1 로 도는 privileged 컨테이너. 터미널은 포털이 kubectl exec + su - learner
# 로 붙으므로 sshd 는 두지 않는다. 콘텐츠(bootstrap/checks/solution)는 런타임에 주입되고
# 이미지에는 굽지 않는다 — 이 이미지는 순수 "환경"만 제공한다.
#
# 빌드 컨텍스트 = 리포지토리 루트. kaniko: --dockerfile=learner/Dockerfile --context=tar://stdin
#   (./build.sh learner [tag])
#
# 2026-07-31 라이브 linux-lab:v1 을 역추출해 정본화 + CPU/메모리 랩(linux-09)용 도구 추가(v2):
#   stress-ng sysstat  (자원 부하/관찰; cgroup·OOM 은 systemd 로 파드 자신의 슬라이스에서 다룬다).
#   ※ LVM 랩(linux-10)은 노드 전역 자원(loop/LVM)을 건드려 파드 격리와 안 맞아 보류 → 관련 패키지 미포함.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    LANG=C.UTF-8

# ── 패키지 ────────────────────────────────────────────────
# systemd 계열 + 기존 v1 실습 도구(권한/프로세스/텍스트/Bash/사용자/systemd/네트워킹) +
# CPU/메모리 랩(linux-09) 도구: stress-ng·sysstat(자원 부하/관찰).
#
# 경량화(2026-08-02, 574MB → 약 380MB):
#   ① stress-ng 는 GPU 스트레서 때문에 libEGL/libgbm 을 링크하고, 그게 mesa-libgallium(42MB)
#      → libllvm20(140MB) 을 끌고 온다. 우리가 쓰는 --cpu/--vm 스트레서는 GL 드라이버가 필요
#      없으므로 **드라이버 패키지만** 강제 제거한다(NEEDED 인 libEGL.so.1/libgbm.so.1 자체는 유지).
#      제거 후 `stress-ng --cpu 1` · `--vm 1 --vm-bytes 128M` · linux-09 의 taskset+nice 조합까지
#      정상 동작을 실측 확인했다. (--gpu 스트레서만 못 쓴다 — 컨테이너 랩에선 어차피 무의미)
#   ② git(21MB)·locales(16MB)·manpages-dev 는 콘텐츠 어디에서도 쓰지 않아 제외.
#      LANG=C.UTF-8 은 locales 패키지 없이 동작한다. man/manpages 는 실습에 쓰므로 유지.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus \
      sudo bash-completion ca-certificates tzdata \
      acl attr coreutils util-linux procps psmisc lsof strace \
      iproute2 iputils-ping net-tools netcat-openbsd dnsutils socat curl openssh-client \
      python3 rsync cron logrotate \
      grep sed mawk file less tree jq vim nano htop bzip2 unzip \
      man-db manpages \
      e2fsprogs \
      stress-ng sysstat \
 && dpkg --force-depends --purge libllvm20 mesa-libgallium \
 && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/info/*

# ── systemd 컨테이너 대응 ─────────────────────────────────
# privileged 라도 udev/networkd/resolved/커널 마운트 유닛은 컨테이너에서 실패/무의미 →
# 마스킹해 부팅을 깔끔하게(is-system-running=running). v1 이미지의 마스킹 목록과 동일.
RUN systemctl mask \
      systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
      systemd-modules-load.service \
      systemd-networkd.service systemd-resolved.service \
      sys-kernel-config.mount sys-kernel-debug.mount sys-kernel-tracing.mount \
 && systemctl set-default multi-user.target

# ── 학습자 계정 (uid 1000, NOPASSWD sudo) ─────────────────
# Ubuntu 24.04 base 는 uid 1000 에 기본 'ubuntu' 계정을 둔다 → 제거 후 learner 로 재사용.
RUN userdel -r ubuntu 2>/dev/null || true; \
    useradd -m -s /bin/bash -u 1000 learner \
 && install -m 0440 /dev/null /etc/sudoers.d/90-learner \
 && echo 'learner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-learner

# systemd 가 SIGRTMIN+3(=정상 종료) 를 받도록
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/lib/systemd/systemd"]
