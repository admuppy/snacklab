# CKA 모의고사 1회 (120분 · 17문항 · 100점)

Linux Foundation **CKA(Certified Kubernetes Administrator)** 실기 시험 형식을 옮긴 모의고사다.
문제는 시험과 같은 도메인 배점으로 배분했다.

| 도메인 | 배점 | 문항 |
|---|---|---|
| 클러스터 아키텍처·설치·구성 | 25 | Q1 Q2 Q3 Q4 Q16 Q17 |
| 워크로드·스케줄링 | 15 | Q5 Q6 Q7 |
| 서비스·네트워킹 | 20 | Q8 Q9 Q10 |
| 스토리지 | 10 | Q11 Q12 |
| 트러블슈팅 | 30 | Q13 Q14 Q15 |

**진행 방식**

- 제한 시간 **120분**. 남은 시간은 화면 상단에 표시된다.
- 문항은 **순서와 무관하게** 풀어도 된다. 자신 있는 것부터 처리하는 것이 실제 시험 전략이다.
  단 **Q9 는 Q5 의 `web` 파드가 떠 있어야** 통신으로 채점할 수 있다.
- 실제 시험처럼 **푸는 중에는 채점 결과가 없다**. 다 풀고 아래 **[제출하고 채점하기]** 를 한 번 누르면
  17문항이 한꺼번에 채점된다(문항마다 실제 클러스터를 확인하므로 1~2분 걸린다).
- **부분 점수가 있다.** 문항마다 채점 항목이 여러 개고 맞힌 항목만큼 점수가 붙는다.
  채점이 끝나면 화면 위쪽에 총점과 문항별 점수·채점 항목이 뜨고, **아래쪽에 틀린 문항 해설**이 붙는다.
- **합격선은 66점**이다. 넘기면 축하 메시지와 함께 모듈 이수 뱃지를 받는다(만점이 아니어도 된다).
- 제출 후에도 남은 시간 안에서 계속 고쳐 **다시 채점**할 수 있다. 최고 점수가 기록된다.
- 네임스페이스를 문제가 지정한 경우 **반드시 그 네임스페이스에** 만들어야 한다.

**시험 언어**

실제 CKA 시험은 **영어·일본어·중국어(간체)** 로만 제공된다(한국어판은 없다). 이 모의고사도 그 세
언어와 한국어를 지원하니, 시험장에서 읽게 될 문장에 익숙해지고 싶다면 상단 언어 선택에서
**English / 日本語 / 简体中文** 으로 바꿔 한 번 더 풀어 보는 것을 권한다.

**환경**

