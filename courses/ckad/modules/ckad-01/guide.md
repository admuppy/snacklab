# CKAD 모의고사 1회 (120분 · 16문항 · 100점)

Linux Foundation **CKAD(Certified Kubernetes Application Developer)** 실기 시험 형식을 옮긴
모의고사다. 문제는 시험과 같은 도메인 배점으로 배분했다.

| 도메인 | 배점 | 문항 |
|---|---|---|
| 애플리케이션 설계·빌드 | 20 | Q1 Q2 Q3 |
| 애플리케이션 배포 | 20 | Q4 Q5 Q6 |
| 관찰가능성·유지보수 | 15 | Q7 Q8 Q9 |
| 환경·구성·보안 | 25 | Q10 Q11 Q12 Q13 |
| 서비스·네트워킹 | 20 | Q14 Q15 Q16 |

**진행 방식**

- 제한 시간 **120분**. 남은 시간은 화면 상단에 표시된다.
- 문항은 **순서와 무관하게** 풀어도 된다. 자신 있는 것부터 처리하는 것이 실제 시험 전략이다.
- 실제 시험처럼 **푸는 중에는 채점 결과가 없다**. 다 풀고 아래 **[제출하고 채점하기]** 를 한 번 누르면
  16문항이 한꺼번에 채점된다(문항마다 실제 클러스터를 확인하므로 1~2분 걸린다).
- **부분 점수가 있다.** 문항마다 채점 항목이 여러 개고 맞힌 항목만큼 점수가 붙는다.
  채점이 끝나면 화면 위쪽에 총점과 문항별 점수·채점 항목이 뜨고, **아래쪽에 틀린 문항 해설**이 붙는다.
- **합격선은 66점**이다. 넘기면 축하 메시지와 함께 모듈 이수 뱃지를 받는다(만점이 아니어도 된다).
- 제출 후에도 남은 시간 안에서 계속 고쳐 **다시 채점**할 수 있다. 최고 점수가 기록된다.
- 네임스페이스를 문제가 지정한 경우 **반드시 그 네임스페이스에** 만들어야 한다.

**시험 언어**

실제 CKAD 시험은 **영어·일본어·중국어(간체)** 로만 제공된다(한국어판은 없다). 이 모의고사도 그 세
언어와 한국어를 지원하니, 시험장에서 읽게 될 문장에 익숙해지고 싶다면 상단 언어 선택에서
**English / 日本語 / 简体中文** 으로 바꿔 한 번 더 풀어 보는 것을 권한다.

**환경**

