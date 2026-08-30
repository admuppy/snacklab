# SnackLab — Kubernetes 심화 과정 학습자 환경 이미지
# (snacklab-k8s)
#
# 리눅스 트랙(linux-lab)과 같은 "systemd PID1 privileged pod" 골격에 **파드 안 단일노드 k3s** 를
# 얹었다. 학습자마다 세션 = 격리된 자기 전용 클러스터. 세션 종료 = 파드째 폐기 = 완전 초기화.
# 터미널/체크는 포털이 `kubectl exec ... su - learner -c 'bash -s'` 로 붙으므로 sshd 없음.
# 콘텐츠(course.json/modules)는 이미지에 굽지 않고 포털 쪽 /courses 로 주입한다 — 이 이미지는
# 순수 "환경"만 제공.
#
# 빌드 컨텍스트 = 리포지토리 루트 (build.sh k8s-lab [tag]).
#   에어갭 기동: k3s 바이너리 + airgap 이미지 tar 를 이미지에 구워, 런타임에 인터넷 없이 부팅.
# ── 0단계: 에어갭 이미지 tar 슬림화 (빌더) ────────────────
# k3s 공식 airgap tar 는 544MB 지만 traefik·klipper-helm·klipper-lb·metrics-server 는
# k3s.service 에서 --disable 로 끄므로 절대 쓰이지 않는다. 실제 필요한 pause·coredns·
# local-path-provisioner 만 남기면 118MB. (자세한 내용은 filter-airgap.py)
FROM ubuntu:24.04 AS airgap
ARG K3S_VERSION=v1.36.2+k3s1
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates python3 \
 && rm -rf /var/lib/apt/lists/*
COPY k8s-lab/filter-airgap.py /tmp/filter-airgap.py
RUN curl -fsSL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar" \
      -o /tmp/full.tar \
 && python3 /tmp/filter-airgap.py /tmp/full.tar /tmp/k3s-airgap-images-amd64.tar \
      rancher/mirrored-pause rancher/mirrored-coredns-coredns rancher/local-path-provisioner \
 && rm -f /tmp/full.tar \
 && ls -l /tmp/k3s-airgap-images-amd64.tar
# CKA Q16 (etcd backup/restore) and Q17 (multi-node drain) tooling, fetched here so the
# final image needs no internet: etcdctl/etcdutl (the real exam's client binaries) and
# kwok (fake kubelet-less worker nodes; measured 57MiB RSS on 2026-08-06).
ARG ETCD_VERSION=v3.5.16
ARG KWOK_VERSION=v0.8.0
RUN curl -fsSL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz" \
      -o /tmp/etcd.tar.gz \
 && tar xzf /tmp/etcd.tar.gz -C /tmp --strip-components=1 \
      "etcd-${ETCD_VERSION}-linux-amd64/etcdctl" "etcd-${ETCD_VERSION}-linux-amd64/etcdutl" \
 && rm -f /tmp/etcd.tar.gz \
 && curl -fsSL "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/kwok-linux-amd64" \
      -o /tmp/kwok \
 && curl -fsSL "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_VERSION}/stage-fast.yaml" \
      -o /tmp/kwok-stages.yaml \
 && chmod +x /tmp/etcdctl /tmp/etcdutl /tmp/kwok

# ── 1단계: 실제 학습자 환경 이미지 ────────────────────────
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    LANG=C.UTF-8

# k3s 버전 고정 — 재현성. (갱신 시 airgap 이미지 tar URL 도 같은 버전으로.)
ARG K3S_VERSION=v1.36.2+k3s1
ARG K3S_TAG=v1.36.2-k3s1

# ── 패키지 ────────────────────────────────────────────────
# systemd 계열 + k8s 실습 도구(kubectl 은 k3s 가 심볼릭). k3s 는 자체 containerd 를 쓰므로
# 별도 런타임 불필요.
#   socat  : kubectl port-forward 가 필요로 한다
#   conntrack: kube-proxy 필수
#   kmod   : k3s 유닛의 modprobe(br_netfilter·overlay) — 호스트 /lib/modules 마운트와 짝
#   fuse-overlayfs/fuse3: 파드 안 containerd 스냅샷터
# 경량화(2026-08-02): vim(41MB 런타임) → vim-tiny, python3(27MB)·git(11MB)·man-db(perl 21MB)·
#   locales(16MB)·tree 제외 — 코스 콘텐츠 어디에서도 쓰지 않고, LANG=C.UTF-8 은 locales 없이
#   동작한다. 편집기는 nano + vi(vim-tiny) 로 충분.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus \
      sudo bash-completion ca-certificates tzdata \
      coreutils util-linux procps psmisc lsof \
      iproute2 iputils-ping net-tools curl socat conntrack ethtool kmod \
      fuse-overlayfs fuse3 \
      jq vim-tiny nano less \
 && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/info/*

# ── k3s 바이너리 + 에어갭 이미지 (오프라인 부팅) ──────────
# get.k3s.io 설치 스크립트는 쓰지 않는다 — 그 스크립트는 마지막에 `systemctl daemon-reload`를
# 호출하는데, kaniko 빌드 환경엔 systemd 버스가 없어("Failed to connect to bus") 실패한다.
# 대신 바이너리·심볼릭·유닛·enable(멀티유저 wants 심볼릭)을 오프라인 파일 조작으로 직접 배치한다.
#   --write-kubeconfig-mode 0644 : learner 계정이 kubeconfig 를 읽도록.
#   --disable traefik/servicelb/metrics-server/cloud-controller : 소형 단일노드 부담↓
#     (k3s.service 의 ExecStart 에 기술) — 그래서 에어갭 tar 도 그만큼 슬림화한다(0단계).
#   local-path(PV)·network-policy(kube-router)·coredns 는 유지 — 스토리지·NetworkPolicy 실습에 사용.
RUN curl -fsSL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s" \
      -o /usr/local/bin/k3s \
 && chmod +x /usr/local/bin/k3s \
 && ln -sf k3s /usr/local/bin/kubectl \
 && ln -sf k3s /usr/local/bin/crictl \
 && ln -sf k3s /usr/local/bin/ctr \
 && mkdir -p /var/lib/rancher/k3s/agent/images
# 0단계에서 걸러낸 슬림 tar 만 반입(544MB → 118MB). k3s 가 기동 시 containerd 로 자동 import 한다.
COPY --from=airgap /tmp/k3s-airgap-images-amd64.tar /var/lib/rancher/k3s/agent/images/

# k3s.service 유닛 배치 + enable (오프라인: 버스 없이 wants 심볼릭만 생성)
COPY k8s-lab/k3s.service /etc/systemd/system/k3s.service
RUN : > /etc/systemd/system/k3s.service.env \
 && ln -sf /etc/systemd/system/k3s.service \
      /etc/systemd/system/multi-user.target.wants/k3s.service

# ── exam tooling: etcdctl/etcdutl + kwok ──────────────────
# etcdctl/etcdutl: CKA Q16 uses the real exam workflow against k3s embedded etcd
# (enabled per-course via K3S_CLUSTER_INIT, see lab-init). kwok: fake worker nodes for
# the multi-node drain question — installed but *disabled*; a course bootstrap opts in
# with `sudo systemctl enable --now kwok`.
COPY --from=airgap /tmp/etcdctl /tmp/etcdutl /tmp/kwok /usr/local/bin/
COPY --from=airgap /tmp/kwok-stages.yaml /etc/kwok/stage-fast.yaml
COPY k8s-lab/kwok.service /etc/systemd/system/kwok.service

# ── 학습에 쓸 컨테이너 이미지 목록(반입용 참고) ───────────
# 랩에서 학습자가 배포하는 nginx·busybox 는 첫 파드 스케줄 시 pull 된다(이미지에 굽지 않는다 —
# 구우면 파드 이미지가 수백 MB 커지고, 대부분의 학습자는 일부만 쓴다).
COPY k8s-lab/preload-images.txt /tmp/preload-images.txt
# 이미지 preload 는 빌드 시점 인터넷으로 pull → tar 저장이 이상적이나, kaniko 컨텍스트엔 도커가
# 없다. 대신 런타임 최초 부팅 시 k3s 가 필요한 이미지를 pull 하도록 두고(하버/인터넷 가용 전제),
# 목록은 문서·프리풀 유닛에서 참조한다. (에어갭 강제 시 이 파일 기준으로 tar 를 별도 반입할 것.)

# ── systemd 컨테이너 대응 + k3s 유닛 정리 ────────────────
RUN systemctl mask \
      systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
      systemd-modules-load.service \
      systemd-networkd.service systemd-resolved.service \
      sys-kernel-config.mount sys-kernel-debug.mount sys-kernel-tracing.mount \
 && systemctl set-default multi-user.target

# ── 학습자 계정 (uid 1000, NOPASSWD sudo) + kubectl 편의 ──
RUN userdel -r ubuntu 2>/dev/null || true; \
    useradd -m -s /bin/bash -u 1000 learner \
 && install -m 0440 /dev/null /etc/sudoers.d/90-learner \
 && echo 'learner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-learner
# KUBECONFIG 을 로그인 셸 전역에 — 터미널과 체크(su - learner -c 'bash -s') 양쪽에 적용.
# k 별칭 + kubectl 자동완성 + 기본 네임스페이스 default.
RUN printf '%s\n' \
      'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' \
      'export PATH=$PATH:/usr/local/bin' \
      'alias k=kubectl' \
      'source <(kubectl completion bash 2>/dev/null) || true' \
      'complete -o default -F __start_kubectl k 2>/dev/null || true' \
      > /etc/profile.d/k3s.sh \
 && chmod 0644 /etc/profile.d/k3s.sh

# ── 엔트리포인트: systemd 기동 전에 cgroup 네임스페이스 격리 ──
# privileged 파드는 호스트 cgroup ns 를 물려받아, 내부 kubelet 이 바깥 클러스터의 kubepods.slice 를
# 고아 cgroup 으로 오인해 몰살시킨다(상세: entrypoint.sh 주석). 그래서 systemd 앞에 unshare 를 둔다.
COPY k8s-lab/entrypoint.sh /usr/local/bin/lab-init
RUN chmod 0755 /usr/local/bin/lab-init

STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/local/bin/lab-init"]