파드 안에서 도는 **단일노드 k3s v1.36** 클러스터이며 당신 전용이다. `kubectl`(`k` 별칭)과
`KUBECONFIG` 은 이미 설정돼 있고, `sudo` 는 비밀번호 없이 쓸 수 있다. `jq` 와 `vi`/`nano` 가
있다. 시험처럼 [쿠버네티스 공식 문서](https://kubernetes.io/docs/) 를 봐도 된다 — 오히려 문서에서
YAML 예시를 찾아 고쳐 쓰는 것이 시험의 정석이다.

```bash
kubectl get nodes       # lab(컨트롤플레인) + worker-1·worker-2(가상 워커)
kubectl get ns          # app-prod, ops, broken, maint 가 준비돼 있다
```

**실제 시험과 다른 점** (환경 제약상 불가피한 부분)

- **kubeadm 클러스터 업그레이드** 문제는 넣지 않았다. k3s 기반이라 kubeadm 절차가
  재현되지 않는다 — 이 영역은 별도 학습이 필요하다.
- **Q16 의 etcd 복구는 오프라인 단계까지만** 채점한다(`--data-dir` 복구). 복구본으로 운영
  클러스터를 절체하는 마지막 단계는 k3s 전용 절차라 범위에서 뺐다.
- **worker-1·worker-2 는 KWOK 가상 워커**다. 스케줄·축출·drain 은 실제와 동일하게 동작하지만,
  그 위의 파드가 진짜 프로세스를 실행하지는 않는다(Q17 채점에는 영향 없다).
- Ingress 컨트롤러가 없어 **Q10 은 리소스 작성까지만** 채점한다(실제 라우팅 확인 없음).

> 시간 절약 요령: `kubectl create ... --dry-run=client -o yaml > q.yaml` 로 뼈대를 만든 뒤
> 편집하는 습관이 시험에서 가장 크게 유리하다. `kubectl explain <리소스>.<필드>` 도 즉시 쓸 수 있다.

## 1. Q1 (5점) RBAC — ServiceAccount·Role·RoleBinding

네임스페이스 `app-prod` 에서 배포 도구가 쓸 **읽기 전용** 신원을 만들어라.

- ServiceAccount `deploy-bot`
- Role `pod-reader` — `pods` 와 `deployments`(apps 그룹)에 대해 **`get`, `list`, `watch` 만**
- RoleBinding `deploy-bot-rb` — 위 Role 을 `deploy-bot` 에 연결

권한은 `app-prod` 안에서만 유효해야 한다. 다른 네임스페이스의 파드가 조회되거나
파드를 만들고 지울 수 있으면 오답이다.

```bash
kubectl auth can-i list pods -n app-prod --as=system:serviceaccount:app-prod:deploy-bot
```

> 참고: [RBAC 인가](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 2. Q2 (4점) CSR 승인과 사용자 권한 부여

새 개발자 `dev-user` 의 클라이언트 인증서 서명 요청이 **승인 대기 중**이다.

```bash
kubectl get csr
```

1. CSR `dev-user` 를 **승인**해 인증서가 발급되게 하라.
2. 사용자(User) `dev-user` 가 `app-prod` 를 **열람만** 할 수 있도록,
   기본 ClusterRole `view` 를 쓰는 RoleBinding `dev-user-view` 를 `app-prod` 에 만들어라.

`edit` 이나 `admin` 을 바인딩하면 오답이다. 확인:

```bash
kubectl auth can-i list pods   -n app-prod --as=dev-user   # yes
kubectl auth can-i delete pods -n app-prod --as=dev-user   # no
```

> 참고: [인증서와 CSR](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)

## 3. Q3 (4점) 정적 파드(static pod) 생성

노드의 kubelet 이 **직접** 관리하는 정적 파드를 만들어라. apiserver 로 만들면 안 된다.

- 이름 `ops-static`, 네임스페이스 `default`
- 이미지 `busybox:1.36`, 명령은 계속 살아 있도록 (예: `sleep 86400`)

이 환경(k3s)의 매니페스트 디렉터리는 다음과 같다.

```bash
ls /var/lib/rancher/k3s/agent/pod-manifests/
```

정적 파드는 apiserver 에 **미러 파드**로 나타나며 이름 뒤에 노드명이 붙는다
(`ops-static-<노드명>`). 파일을 놓은 뒤 몇 초 기다렸다가 `kubectl get pod` 로 확인하라.

> 참고: [정적 파드](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

## 4. Q4 (3점) ResourceQuota·LimitRange

네임스페이스 `ops` 의 사용량을 통제하라.

ResourceQuota `ops-quota`:

| 항목 | 값 |
|---|---|
| `pods` | 5 |
| `requests.cpu` | 1 |
| `requests.memory` | 1Gi |

LimitRange `ops-limits` (`type: Container`):

| 항목 | 값 |
|---|---|
| `defaultRequest.cpu` | 100m |
| `defaultRequest.memory` | 128Mi |
| `default.cpu` | 200m |
| `default.memory` | 256Mi |

쿼터에 `requests.*` 가 걸리면 그 네임스페이스의 **모든 파드가 요청량을 선언**해야 한다는 점을
기억하라 — LimitRange 의 기본값이 그 역할을 대신해 준다.

> 참고: [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/) ·
> [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)

## 5. Q5 (6점) Deployment 와 롤아웃 전략

네임스페이스 `app-prod` 에 Deployment `web` 을 만들어라.

- 레플리카 **3**, 이미지 `nginx:1.26`
- 컨테이너 요청량 `cpu: 50m`, `memory: 64Mi`
- 롤아웃 전략 `RollingUpdate` 이면서 **무중단**: `maxSurge: 1`, `maxUnavailable: 0`
- 파드 라벨은 `app=web` (뒤 문항들이 이 라벨을 쓴다)

세 개가 모두 Ready 여야 통과다.

> 참고: [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 6. Q6 (4점) DaemonSet 배포

네임스페이스 `ops` 에 DaemonSet `node-agent` 를 배포하라.

- 이미지 `busybox:1.36`, 계속 실행되는 명령
- **요청량을 명시**할 것 (예: `cpu: 10m`, `memory: 16Mi`) — `ops` 에는 쿼터가 걸려 있다
- 모든 노드에서 파드가 Ready 여야 한다

> 참고: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)

## 7. Q7 (5점) 사이드카 컨테이너와 공유 볼륨

네임스페이스 `app-prod` 에 파드 `logger` 를 만들어라. 컨테이너 **2개**가 `emptyDir` 볼륨
하나를 **같은 경로 `/var/log/app`** 로 공유해야 한다.

- 컨테이너 `app` — 주기적으로 `/var/log/app/app.log` 에 무언가를 덧붙여 쓴다
- 컨테이너 `sidecar` — 같은 파일을 읽는다 (예: `tail -f`)

채점은 **sidecar 안에서 그 로그 파일이 실제로 읽히는지** 로 한다. 마운트만 걸고 아무것도
쓰지 않으면 통과하지 못한다.

> 참고: [로깅 아키텍처 — 사이드카](https://kubernetes.io/docs/concepts/cluster-administration/logging/#sidecar-container-with-logging-agent)

## 8. Q8 (7점) Service — ClusterIP 와 NodePort

Q5 의 `web` 파드를 두 가지 방식으로 노출하라. 둘 다 네임스페이스 `app-prod` 다.

| 이름 | 타입 | 포트 |
|---|---|---|
| `web-svc` | ClusterIP | `80` → 컨테이너 `80` |
| `web-np` | NodePort | `80` → 컨테이너 `80`, nodePort **30080** |

두 서비스 모두 엔드포인트가 **3개**여야 하고, 클러스터 안에서 DNS 이름
`web-svc.app-prod.svc.cluster.local` 로 실제 응답이 와야 한다.

> 참고: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

## 9. Q9 (7점) NetworkPolicy 로 트래픽 차단

네임스페이스 `app-prod` 를 기본 차단으로 바꾸고, 지정한 클라이언트만 통과시켜라.

1. `default-deny` — `app-prod` 의 **모든 파드**에 대해 **Ingress 전면 차단**
   (`podSelector: {}`, `policyTypes: ["Ingress"]`)
2. `allow-client` — `app=web` 파드에 대해, **`role=client` 라벨을 가진 파드**로부터
   **TCP 80** 만 허용

네임스페이스에는 이미 `client`(`role=client`)와 `intruder`(`role=outsider`) 파드가 떠 있다.
채점은 실제 통신으로 한다 — `client` 는 `web` 에 닿아야 하고 `intruder` 는 막혀야 한다.

```bash
kubectl exec -n app-prod client   -- wget -T3 -qO- http://<web파드IP>/
kubectl exec -n app-prod intruder -- wget -T3 -qO- http://<web파드IP>/   # 막혀야 정상
```

> 참고: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 10. Q10 (6점) Ingress 리소스 작성

네임스페이스 `app-prod` 에 Ingress `web-ing` 을 작성하라.

- host `shop.example.com`
- path `/`, `pathType: Prefix`
- 백엔드 Service `web-svc` 의 포트 `80`

이 환경에는 Ingress 컨트롤러가 없으므로 **리소스 정의만** 채점한다(실제 라우팅은 확인하지 않는다).

> 참고: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## 11. Q11 (5점) PV·PVC 정적 바인딩

정적으로 준비한 볼륨을 파드에 연결하라.

1. PersistentVolume `pv-data` — 용량 `1Gi`, `ReadWriteOnce`,
   `storageClassName: manual`, hostPath `/mnt/data`
2. PersistentVolumeClaim `pvc-data` (`app-prod`) — `1Gi`, `ReadWriteOnce`,
   같은 `storageClassName` 으로 **`pv-data` 에 바인딩**되어야 한다
3. 파드 `data-user` (`app-prod`) — 그 PVC 를 `/data` 에 마운트하고 Running

`storageClassName` 을 비워 두면 기본 StorageClass 가 동적으로 다른 볼륨을 만들어 붙는다.
그러면 `Bound` 이긴 해도 `pv-data` 가 아니므로 오답이다.

> 참고: [PV·PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

## 12. Q12 (5점) 동적 프로비저닝과 데이터 쓰기

기본 StorageClass 로 볼륨을 **동적 생성**해 사용하라.

1. PVC `pvc-dyn` (`app-prod`) — `storageClassName: local-path`, `500Mi`, `ReadWriteOnce`
2. 파드 `writer` (`app-prod`) — 그 PVC 를 `/data` 에 마운트하고,
   `/data/hello.txt` 에 `cka` 를 기록한 뒤 계속 실행

`local-path` 는 `WaitForFirstConsumer` 라 **파드가 붙기 전까지 PVC 는 Pending** 이다.
정상 동작이니 파드를 먼저 만들어라.

```bash
kubectl get sc
```

> 참고: [StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 13. Q13 (10점) 장애 조치 — 기동하지 않는 Deployment

네임스페이스 `broken` 의 Deployment `api` 가 **한 번도 Ready 가 되지 않는다.**
원인을 찾아 고쳐라. 레플리카 수(**2**)와 이름·네임스페이스는 그대로 유지해야 한다.

```bash
kubectl get pods -n broken
kubectl describe pod -n broken <파드>      # Events 를 읽어라
```

두 파드가 모두 Running·Ready 이고, 실패한 파드가 남아 있지 않아야 통과다.

> 참고: [애플리케이션 트러블슈팅](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 14. Q14 (10점) 장애 조치 — 엔드포인트가 비어 있는 Service

네임스페이스 `broken` 의 Service `cache-svc` 로 아무 응답이 오지 않는다.
백엔드 Deployment `cache` 자체는 정상이다.

```bash
kubectl get endpoints cache-svc -n broken
kubectl get pods -n broken --show-labels
kubectl describe svc cache-svc -n broken
```

**틀린 곳이 두 군데**다. 서비스의 `port` 는 `80` 을 유지한 채,
엔드포인트가 채워지고 실제 HTTP 응답이 오도록 고쳐라.

> 참고: [서비스 디버깅](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

## 15. Q15 (10점) 장애 조치 — CrashLoopBackOff 와 원인 보고

네임스페이스 `broken` 의 Deployment `worker` 가 `CrashLoopBackOff` 로 재시작을 반복한다.

```bash
kubectl logs -n broken deploy/worker
kubectl describe pod -n broken <파드>
```

1. 원인을 제거해 파드가 **안정적으로 Running** 이 되게 하라(재시작 루프가 멈춰야 한다).
2. 원인이 된 리소스를 `~/answers/q15.txt` 에 **한 줄, `<kind>/<name>` 소문자 형식**으로 적어라.
   예: `deployment/foo`

채점은 컨테이너가 재시작 없이 20초 이상 살아 있어야 점수를 준다. 고친 직후에 제출하면 미달일 수 있으니 잠시 기다렸다 제출하라.

> 참고: [파드 디버깅](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

## 16. Q16 (6점) etcd 백업과 오프라인 복구

이 클러스터의 데이터스토어는 **임베디드 etcd** 다. 아래 접속 정보로 작업하라
(인증서가 root 소유이므로 `sudo` 가 필요하다).

- 엔드포인트: `https://127.0.0.1:2379`
- CA: `/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt`
- 인증서: `/var/lib/rancher/k3s/server/tls/etcd/server-client.crt`
- 키: `/var/lib/rancher/k3s/server/tls/etcd/server-client.key`

1. `etcdctl` 로 스냅샷을 **`~/backup/etcd-snap.db`** 에 저장하라.
2. 그 스냅샷을 `etcdutl` 로 **`~/backup/restored`** 디렉터리에 **오프라인 복구**하라
   (`--data-dir` 사용, 대상 디렉터리가 미리 존재하면 실패한다).

**주의**: 복구본으로 운영 클러스터를 절체하는 단계는 이 시험 범위가 아니다.
`k3s server --cluster-reset` 류 명령을 실행하면 다른 문항의 리소스가 사라질 수 있다.

> 참고: [etcd 클러스터 운영](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

## 17. Q17 (3점) 노드 비우기(drain) — worker-1 유지보수

워커 노드 `worker-1` 이 커널 패치를 위해 곧 내려간다. 네임스페이스 `maint` 의
Deployment `payments`(레플리카 4)가 worker-1/worker-2 에 걸쳐 돌고 있다.

1. `worker-1` 을 **안전하게 비워라** — 스케줄 금지 상태를 유지하고, DaemonSet 은 무시한다.
2. 작업 후에도 `payments` 는 **4개 모두 가용**해야 한다(worker-2 로 옮겨진다).

```bash
kubectl get pods -n maint -o wide
```

> 참고: [노드 안전하게 비우기](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