파드 안에서 도는 **단일노드 k3s v1.36** 클러스터이며 당신 전용이다. `kubectl`(`k` 별칭)과
`KUBECONFIG` 은 이미 설정돼 있고, `sudo` 는 비밀번호 없이 쓸 수 있다. `jq` 와 `vi`/`nano` 가
있다. 시험처럼 [쿠버네티스 공식 문서](https://kubernetes.io/docs/) 를 봐도 된다 — 오히려 문서에서
YAML 예시를 찾아 고쳐 쓰는 것이 시험의 정석이다.

```bash
kubectl get nodes
kubectl get ns          # dev, prod, batch, broken 이 준비돼 있다
```

**실제 시험과 다른 점** (환경 제약상 불가피한 부분)

- **Helm 문제는 넣지 않았다**(환경에 helm 바이너리가 없다). Kustomize 는 `kubectl apply -k` 로 출제했다.
- Ingress 컨트롤러가 없어 **Q15 는 리소스 작성까지만** 채점한다(실제 라우팅 확인 없음).
- 컨테이너 이미지 빌드(Dockerfile 작성·docker build)는 별도 학습이 필요하다.

> 시간 절약 요령: `kubectl create ... --dry-run=client -o yaml > q.yaml` 로 뼈대를 만든 뒤
> 편집하는 습관이 시험에서 가장 크게 유리하다. `kubectl explain <리소스>.<필드>` 도 즉시 쓸 수 있다.

## 1. Q1 (7점) 사이드카 컨테이너 — 로그 스트리밍

네임스페이스 `dev` 에 파드 `logger` 를 만들어라. 컨테이너 두 개가 **emptyDir 볼륨 `logs`** 를 공유한다.

- 메인 컨테이너 `app` — 이미지 `busybox:1.36`, 명령:
  `sh -c "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"`
  볼륨을 `/var/log/app` 에 마운트.
- 사이드카 컨테이너 `streamer` — 이미지 `busybox:1.36`, 명령:
  `sh -c "tail -F /var/log/app/app.log"` 볼륨을 같은 경로에 마운트.

채점: 파드 구성(컨테이너 2개·공유 emptyDir)과 함께 **`kubectl logs logger -c streamer` 에
`tick` 줄이 실제로 나오는지** 를 본다.

> 참고: [파드에서 사이드카 컨테이너 사용](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

## 2. Q2 (7점) Job 과 CronJob

네임스페이스 `batch` 에서:

1. Job `pi` — 이미지 `busybox:1.36`, 명령 `sh -c "echo 3.14159"`,
   **completions 3 · parallelism 2**, `restartPolicy: Never`. 세 번 모두 성공해야 한다.
2. CronJob `cleanup` — 이미지 `busybox:1.36`, 명령 `sh -c "echo cleaned"`,
   스케줄 **매일 03:00** (`0 3 * * *`), **concurrencyPolicy Forbid**,
   **successfulJobsHistoryLimit 1**, `restartPolicy: Never`.

채점: Job 스펙과 **`status.succeeded` 가 3 에 도달했는지**, CronJob 의 스케줄·정책 필드.

> 참고: [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) ·
> [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-job/)

## 3. Q3 (6점) init 컨테이너로 콘텐츠 준비

네임스페이스 `dev` 에 파드 `web-init` 을 만들어라.

- init 컨테이너 `setup` — 이미지 `busybox:1.36`, emptyDir 볼륨 `web` 을 `/work` 에 마운트하고
  명령 `sh -c "echo ready-to-serve > /work/index.html"` 실행.
- 메인 컨테이너 `web` — 이미지 `nginx:1.26`, 같은 볼륨을 `/usr/share/nginx/html` 에 마운트.

채점: init 컨테이너 구성과 함께 **파드 IP 로 HTTP 요청 시 `ready-to-serve` 가 응답되는지** 를 본다.

> 참고: [Init 컨테이너](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

## 4. Q4 (7점) 롤링 업데이트 — 무중단 배포 전략

네임스페이스 `prod` 의 Deployment `api`(nginx:1.25, replicas 2)가 준비돼 있다.

1. 업데이트 전략을 **maxSurge 1 · maxUnavailable 0** 으로 설정하라(무중단 조건).
2. 컨테이너 이미지를 **`nginx:1.26`** 으로 롤링 업데이트하라.
3. 업데이트가 완료되어 **2개 레플리카 모두 새 버전으로 Ready** 여야 한다.

채점: strategy 필드, 새 이미지, 롤아웃 완료(리비전 증가·전 파드 Ready).

> 참고: [Deployment — 롤링 업데이트](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 5. Q5 (6점) 카나리 배포 — 트래픽 25%

네임스페이스 `prod` 에 Deployment `shop`(track=stable, replicas 4)과 Service `shop-svc`
(셀렉터 `app: shop`)가 있다. 새 버전을 **카나리로 25%** 만 내보내라.

1. Deployment `shop-canary` 를 만들어라 — 이미지 **`nginx:1.26`**, replicas **1**,
   파드 라벨 **`app: shop` + `track: canary`** (서비스가 함께 잡도록).
2. 기존 `shop` 을 replicas **3** 으로 줄여, 서비스 뒤 파드가 **stable 3 : canary 1** 이 되게 하라.

채점: 카나리 Deployment 스펙, 서비스 엔드포인트에 카나리 파드가 포함되는지, 3:1 비율.

> 참고: [카나리 배포](https://kubernetes.io/docs/concepts/workloads/management/#canary-deployments)

## 6. Q6 (7점) Kustomize 오버레이

`~/work/kustomize/base` 에 Deployment `hello-web`(nginx:1.25, replicas 1)의 base 가 준비돼 있다.

1. **`~/work/kustomize/overlays/prod`** 디렉터리에 오버레이를 만들어라. base 를 참조하고,
   - **namespace 를 `prod`** 로,
   - **replicas 를 2** 로,
   - **이미지 태그를 `nginx:1.26`** 으로 바꾼다.
2. `kubectl apply -k ~/work/kustomize/overlays/prod` 로 적용하라.

채점: 오버레이 디렉터리의 kustomization 구성(파일)과 **클러스터에 적용된 결과**
(prod 에 hello-web, replicas 2, nginx:1.26, Ready).

> 참고: [Kustomize 로 리소스 관리](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

## 7. Q7 (5점) 프로브 — 자가 치유와 트래픽 게이팅

네임스페이스 `dev` 에 파드 `probe-pod`(이미지 `nginx:1.26`)를 만들고 프로브 두 개를 달아라.

- **readinessProbe** — `httpGet` path `/` port `80`, `initialDelaySeconds: 3`, `periodSeconds: 5`
- **livenessProbe** — `httpGet` path `/` port `80`, `periodSeconds: 10`

채점: 두 프로브의 필드 값과 파드가 **Ready** 인지.

> 참고: [프로브 구성](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 8. Q8 (5점) 장애 진단 — CrashLoopBackOff

네임스페이스 `broken` 의 Deployment `orders` 가 CrashLoopBackOff 다.

1. 원인을 로그에서 확인하고, **실패 로그(에러 메시지가 담긴 출력)를 `~/answers/q8.txt` 에 저장**하라.
   (`kubectl logs` 출력을 그대로 리다이렉트하면 된다.)
2. 컨테이너 명령을 `sh -c "while true; do date; sleep 5; done"` 으로 고쳐
   **Deployment 를 정상(Available) 상태로** 만들어라.

채점: 답안 파일에 실제 에러 문자열이 있는지, Deployment 가 Available 인지.

> 참고: [실행 중인 파드 디버깅](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)

## 9. Q9 (5점) 폐기된 API 버전 수정

`~/work/legacy/stack.yaml` 은 예전 클러스터에서 쓰던 매니페스트라 **제거된 apiVersion** 을 쓰고 있어
`kubectl apply` 가 실패한다.

1. 파일의 apiVersion 을 **현재 클러스터가 지원하는 버전으로 고쳐라** (리소스 종류·이름·스펙은 유지).
2. 고친 파일을 적용해 네임스페이스 `batch` 에 Deployment `report-api` 와 CronJob `report-gen` 이
   생기게 하라.

채점: 두 리소스가 존재하는지, 파일의 apiVersion 이 올바른지.

> 참고: [폐기된 API 마이그레이션 가이드](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

## 10. Q10 (7점) ConfigMap 과 Secret 소비

네임스페이스 `dev` 에서:

1. ConfigMap `app-config` — 키 `mode=production`, `timeout=30`.
2. Secret `db-cred` — 키 `user=admin`, `pass=S3cret1`.
3. 파드 `webapp` — 이미지 `busybox:1.36`, 명령 `sh -c "sleep 86400"`.
   - 환경 변수 **`APP_MODE`** 에 ConfigMap 의 `mode` 키를 주입 (`configMapKeyRef`).
   - Secret 전체를 볼륨으로 **`/etc/creds`** 에 읽기 전용 마운트.

채점: 리소스 값들과 함께 **파드 안에서 실제로** `APP_MODE=production` 환경 변수와
`/etc/creds/user` 파일 내용이 보이는지 확인한다.

> 참고: [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 11. Q11 (6점) SecurityContext — 비루트·읽기 전용

네임스페이스 `dev` 에 파드 `secure-app` 을 만들어라. 이미지 `busybox:1.36`,
명령 `sh -c "sleep 86400"`, 그리고:

- `runAsUser: 1000`, `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- capabilities — **전부 drop** (`drop: ["ALL"]`)
- emptyDir 볼륨을 `/tmp` 에 마운트(읽기 전용 루트에서 쓰기 공간)

채점: 각 보안 필드와 파드가 Running 인지, **실제로 uid 1000 으로 도는지**(`id -u`).

> 참고: [파드 SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 12. Q12 (6점) ServiceAccount 와 토큰 자동 마운트

네임스페이스 `dev` 에서:

1. ServiceAccount `app-sa` 를 만들어라.
2. 파드 `sa-pod` — 이미지 `busybox:1.36`, 명령 `sh -c "sleep 86400"`,
   **`serviceAccountName: app-sa`**, 그리고 파드 스펙에서
   **`automountServiceAccountToken: false`** 로 토큰 자동 마운트를 꺼라.

채점: SA 존재, 파드의 SA 지정, **파드 안에 토큰 디렉터리가 실제로 없는지** 확인.

> 참고: [파드의 ServiceAccount 구성](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

## 13. Q13 (6점) 리소스 요청·상한 — Quota 안에서

네임스페이스 `batch` 에는 ResourceQuota `batch-quota`(requests.cpu 1, requests.memory 1Gi)가
걸려 있다. Deployment `worker` 를 만들어라.

- 이미지 `busybox:1.36`, 명령 `sh -c "sleep 86400"`, replicas **2**
- 컨테이너 리소스: requests **cpu 100m · memory 64Mi**, limits **cpu 200m · memory 128Mi**

채점: requests/limits 값과 **2개 레플리카가 실제로 Ready** 인지(Quota 가 있는 네임스페이스에서는
requests 를 지정하지 않으면 파드 생성 자체가 거부된다는 것을 확인하는 문제다).

> 참고: [컨테이너 리소스 관리](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

## 14. Q14 (7점) Service — ClusterIP 와 NodePort

네임스페이스 `prod` 의 Deployment `frontend`(nginx:1.26)가 준비돼 있다.

1. ClusterIP Service **`frontend-svc`** — port 80 → targetPort 80, 셀렉터 `app: frontend`.
2. NodePort Service **`frontend-np`** — port 80, **nodePort 30080**, 같은 셀렉터.

채점: 두 서비스의 타입·포트·셀렉터, 엔드포인트가 비어 있지 않은지, 그리고 **실제 통신**
(클러스터 안에서 서비스 DNS 로, 노드에서 30080 포트로).

> 참고: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 15. Q15 (6점) Ingress 리소스 작성

네임스페이스 `prod` 에 Ingress **`web-ing`** 을 작성하라. 호스트 **`shop.example.com`** 에 대해:

- 경로 **`/`** (Prefix) → Service `frontend-svc` 포트 80
- 경로 **`/shop`** (Prefix) → Service `shop-svc` 포트 80

이 환경에는 Ingress 컨트롤러가 없으므로 **리소스 스펙만 채점**한다(라우팅 확인 없음).

> 참고: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 16. Q16 (7점) NetworkPolicy — 지정 클라이언트만 허용

네임스페이스 `dev` 에 파드 `cache`(app=cache)와 검증용 파드 `client`(role=client),
`intruder` 가 준비돼 있다.

NetworkPolicy **`cache-guard`** 를 만들어라.

- 대상: **`app: cache`** 파드
- **`role: client`** 라벨 파드에서 오는 **TCP 80** ingress 만 허용 (그 외 전부 차단)

채점: 정책 스펙과 **실제 통신** — client → cache 는 되고, intruder → cache 는 막혀야 한다.

> 참고: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
