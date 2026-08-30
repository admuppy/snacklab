# CKS 모의고사 1회 (120분 · 16문항 · 100점)

Linux Foundation **CKS(Certified Kubernetes Security Specialist)** 실기 시험 형식을 옮긴 모의고사다.
문제는 시험과 같은 도메인 배점으로 배분했다.

| 도메인 | 배점 | 문항 |
|---|---|---|
| 클러스터 셋업 | 15 | Q1 Q2 Q3 |
| 클러스터 하드닝 | 15 | Q4 Q5 Q6 |
| 시스템 하드닝 | 10 | Q7 Q8 |
| 마이크로서비스 취약점 최소화 | 20 | Q9 Q10 Q11 |
| 공급망 보안 | 20 | Q12 Q13 Q14 |
| 모니터링·로깅·런타임 보안 | 20 | Q15 Q16 |

**진행 방식**

- 제한 시간 **120분**. 남은 시간은 화면 상단에 표시된다.
- 문항은 **순서와 무관하게** 풀어도 된다. 자신 있는 것부터 처리하는 것이 실제 시험 전략이다.
- 실제 시험처럼 **푸는 중에는 채점 결과가 없다**. 다 풀고 아래 **[제출하고 채점하기]** 를 한 번 누르면
  16문항이 한꺼번에 채점된다(문항마다 실제 클러스터를 확인하므로 1~2분 걸린다).
- **부분 점수가 있다.** 문항마다 채점 항목이 여러 개고 맞힌 항목만큼 점수가 붙는다.
  채점이 끝나면 화면 위쪽에 총점과 문항별 점수·채점 항목이 뜨고, **아래쪽에 틀린 문항 해설**이 붙는다.
- **합격선은 67점**이다(실제 CKS 와 동일). 넘기면 축하 메시지와 함께 모듈 이수 뱃지를 받는다.
- 제출 후에도 남은 시간 안에서 계속 고쳐 **다시 채점**할 수 있다. 최고 점수가 기록된다.
- 네임스페이스를 문제가 지정한 경우 **반드시 그 네임스페이스에** 만들어야 한다.
- 답안 파일을 요구하는 문항은 **정확히 지정한 경로**(`~/answers/…`)에 써야 채점된다.

**환경**

