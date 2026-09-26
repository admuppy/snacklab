# Deployment 와 롤아웃

**Deployment** 는 파드 집합의 원하는 상태(replicas·이미지)를 선언하면 컨트롤러가 그 상태로
수렴시키고, 이미지 변경 시 **무중단 롤링 업데이트** 와 **롤백** 을 관리해 주는 워크로드다.

이 랩은 파드 안에 뜬 **당신 전용 단일노드 k3s 클러스터** 에서 진행한다. 터미널에서 바로
`kubectl` 을 쓸 수 있고(`k` 별칭·자동완성 설정됨), `KUBECONFIG` 은 이미 잡혀 있다.

노드 확인:

```bash
kubectl get nodes          # Ready 노드 1개
```

- `kubectl get <리소스>` — 리소스 목록을 표로 보여 주는 가장 기본 조회 명령이다.
- `nodes` — 클러스터에 참여한 노드(머신). `STATUS` 가 `Ready` 여야 파드가 배치된다.

현재 컨텍스트 확인:

```bash
kubectl config current-context
```

- `kubectl config` — kubeconfig 파일(접속 대상 클러스터·사용자 정보)을 다루는 하위 명령.
- `current-context` — 지금 kubectl 이 명령을 보내는 컨텍스트(클러스터+사용자+네임스페이스 묶음) 이름을 출력한다.

> 참고: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Deployment 생성 (3 레플리카)

`nginx:1.25` 이미지로 레플리카 3개짜리 Deployment `web` 을 만든다.

Deployment 생성:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — YAML 없이 명령형으로 `web` Deployment 를 만든다. 파드에는 `app=web` 레이블이 자동으로 붙는다.
- `--image=nginx:1.25` — 파드 템플릿의 컨테이너 이미지(`이름:태그`).
- `--replicas=3` — 항상 유지할 파드 수(`spec.replicas`).

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/web            # 모두 Ready 까지 대기
```

- `kubectl rollout status` — 롤아웃이 끝날 때까지(새 파드가 모두 Ready) 기다리며 진행 상황을 출력한다.
- `deploy/web` — `<종류>/<이름>` 형식의 리소스 지정. `deploy` 는 `deployment` 의 축약형이다.

Deployment 상태 확인:

```bash
kubectl get deploy web
```

- `READY` — 준비된 파드/원하는 파드 수, `UP-TO-DATE` — 최신 템플릿으로 만들어진 파드 수, `AVAILABLE` — 서비스 가능한 파드 수.

파드 목록 확인:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — 레이블 셀렉터. `app=web` 레이블이 붙은 파드만 고른다.
- `-o wide` — 파드 IP·배치된 노드 같은 추가 열까지 보여 준다.

`kubectl get deploy web` 의 `READY` 열이 `3/3` 이면 성공이다. ReplicaSet 이 파드 3개를
만들었는지 `kubectl get rs` 로도 확인해 보라.

## 2. 롤링 업데이트

이미지를 `nginx:1.26` 으로 올린다. Deployment 는 새 ReplicaSet 을 만들고 파드를 몇 개씩
교체하며(기본 `maxUnavailable=25%`, `maxSurge=25%`) 서비스 중단 없이 갈아끼운다.

이미지 교체:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # 모든 컨테이너 이미지 교체
```

- `kubectl set image deploy/web <컨테이너>=<이미지>` — 파드 템플릿의 이미지만 바꾼다. 템플릿이 바뀌면 새 롤아웃이 시작된다.
- `'*=nginx:1.26'` — `*` 는 모든 컨테이너를 뜻한다. 셸이 `*` 를 파일명으로 펼치지 않도록 작은따옴표로 감쌌다.

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/web             # 롤아웃 완료까지 대기
```

이벤트로 교체 과정 확인:

```bash
kubectl describe deploy web | grep -A2 Events # 이벤트로 교체 과정 확인
```

- `kubectl describe` — 리소스의 상세 정보와 최근 이벤트를 사람이 읽기 좋게 출력한다.
- `| grep -A2 Events` — 출력에서 `Events` 줄과 그 뒤(After) 2줄만 걸러 본다. 구/신 ReplicaSet 의 스케일 조정 기록이 보인다.

ReplicaSet 확인:

```bash
kubectl get rs                                # 구/신 ReplicaSet 공존 → 신규만 3개
```

- `rs` — ReplicaSet 의 축약형. Deployment 는 이미지(템플릿)가 바뀔 때마다 새 ReplicaSet 을 만들고, 구 ReplicaSet 은 0 으로 줄여 롤백용으로 남겨 둔다.

`kubectl rollout status` 가 `successfully rolled out` 을 출력하면 완료다.

> 참고: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. 롤백

방금 배포에 문제가 있었다고 치고 **직전 리비전으로 되돌린다.** Deployment 는 리비전
히스토리를 보관하므로 즉시 롤백할 수 있다.

리비전 목록 확인:

```bash
kubectl rollout history deploy/web           # 리비전 목록
```

- `kubectl rollout history` — Deployment 가 보관 중인 리비전(템플릿 변경 이력) 목록을 보여 준다.
- 특정 리비전의 내용은 `--revision=<N>` 을 붙여 확인한다.

직전 리비전으로 롤백:

```bash
kubectl rollout undo deploy/web              # 직전 리비전(nginx:1.25)으로 롤백
```

- `kubectl rollout undo` — 직전 리비전의 파드 템플릿으로 되돌리는 새 롤아웃을 시작한다. 롤백도 하나의 새 리비전으로 기록된다.

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/web
```

현재 이미지 확인:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — 출력 중 원하는 필드만 JSONPath 식으로 뽑는다. `{.spec.template.spec.containers[0].image}` 는 첫 번째 컨테이너의 이미지.
- `; echo` — jsonpath 출력에는 줄바꿈이 없어서 프롬프트가 붙지 않게 줄을 바꿔 준다.

이미지가 다시 `nginx:1.25` 로 돌아오고 리비전이 하나 더 쌓이면 성공이다. 특정 리비전으로
되돌리려면 `kubectl rollout undo deploy/web --to-revision=<N>` 을 쓴다.

> 참고: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
