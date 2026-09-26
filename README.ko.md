# SnackLab

**브라우저 하나로 끝나는 셀프호스팅 실습 랩 포털** — 일회용 실환경, 자동 채점, 모의고사.

*[English README](README.md)*

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Node](https://img.shields.io/badge/node-%E2%89%A518-brightgreen)
![Kubernetes](https://img.shields.io/badge/kubernetes-v1.27%2B-326CE5)
![Modules](https://img.shields.io/badge/modules-24-orange)
![i18n](https://img.shields.io/badge/i18n-7_locales-purple)

학습자마다 **격리된 일회용 환경**을 즉석에서 만들어 준다 — systemd가 도는 privileged 파드에,
트랙에 따라 그 안에 단일노드 k3s 클러스터나 올인원 OpenStack까지 통째로.
Isovalent Labs / Killercoda 류의 셀프호스팅 대안.

이런 곳에 잘 맞는다:

- 사내 기술역량 증진·학습 성취도 평가 도구 도입을 고민하는 **인사·교육(HR/L&D) 담당자** —
  스텝별 자동 채점과 시험 점수가 학습자별 객관적 결과 데이터로 바로 쌓인다
- **신규 팀 합류자 온보딩** — Linux·Kubernetes·OpenStack 기초를 스스로 따라가는
  학습 경로, 워크스테이션 세팅 불필요
- CKA / CKAD / CKS 를 준비하는 **자격증 스터디** — 실전 같은 시간제 모의고사
- 셀프호스팅·폐쇄망 랩이 필요한 **플랫폼/인프라 팀** — 조직 전체가 공유하는 실습 환경

## 🚀 60초 체험

클러스터 없이도 된다 — `sim` 드라이버가 세션을 흉내내므로 UI 전체를 바로 둘러볼 수 있다:

```bash
git clone https://github.com/admuppy/snacklab && cd snacklab/v0.1
npm ci
DRIVER=sim node server.js
# http://localhost:3000
```

Node.js 18 이상 필요. 런타임 의존성은 express·ws 뿐이다.

## 왜 SnackLab인가?

- 🧑‍💻 **학습자 설치 제로** — 가이드·터미널·채점 전부 브라우저에서.
- ⚙️ **시뮬레이션이 아닌 진짜 환경** — 리눅스 트랙은 systemd PID1 파드, 쿠버네티스 트랙은
  파드 안에서 도는 진짜 단일노드 k3s, OpenStack 트랙은 진짜 컨트롤플레인.
- ✅ **자동 채점** — 스텝별 체크 스크립트 + 로케일별 메시지. 시험 모드는 부분점수·일괄 채점.
- 📝 **실전 같은 모의고사** — CKA/CKAD/CKS 각 120분, 실제 시험 도메인 배점·합격 뱃지·문항별
  해설, 실제 시험 제공 언어(en·ja·zh-CN)로 강제하는 "시험 언어" 팝업까지.
- 🌏 **i18n 우선** — UI 7개 로케일(ko·en·ja·zh-CN·zh-TW·es·de), 가이드·채점 메시지 다국어
  + 합리적 폴백.
- ⚡ **웜풀** — 세션 즉시 시작용 파드 미리 준비, admin 대시보드에서 실시간 조절.
- 🔌 **폐쇄망 친화** — 학습자 이미지는 오프라인 부팅, `imageRegistry` 값 하나로 사설
  레지스트리 전환.
- 📦 **배포 방식 2가지** — 쿠버네티스 Helm 차트, 또는 쿠버네티스 없이 싱글 호스트
  [Docker Compose 스택](compose/).

## 트랙

| 트랙 | 모듈 | 환경 |
|---|---|---|
| Linux 중급 | linux-01 ~ 09 (권한·프로세스·텍스트·Bash·계정·systemd·네트워킹·종합·자원관리) | systemd PID1 파드 |
| Kubernetes 심화 | k8s-01 ~ 10 (워크로드·서비스·구성·프로브·리소스·스케줄링·스토리지·RBAC·NetworkPolicy·트러블슈팅) | 파드 안 단일노드 k3s |
| CKA / CKAD / CKS 모의고사 | cka-01 · ckad-01 · cks-01 (각 120분, 15~16문항) | 파드 안 단일노드 k3s |
| OpenStack 입문 | openstack-01 ~ 02 (서비스 카탈로그·네트워크·인스턴스 라이프사이클·프로젝트, qcow2 이미지 제작·업로드) | 파드 안 올인원 OpenStack(Caracal), nova fake 드라이버 |

OpenStack 트랙은 keystone·glance·neutron·nova를 **fake virt 드라이버**로 돌린다:
인스턴스가 실제 VM 없이 상태 머신으로만 "부팅"되므로 클라우드 전체가 유휴 ~0.05 CPU /
2.8 GiB 로 돌면서도, API·CLI 흐름은 실제 OpenStack과 동일하다.

## 아키텍처

```
┌────────────────┐  HTTPS / WebSocket  ┌────────────────────────────────┐
│    브라우저     │◄───────────────────►│   포털 (Node.js 단일           │
│ 가이드·터미널   │                     │   server.js)                   │
│ 카탈로그·관리자 │                     │ 인증(local/OIDC) · i18n ·      │
└────────────────┘                     │ 채점 · 시험모드 · 웜풀          │
                                       └───────────┬────────────────────┘
                        코스 번들                   │ 세션 드라이버
                 (콘텐츠 이미지 → /courses)         │ sim | pod | docker
                                                   │
                 ┌─────────────────────────────────┼─────────────────────┐
                 ▼                                 ▼                     ▼
        ┌────────────────┐              ┌────────────────────┐ ┌──────────────────┐
        │  Linux 트랙    │              │  K8s·시험 트랙      │ │ OpenStack 트랙   │
        │ systemd PID1   │              │ 파드 안            │ │ 올인원 클라우드   │
        │ 파드           │              │ 단일노드 k3s       │ │ (fake 드라이버)  │
        └────────────────┘              └────────────────────┘ └──────────────────┘
                  학습자 세션 = 일회용 privileged 파드 1개
        (터미널·체크는 전부 `kubectl exec` 경유 — sshd·ingress 없음)
```

- **드라이버**: `pod`(쿠버네티스 학습자 파드), `docker`(docker 소켓으로 privileged 형제
  컨테이너), `sim`(백엔드 없음 — UI 개발용).
- **콘텐츠**: 코스 번들(`course.json` + modules)은 작은 콘텐츠 이미지로 배포되고
  initContainer가 포털 `/courses` 볼륨에 복사한다 — 콘텐츠 갱신에 포털·학습자 이미지
  리빌드가 필요 없다.

## 구조

```
v0.1/           앱 — 포털 전체가 단일 server.js (express + ws)
  userctl.js         로컬 계정 CLI
  public/            정적 UI (카탈로그/랩/관리자, i18n.js)
  content/           내장 콘텐츠 (linux-01~09)
courses/             코스 번들 (k8s·cka·cks·ckad·openstack) — course.json + modules/, 콘텐츠 이미지로 주입
k8s-lab/             k3s 내장 학습자 환경 이미지 (에어갭 슬림화 필터 포함)
openstack-lab/       올인원 OpenStack 내장 학습자 환경 이미지 (fake 드라이버)
learner/             리눅스 트랙 학습자 환경 이미지
portal/              포털 이미지 Dockerfile
chart/               Helm 차트 (values.yaml=기본값, values-example.yaml=운영 예시)
compose/             싱글 호스트 Docker Compose 배포 (docker 드라이버, 쿠버네티스 불필요)
deploy/              학습자 파드 템플릿, 코스 E2E 검증 스크립트
build.sh / deploy.sh 클러스터 내 kaniko 빌드·helm 배포
```

## 쿠버네티스 설치

### 요구 사항

| | 최소 | 비고 |
|---|---|---|
| Kubernetes | v1.27+ | CNCF 표준 배포판 아무거나 (k3s, kubeadm, RKE2, EKS, ...) |
| 아키텍처 | amd64 | 학습자 이미지는 현재 amd64 빌드 |
| Privileged pod | 필수 | 학습자 파드가 systemd(및 k3s·OpenStack)를 PID1 로 돌린다 |
| CNI | NetworkPolicy 를 강제하는 CNI(Calico, Cilium) 강력 권장 | 차트에 학습자 격리 NetworkPolicy 포함 — 미강제 CNI(순정 flannel 등)에선 무효 |
| StorageClass | 선택 | 진도/뱃지 영속화용. 동적 프로비저너 아무거나 (local-path, Longhorn, NFS, Ceph, ...) |
| 레지스트리 | 아무거나 | 클러스터가 pull 가능하면 됨 (아래 `imageRegistry` 참고) |

### 권장 스펙

포털 자체는 가볍다(요청 100m CPU / 256Mi). 용량 산정 기준은 **동시 학습 세션 수**다:

| 세션 종류 | requests | limits | 정상 상태 실측 |
|---|---|---|---|
| 리눅스 트랙 파드 | 250m CPU / 1Gi / 임시디스크 2Gi | 2 CPU / 4Gi / 8Gi | 가벼움 |
| 파드 안 k3s (k8s·시험 트랙) | 500m / 1Gi | 2 CPU / 4Gi | ~1 CPU, 1.5~2.5 GiB |
| 올인원 OpenStack 파드 | 500m / 2Gi | 2 CPU / 6Gi | 유휴 ~0.05 CPU, 2.8 GiB |

경험칙:

- **평가/소규모**: 노드 1대 4 vCPU / 8 GiB → k3s·OpenStack 세션 2~3개 동시.
- **강의실(동시 ~10명)**: 노드 합산 16 vCPU / 32 GiB.
- 임시 디스크는 시험 세션당 ~1 GiB 잡을 것(실측: CKA 완주 시 756 MiB 기록), 파드당 상한 8 Gi.
- 세션 부팅: 노드에 이미지가 캐시된 뒤에는 k3s·OpenStack 파드가 10~40초에 부트스트랩된다.
  노드별 최초 pull은 수 분(이미지 1~3 GiB) — 웜풀이 양쪽 다 가려 준다.
- 랩 네임스페이스용 ResourceQuota·LimitRange 가 차트에 포함되어 기본 활성화되어 있다.

### 설치

```bash
helm upgrade --install lab ./chart -n snacklab --create-namespace \
  --set auth.adminPassword='<초기 관리자 비밀번호>' \
  -f chart/values-example.yaml   # 사이트에 맞게 복사·수정 후 사용
```

`auth.mode: local`이면 포털이 첫 기동 때 관리자 계정을 만듭니다: 계정 `adminUsers[0]`
(기본 `admin`), 비밀번호 `auth.adminPassword`(기본값 **`ChangeMe`** — 로그인 후 바로 바꾸세요).
계정은 sessions 볼륨의 `users.json`에 기록되며 이 파일이 아직 없을 때만 생성되므로, 이후
`adminPassword`를 바꿔도 반영되지 않습니다 — 계정은 관리자 대시보드(`/admin.html`)에서 관리하세요.

선택 Secret:

- `auth.usersExistingSecret` — 자동 생성 관리자 대신 Secret으로 `users.json` 시드
  (키 `users.json`, `node v0.1/userctl.js add <계정> --admin`으로 생성). 역시 첫 기동 때만 복사됩니다.
- `auth.cookieSecretExistingSecret` — 쿠키 서명 키(키 `cookieSecret`). 지정하면 포털 재시작 후에도
  로그인이 유지되고, 없으면 파드마다 임의 키를 생성합니다.

```bash
kubectl -n snacklab create secret generic lab-cookie \
  --from-literal=cookieSecret=$(openssl rand -hex 32)
```

존재하지 않는 Secret을 지정하면 포털 pod가
`MountVolume.SetUp failed for volume "users" : secret "lab-users" not found`(쿠키 Secret이면
`CreateContainerConfigError`)로 실패합니다 — Secret을 만든 뒤
`kubectl -n snacklab rollout restart deploy/lab-snacklab`로 재시작하세요.

로그인 없이 먼저 띄워 보려면 `--set auth.mode=off`(내부망 데모 전용).

주요 값 (전체는 `chart/values.yaml` 참고):

- `imageRegistry` — 코스/학습자 이미지 레지스트리 프리픽스. 폐쇄망이면 자기 레지스트리로.
- `driver` — `pod`(실제 세션) 또는 `sim`(클러스터 불필요).
- `auth.mode` — `auto` | `off` | `local` | `oidc`.
- `courses` — 마운트할 콘텐츠 이미지 (k8s / cka / cks / ckad / openstack, 또는 자체 코스).
- `persistence.*` — 진도/뱃지 저장. `storageClass: ''` 는 클러스터 기본, NFS 계열
  (RWX 전용) 프로비저너는 `accessModes` 재정의 가능.
- `warmPool.*` — 웜풀 크기·동작.
- `session.*` — TTL·유휴 타임아웃·사용자당/전체 세션 상한.

### 이미지 빌드

빌드는 클러스터 안 kaniko 로 돈다 (docker 데몬 불필요):

```bash
export REGISTRY=registry.example.com/snacklab   # 또는 ./build.env 에
./build.sh v1.x                # 포털 이미지
./build.sh learner v2          # 리눅스 학습자 환경
./build.sh k8s-lab v1          # k3s 학습자 환경
./build.sh openstack-lab v1    # OpenStack 학습자 환경
./build.sh k8s-course v1       # 코스 콘텐츠 이미지 (cka/cks/ckad/openstack-course 동일)
./deploy.sh v1.x               # chart/values-live.yaml 로 helm upgrade
```

### 콘텐츠 검증

실제 학습자 파드로 하는 E2E 가 기본이다
(bootstrap → pre-check 전부 FAIL 확인 → solution → post-check 전부 PASS):

```bash
./deploy/e2e-course.sh courses/k8s
./deploy/e2e-course.sh courses/openstack
./deploy/e2e-course.sh courses/cka cka-01
```

## Docker Compose (싱글 호스트, 쿠버네티스 불필요)

포털을 일반 컨테이너로 띄우고, docker 소켓을 통해 학습자 세션을 privileged 형제
컨테이너로 만드는 방식도 지원한다 — 학습자 이미지·콘텐츠는 동일, 클러스터는 불필요:

```bash
cd compose
./build-images.sh
docker compose up -d --build
# http://localhost:3000
```

격리 수준은 쿠버네티스 배포보다 약하다(신뢰 경계가 호스트 전체) —
사이징·인증 설정 포함 상세는 [compose/README.md](compose/README.md) 참고.

## 무엇과 다른가

| | SnackLab | 호스팅형 플레이그라운드 (Killercoda, Instruqt, ...) | 로컬 VM / kind |
|---|---|---|---|
| 셀프호스팅 / 폐쇄망 | ✅ | ❌ | ✅ |
| 학습자 준비 제로 (브라우저만) | ✅ | ✅ | ❌ |
| 자체 콘텐츠 + 자동 채점 | ✅ | 제한적 / 유료 티어 | 수동 |
| 시험 모드 (배점·부분점수·뱃지) | ✅ | ❌ | ❌ |
| 학습자별 격리된 k8s / OpenStack | ✅ | ✅ | 머신당 1개 |
| 비용 | 내 하드웨어 | 구독 | 내 하드웨어 |

## 보안 모델

학습자 파드는 **privileged**(systemd·k3s 요구)다. 신뢰 경계는 "같은 클러스터 공유"이며,
작정한 사용자는 원리적으로 노드 자격증명에 접근할 수 있다. 완전 신뢰 집단이 아니라면:

- 차트에 포함된 학습자 NetworkPolicy(ingress 전면 차단, egress 는 DNS·공인 80/443 만,
  RFC1918/링크로컬 차단)를 켜고 **강제하는 CNI** 위에서 운영할 것;
- 학습자 파드 전용 노드풀 + taint 검토;
- 노드·파드·서비스 CIDR 이 `learner.networkPolicy.blockedCidrs` 안에 드는지 확인.

상세는 `chart/values.yaml` 과 `chart/templates/networkpolicy-learner.yaml` 주석 참고.

## 콘텐츠 작성

모듈 = `meta.json + guide.md(+로케일) + bootstrap.sh + checks/*.sh + solution.sh`
(+시험형은 `explain.md`). 채점 스크립트는 키만 출력하고 포털이 `checks/messages.json` 으로
로케일 렌더링한다. 규칙 전체:
[docs/content-authoring-conventions.md](docs/content-authoring-conventions.md).

## 기여

[CONTRIBUTING.md](CONTRIBUTING.md) 참고. 이슈·PR 환영 — 특히 콘텐츠(새 모듈/트랙, 번역)
기여를 환영한다.

## 라이선스

[Apache License 2.0](LICENSE)