파드 안에서 도는 **단일노드 k3s v1.36** 클러스터이며 당신 전용이다. `kubectl`(`k` 별칭)과
`KUBECONFIG` 은 이미 설정돼 있고, `sudo` 는 비밀번호 없이 쓸 수 있다. `jq`, `openssl`,
`sha512sum`, `vi`/`nano` 가 있다. 시험처럼 [쿠버네티스 공식 문서](https://kubernetes.io/docs/) 를
봐도 된다.

```bash
kubectl get nodes
kubectl get ns    # prod, apps, sys-hard, restricted-ns, supply, runtime 이 준비돼 있다
ls ~/work         # 문항이 참조하는 파일들
```

**실제 시험과 다른 점** (환경 제약상 불가피한 부분)

- **AppArmor, Falco, gVisor(RuntimeClass)** 문항은 넣지 않았다. 파드 안 클러스터라 호스트 커널
  기능을 보장할 수 없다. 이 영역은 별도 학습이 필요하다.
- **trivy 바이너리가 없다.** Q13 은 미리 떠 놓은 스캔 리포트(`~/work/scans/`)를 읽고 판단한다
  (실제 시험에서는 `trivy image <이미지>` 를 직접 실행한다).
- Ingress 컨트롤러가 없어 **Q2 는 리소스 작성까지만** 채점한다(실제 TLS 종단 확인 없음).
- ImagePolicyWebhook/OPA Gatekeeper 는 구성 요소 반입 문제로 제외했다.

> 시간 절약 요령: `kubectl create ... --dry-run=client -o yaml > q.yaml` 로 뼈대를 만들고,
> 기존 리소스는 `kubectl get ... -o yaml > q.yaml` 로 내려받아 고친 뒤 apply 하라.
> `kubectl explain pod.spec.securityContext` 도 즉시 쓸 수 있다.

## 1. Q1 (7점) NetworkPolicy — 기본 차단과 선별 허용

네임스페이스 `prod` 에는 `backend`(nginx, `app=backend`)와 발신용 `frontend`(`app=frontend`),
`other`(`app=other`) 파드가 떠 있다. 기본 차단 후 지정 경로만 허용하라.

1. `deny-all` — `prod` 의 **모든 파드**에 대해 **Ingress 전면 차단**
   (`podSelector: {}`, `policyTypes: ["Ingress"]`)
2. `allow-frontend` — `app=backend` 파드에 대해, **`app=frontend` 파드로부터의 TCP 80** 만 허용

채점은 실제 통신으로 한다 — `frontend` 는 `backend` 에 닿아야 하고 `other` 는 막혀야 한다.

```bash
kubectl exec -n prod frontend -- wget -T3 -qO- http://<backend파드IP>/
kubectl exec -n prod other    -- wget -T3 -qO- http://<backend파드IP>/   # 막혀야 정상
```

> 참고: [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 2. Q2 (4점) TLS Secret 과 TLS Ingress

네임스페이스 `prod` 의 웹 서비스에 TLS 를 입혀라.

1. `openssl` 로 **자체 서명 인증서**를 만들어라 — CN 은 `web.snacklab.local`
2. 그 인증서·키로 **TLS 타입 Secret** `web-cert` 를 `prod` 에 만들어라
3. Ingress `web-tls` (`prod`) — host `web.snacklab.local`, path `/`(Prefix),
   백엔드 `web-svc:80`, **`tls` 섹션에서 `web-cert` 참조**

이 환경에는 Ingress 컨트롤러가 없으므로 **리소스 정의만** 채점한다.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
```

> 참고: [Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) ·
> [TLS Secret](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## 3. Q3 (4점) 플랫폼 바이너리 무결성 검증

`~/work/binaries/` 에 릴리스 바이너리 3개(`kube-apiserver`, `kubelet`, `kube-proxy`)와
배포처가 공개한 체크섬 파일 `checksums.txt` 가 있다.

1. **SHA-512 체크섬을 대조**해 변조된 바이너리를 찾아라.
2. 변조된 바이너리의 **파일 이름 한 줄**을 `~/answers/q3.txt` 에 적어라. 예: `kube-proxy`

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
```

> 참고: [릴리스 바이너리 검증](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/)

## 4. Q4 (6점) RBAC 최소 권한으로 조이기

네임스페이스 `apps` 의 ServiceAccount `ci-bot` 은 CI 파이프라인용인데, 지금
RoleBinding `ci-bot-rb` 가 ClusterRole `admin` 을 통째로 물려줘 **권한이 과하다**.

`ci-bot` 이 딱 다음만 할 수 있게 고쳐라.

- `pods` — `get`, `list`
- `deployments`(apps 그룹) — `get`, `list`, `update`

Role 이름은 `ci-role`, 바인딩 이름은 `ci-bot-rb` 를 **그대로 유지**하라(교체는 자유).
Secret 조회나 파드 삭제가 여전히 가능하면 감점이다.

```bash
kubectl auth can-i list secrets -n apps --as=system:serviceaccount:apps:ci-bot   # no 여야 한다
```

> 참고: [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

## 5. Q5 (5점) ServiceAccount 토큰 자동 마운트 차단

네임스페이스 `apps` 의 Deployment `web` 은 API 를 쓸 일이 없는데 **기본 SA 토큰이
컨테이너에 마운트**되고 있다 — 침해 시 API 접근 통로가 된다.

1. ServiceAccount `web-sa` 를 `apps` 에 만들되 **`automountServiceAccountToken: false`**
2. Deployment `web` 이 `web-sa` 를 쓰도록 수정
3. 새 파드 안에 `/var/run/secrets/kubernetes.io/serviceaccount` 가 **마운트되지 않아야** 한다

```bash
kubectl exec -n apps deploy/web -- ls /var/run/secrets/kubernetes.io/serviceaccount  # 실패해야 정상
```

> 참고: [SA 토큰 자동 마운트](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting)

## 6. Q6 (4점) 위험한 ClusterRoleBinding 제거

누군가 디버깅한다며 **인증된 모든 사용자(`system:authenticated`)에게 `cluster-admin`** 을
부여하는 ClusterRoleBinding 을 남겨 놓았다.

1. 해당 ClusterRoleBinding 을 찾아 **이름 한 줄**을 `~/answers/q6.txt` 에 적어라.
2. 그 바인딩을 **삭제**하라. 기본 `cluster-admin` 바인딩(`system:masters` 대상)은 건드리면 안 된다.

```bash
kubectl get clusterrolebindings -o wide | grep cluster-admin
```

> 참고: [RBAC 모범 사례](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)

## 7. Q7 (5점) seccomp RuntimeDefault 적용

네임스페이스 `sys-hard` 의 Deployment `runner` 는 seccomp 없이 돌고 있다.
**파드 시큐리티 컨텍스트**에 `seccompProfile: { type: RuntimeDefault }` 를 적용하고,
파드 2개가 모두 Ready 가 되게 하라.

> 참고: [seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)

## 8. Q8 (5점) 호스트 접근 제거 — privileged·hostPID·hostPath

네임스페이스 `sys-hard` 의 Deployment `node-tool` 은 노드를 통째로 잡고 있다:
`privileged: true`, `hostPID: true`, `hostNetwork: true`, hostPath `/` 마운트.

**네 가지 호스트 접근을 모두 제거**하고, 이름·네임스페이스·이미지를 유지한 채
파드가 계속 Running 이게 하라.

> 참고: [파드 시큐리티 컨텍스트](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 9. Q9 (7점) SecurityContext 로 컨테이너 강화

네임스페이스 `apps` 에 Deployment `secure-app` 을 만들어라.

- 이미지 `busybox:1.36`, 계속 실행되는 명령(예: `sleep 86400`), 레플리카 1
- 컨테이너 시큐리티 컨텍스트:

| 항목 | 값 |
|---|---|
| `runAsNonRoot` | `true` |
| `runAsUser` | `10001` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |
| `readOnlyRootFilesystem` | `true` |

파드가 Ready 여야 통과다.

> 참고: [SecurityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

## 10. Q10 (7점) Pod Security Admission — restricted 적용

네임스페이스 `restricted-ns` 에는 `privileged` 로 도는 Deployment `legacy` 가 있다.

1. 네임스페이스에 **`restricted` 프로파일을 enforce** 라벨로 걸어라
   (`pod-security.kubernetes.io/enforce=restricted`)
2. Deployment `legacy` 를 **restricted 기준에 맞게 고쳐** 새 파드가 정상 기동하게 하라
   (privileged 제거, `runAsNonRoot`, `allowPrivilegeEscalation: false`,
   `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault` — busybox 는
   `runAsUser` 도 지정해야 뜬다)

라벨만 걸면 **기존 파드는 남는다** — Deployment 를 고쳐 롤아웃돼야 새 파드가 심사를 통과한다.

> 참고: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) ·
> [네임스페이스에 PSA 적용](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

## 11. Q11 (6점) Secret 다루기 — 추출·생성·마운트

네임스페이스 `apps` 의 Secret `db-creds` 를 다룬다.

1. `db-creds` 의 **`password` 값을 디코드**해 `~/answers/q11.txt` 에 한 줄로 적어라.
2. 새 Secret `api-token` 을 `apps` 에 만들어라 — 키 `token`, 값 `cks-2026`
3. 파드 `secret-user` (`apps`, `busybox:1.36`, 계속 실행) — `db-creds` 를
   **읽기 전용 볼륨**으로 `/etc/creds` 에 마운트하고 Running

> 참고: [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)

## 12. Q12 (7점) Dockerfile 보안 결함 수정

`~/work/audit/Dockerfile` 은 보안 결함이 있는 채로 리뷰에 올라왔다. **파일을 직접 고쳐라.**

1. 베이스 이미지가 `latest` 다 — **`nginx:1.26`** 으로 고정하라.
2. 크리덴셜(`ENV API_KEY=…`)이 이미지에 박힌다 — **그 줄을 제거**하라.
3. `USER root` 로 끝난다 — **`nginx` 사용자**로 실행되게 바꿔라.

나머지 줄(COPY·CMD 등)은 유지해야 한다. 채점은 파일 내용으로 한다.

> 참고: [Dockerfile 모범 사례](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)

## 13. Q13 (7점) 취약 이미지 식별과 격리

네임스페이스 `supply` 에 Deployment `frontend-app`, `report-app`, `batch-app` 이 떠 있다.
각 이미지의 취약점 스캔 리포트가 `~/work/scans/` 에 준비돼 있다
(실제 시험에서는 `trivy image` 를 직접 실행한다).

1. 리포트를 읽고 **CRITICAL 취약점이 있는 이미지**를 쓰는 Deployment 를 모두 찾아라.
2. 그 Deployment 이름을 `~/answers/q13.txt` 에 **한 줄에 하나씩** 적어라.
3. 해당 Deployment 를 **replicas 0 으로 스케일**해 격리하라.
   취약점 없는 워크로드는 건드리면 안 된다.

> 참고: [공급망 보안 개요](https://kubernetes.io/docs/concepts/security/supply-chain-security/)

## 14. Q14 (6점) 이미지 다이제스트 고정

태그는 재푸시로 바꿔치기될 수 있다. 네임스페이스 `supply` 의 Deployment `pinned` 가
`nginx:1.26` 을 **태그가 아닌 다이제스트로** 참조하게 바꿔라
(`nginx@sha256:<64자리>`). 파드는 계속 Ready 여야 한다.

지금 떠 있는 파드에서 다이제스트를 얻을 수 있다:

```bash
kubectl get pod -n supply -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
```

> 참고: [이미지 다이제스트](https://kubernetes.io/docs/concepts/containers/images/#image-names)

## 15. Q15 (8점) API 서버 감사 로깅(audit logging) 구성

API 서버에 감사 로깅을 켜라. k3s 는 `/etc/rancher/k3s/config.yaml` 의
`kube-apiserver-arg` 로 apiserver 플래그를 받는다.

1. 감사 정책 `/var/lib/rancher/k3s/server/audit-policy.yaml` —
   **`secrets` 리소스는 `Metadata` 레벨**로 기록, 그 외는 기록하지 않도록(`None`)
2. apiserver 인자 — `audit-policy-file=<위 경로>`,
   `audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log`,
   `audit-log-maxage=7`, `audit-log-maxbackup=2`
3. 로그 디렉터리를 만들고 `sudo systemctl restart k3s` 로 반영하라.
   재시작 후 **`kubectl get nodes` 로 클러스터가 정상인지 반드시 확인**하라 —
   인자를 잘못 쓰면 apiserver 가 뜨지 않아 다른 문항까지 채점이 막힌다.

채점은 Secret 을 한 번 조회한 뒤 감사 로그에 그 기록이 남는지 본다.

> 참고: [감사(Auditing)](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)

## 16. Q16 (12점) 런타임 포렌식 — 침해 파드 색출과 격리

보안팀이 네임스페이스 `runtime` 에서 **암호화폐 채굴 의심 통신**을 감지했다.
워크로드는 `web`, `metrics`, `logshipper` 세 개다.

1. 각 파드의 **실행 중인 프로세스를 조사**해(`kubectl exec <pod> -- ps` 또는
   `crictl`) 침해된 파드를 찾아라. 채굴풀 주소·`xmrig` 같은 흔적이 보인다.
2. 침해 파드를 관리하는 **Deployment 이름 한 줄**을 `~/answers/q16.txt` 에 적어라.
3. 그 Deployment 를 **replicas 0 으로 스케일**해 격리하라.
   나머지 두 워크로드는 계속 Running 이어야 한다.

> 참고: [보안 체크리스트](https://kubernetes.io/docs/concepts/security/security-checklist/)
