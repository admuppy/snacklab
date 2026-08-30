# 해설

제출 후 만점을 받지 못한 문항에만 아래 해설이 화면에 표시된다.
정답은 하나가 아니다 — 채점은 "결과가 규격대로인가"를 보므로, 아래는 가장 짧은 기준 답이다.

## Q1 사이드카 컨테이너 — 로그 스트리밍

파드 하나에 컨테이너 둘, emptyDir 하나. 핵심은 **두 컨테이너가 같은 볼륨을 같은 경로에** 마운트하는 것이다.

```yaml
apiVersion: v1
kind: Pod
metadata: { name: logger, namespace: dev }
spec:
  volumes: [{ name: logs, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do echo \"tick $i\" >> /var/log/app/app.log; i=$((i+1)); sleep 2; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: streamer
      image: busybox:1.36
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

자주 틀리는 곳

- 사이드카에 볼륨을 안 붙이면 `tail` 이 빈 파일도 못 찾는다 — 로그 항목(2점)이 날아간다.
- `tail -F`(대문자)는 파일이 아직 없어도 기다린다. `-f` 는 파일이 없으면 종료해 CrashLoop 이 될 수 있다.
- 채점은 `kubectl logs logger -c streamer` 에 `tick` 이 실제로 흐르는지 본다 — 구성만 맞고 명령이 틀리면 점수가 안 나온다.

## Q2 Job 과 CronJob

Job 은 명령형으로 만들고 YAML 로 completions/parallelism 을 더하는 편이 빠르다.

```bash
kubectl create job pi -n batch --image=busybox:1.36 --dry-run=client -o yaml -- sh -c "echo 3.14159" > job.yaml
# spec: 에 completions: 3, parallelism: 2 추가 후
kubectl apply -f job.yaml
kubectl create cronjob cleanup -n batch --image=busybox:1.36 --schedule="0 3 * * *" \
  --dry-run=client -o yaml -- sh -c "echo cleaned" > cj.yaml
# spec: 에 concurrencyPolicy: Forbid, successfulJobsHistoryLimit: 1 추가 후
kubectl apply -f cj.yaml
```

자주 틀리는 곳

- `completions`/`parallelism` 은 **Job 의 spec** 이지 template.spec 이 아니다.
- CronJob 의 `concurrencyPolicy`·`successfulJobsHistoryLimit` 도 **CronJob 의 spec** 레벨이다
  (jobTemplate.spec 이 아니다).
- `restartPolicy: Never` 를 빼먹으면 기본값이 없어서 Job 생성 자체가 거부된다.

## Q3 init 컨테이너로 콘텐츠 준비

init 컨테이너가 끝나야 메인이 뜬다. 준비물(index.html)을 emptyDir 로 넘긴다.

```yaml
spec:
  volumes: [{ name: web, emptyDir: {} }]
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo ready-to-serve > /work/index.html"]
      volumeMounts: [{ name: web, mountPath: /work }]
  containers:
    - name: web
      image: nginx:1.26
      volumeMounts: [{ name: web, mountPath: /usr/share/nginx/html }]
```

자주 틀리는 곳

- 메인 마운트 경로가 nginx 문서 루트(`/usr/share/nginx/html`)가 아니면 HTTP 채점(2점)이 실패한다.
- 볼륨 이름이 서로 다르면 init 이 쓴 파일이 메인에 보이지 않는다.

## Q4 롤링 업데이트 — 무중단 배포 전략

전략 먼저, 이미지 교체는 그다음. 순서를 바꾸면 첫 롤아웃이 기본 전략(25%)으로 돈다.

```bash
kubectl patch deploy api -n prod --type merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image deploy/api -n prod api=nginx:1.26
kubectl rollout status deploy/api -n prod
```

자주 틀리는 곳

- `kubectl edit` 로 해도 된다 — 채점은 필드 값만 본다.
- `maxUnavailable: 0` 과 `maxSurge: 0` 을 동시에 쓰면 롤아웃이 영원히 안 움직인다.
- `rollout status` 로 완료를 확인하고 제출해야 "2개 모두 새 버전 Ready"(2점)를 받는다.

## Q5 카나리 배포 — 트래픽 25%

서비스 셀렉터(`app: shop`)는 그대로 두고, **같은 app 라벨 + 다른 track 라벨**의 두 번째
Deployment 를 넣는 것이 라벨 기반 카나리의 전부다.

```bash
kubectl create deploy shop-canary -n prod --image=nginx:1.26 --replicas=1 --dry-run=client -o yaml > canary.yaml
# 파드 템플릿 라벨을 app: shop, track: canary 로, selector 도 같게 고친 뒤 apply
kubectl scale deploy shop -n prod --replicas=3
```

자주 틀리는 곳

- `kubectl create deploy` 가 만드는 라벨은 `app: shop-canary` 다 — **꼭 `app: shop` 으로 고쳐야**
  서비스가 카나리를 잡는다(엔드포인트 항목 2점이 여기 걸려 있다).
- selector 와 template 라벨이 안 맞으면 apply 자체가 거부된다.
- stable 을 3 으로 줄이는 걸 잊으면 4:1 이 되어 25% 가 아니다.

## Q6 Kustomize 오버레이

오버레이는 base 를 참조하는 kustomization.yaml 하나로 완성된다.

```yaml
# ~/work/kustomize/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources: [../../base]
replicas: [{ name: hello-web, count: 2 }]
images: [{ name: nginx, newTag: "1.26" }]
```

```bash
kubectl apply -k ~/work/kustomize/overlays/prod
```

자주 틀리는 곳

- `resources` 의 상대경로는 **오버레이 디렉터리 기준**이다(`../../base`).
- `images.name` 은 base 가 쓰는 **이미지 이름**(nginx)이지 컨테이너 이름(web)이 아니다.
- `newTag` 는 문자열이다 — `"1.26"` 처럼 따옴표를 두르는 습관이 안전하다.
- 파일만 만들고 `apply -k` 를 잊으면 클러스터 항목 5점이 전부 날아간다.

## Q7 프로브 — 자가 치유와 트래픽 게이팅

문제에 적힌 숫자를 그대로 옮기면 된다. 프로브는 컨테이너 레벨 필드다.

```yaml
containers:
  - name: web
    image: nginx:1.26
    readinessProbe:
      httpGet: { path: /, port: 80 }
      initialDelaySeconds: 3
      periodSeconds: 5
    livenessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 10
```

자주 틀리는 곳

- readiness 와 liveness 필드 이름이 비슷해 서로 바꿔 넣기 쉽다 — 채점은 각각 따로 본다.
- 포트를 8080 등으로 잘못 쓰면 스펙 항목은 물론 Ready 항목(1점)까지 실패한다.

## Q8 장애 진단 — CrashLoopBackOff

원인 조사(로그 저장) → 수리(명령 교체) 순서다.

```bash
kubectl logs deploy/orders -n broken > ~/answers/q8.txt 2>&1   # "not found" 가 담긴다
kubectl patch deploy orders -n broken --type json -p \
  '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","while true; do date; sleep 5; done"]}]'
```

자주 틀리는 곳

- CrashLoop 파드의 로그는 `--previous` 없이도 마지막 실행 출력이 나온다. 비어 있으면
  `kubectl logs <파드> -n broken --previous` 를 쓰면 된다.
- 답안 파일에는 **에러가 담긴 실제 출력**이 있어야 한다. 손으로 쓴 요약은 인정되지 않는다.
- `kubectl edit deploy orders -n broken` 로 command 를 고쳐도 똑같이 인정된다.

## Q9 폐기된 API 버전 수정

`apps/v1beta1`·`batch/v1beta1` 은 오래전에 제거됐다. 현행 버전은 `apps/v1`·`batch/v1` 이다.

```bash
sed -i -e 's|apps/v1beta1|apps/v1|' -e 's|batch/v1beta1|batch/v1|' ~/work/legacy/stack.yaml
kubectl apply -f ~/work/legacy/stack.yaml
```

자주 틀리는 곳

- 어떤 버전이 맞는지 모르겠으면 `kubectl api-resources | grep -i cronjob` 또는
  `kubectl explain cronjob` 이 현행 group/version 을 알려준다.
- **파일 자체**도 채점 대상(2점)이다 — 파일은 안 고치고 새 YAML 을 따로 만들면 그 항목을 잃는다.
- apply 만 하고 report-api 가 Ready 인지 확인 안 하면 마지막 1점을 놓칠 수 있다.

## Q10 ConfigMap 과 Secret 소비

생성은 명령형 두 줄, 소비는 YAML 로.

```bash
kubectl create configmap app-config -n dev --from-literal=mode=production --from-literal=timeout=30
kubectl create secret generic db-cred -n dev --from-literal=user=admin --from-literal=pass=S3cret1
```

```yaml
spec:
  volumes: [{ name: creds, secret: { secretName: db-cred } }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef: { name: app-config, key: mode }
      volumeMounts: [{ name: creds, mountPath: /etc/creds, readOnly: true }]
```

자주 틀리는 곳

- `env: [{name: APP_MODE, value: production}]` 처럼 **리터럴로 넣으면 인정되지 않는다** —
  채점이 `configMapKeyRef` 참조 여부를 본다.
- Secret 볼륨은 키마다 파일이 된다(`/etc/creds/user`, `/etc/creds/pass`).
- 파드 생성 후 ConfigMap 을 고쳐도 env 는 안 바뀐다 — 값을 잘못 넣었다면 파드를 다시 만들어야 한다.

## Q11 SecurityContext — 비루트·읽기 전용

runAsUser/runAsNonRoot 는 파드 레벨에 둬도 되고, 나머지 셋은 **컨테이너 레벨**이다.

```yaml
spec:
  securityContext: { runAsUser: 1000, runAsNonRoot: true }
  volumes: [{ name: tmp, emptyDir: {} }]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      volumeMounts: [{ name: tmp, mountPath: /tmp }]
```

자주 틀리는 곳

- `allowPrivilegeEscalation`·`readOnlyRootFilesystem`·`capabilities` 는 파드 레벨에 두면
  **스키마 오류**다 — 컨테이너 securityContext 에만 있다.
- 읽기 전용 루트에서 셸이 쓸 공간이 없으면 이미지에 따라 기동이 실패한다 — `/tmp` emptyDir 가 그 대비다.
- uid 1000 이 실제로 적용됐는지는 `kubectl exec secure-app -n dev -- id -u` 로 직접 확인해 두자.

## Q12 ServiceAccount 와 토큰 자동 마운트

```bash
kubectl create serviceaccount app-sa -n dev
```

```yaml
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 86400"]
```

자주 틀리는 곳

- `automountServiceAccountToken` 은 **파드 spec 레벨** 필드다(컨테이너 아래가 아니다).
- SA 쪽에 걸어도 효과는 같지만, 문제가 "파드 스펙에서 꺼라"고 지정했으므로 파드에 걸어야
  스펙 항목(1점)을 받는다.
- 확인은 `kubectl exec sa-pod -n dev -- ls /var/run/secrets/kubernetes.io/serviceaccount` —
  "No such file or directory" 가 정답 상태다.

## Q13 리소스 요청·상한 — Quota 안에서

```bash
kubectl create deploy worker -n batch --image=busybox:1.36 --replicas=2 --dry-run=client -o yaml > worker.yaml
# command 와 resources 를 채워 apply
```

```yaml
resources:
  requests: { cpu: 100m, memory: 64Mi }
  limits: { cpu: 200m, memory: 128Mi }
```

자주 틀리는 곳

- **이 문제의 존재 이유**: ResourceQuota 가 있는 네임스페이스에서는 requests 없는 파드가
  아예 거부된다. Deployment 는 만들어져도 파드가 0 개면 `kubectl get events -n batch` 에
  `failed quota` 가 남아 있다.
- 값은 문제 그대로: `100m` 을 `0.1` 로 써도 쿠버네티스는 같게 보지만, 채점은 정규화된
  문자열(100m)을 비교하므로 문제의 표기를 그대로 쓰는 것이 안전하다.

## Q14 Service — ClusterIP 와 NodePort

```bash
kubectl expose deploy frontend -n prod --name=frontend-svc --port=80 --target-port=80
kubectl expose deploy frontend -n prod --name=frontend-np --port=80 --target-port=80 --type=NodePort \
  --dry-run=client -o yaml > np.yaml
# ports[0] 에 nodePort: 30080 추가 후 apply
```

자주 틀리는 곳

- `expose` 는 nodePort 값을 지정할 수 없다 — dry-run YAML 에 `nodePort: 30080` 을 손으로 넣는다.
- 셀렉터를 손으로 쓸 때 `app: frontend` 가 아니면 엔드포인트가 비고, 통신 항목 3점이 전부 날아간다.
- 클러스터 안 검증: `kubectl exec client -n dev -- wget -qO- http://frontend-svc.prod.svc.cluster.local`.

## Q15 Ingress 리소스 작성

컨트롤러가 없어도 리소스는 완전한 규격으로 쓴다.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: frontend-svc, port: { number: 80 } } }
          - path: /shop
            pathType: Prefix
            backend: { service: { name: shop-svc, port: { number: 80 } } }
```

자주 틀리는 곳

- `pathType` 은 필수 필드다 — 빼면 apply 가 거부된다. 문제가 Prefix 를 지정했다.
- `port: { number: 80 }` 구조를 `port: 80` 으로 줄이면 스키마 오류다.
- 두 경로를 **같은 host 규칙 안에** 넣어야 한다. host 를 두 번 쓰면 규칙이 갈라져도 채점은 통과하지만
  한 규칙이 정석이다.

## Q16 NetworkPolicy — 지정 클라이언트만 허용

대상 파드를 고르고(from 이 아니라 podSelector), 허용원을 from 에 적는다.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: cache-guard, namespace: dev }
spec:
  podSelector:
    matchLabels: { app: cache }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: client }
      ports:
        - { protocol: TCP, port: 80 }
```

자주 틀리는 곳

- `podSelector`(대상)와 `from.podSelector`(허용원)를 바꿔 쓰면 정반대 정책이 된다.
- NetworkPolicy 는 선택된 파드에 대해 **명시된 것 외 전부 차단**이다 — deny 규칙을 따로 쓸 필요 없다.
- 이 클러스터는 정책을 실제로 강제한다(kube-router). 제출 전에
  `kubectl exec intruder -n dev -- wget -T2 -qO- http://<cache IP>` 가 **실패하는지** 직접 확인해 보자.
