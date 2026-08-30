# Deployment 와 롤아웃

**Deployment** 는 파드 집합의 원하는 상태(replicas·이미지)를 선언하면 컨트롤러가 그 상태로
수렴시키고, 이미지 변경 시 **무중단 롤링 업데이트** 와 **롤백** 을 관리해 주는 워크로드다.

이 랩은 파드 안에 뜬 **당신 전용 단일노드 k3s 클러스터** 에서 진행한다. 터미널에서 바로
`kubectl` 을 쓸 수 있고(`k` 별칭·자동완성 설정됨), `KUBECONFIG` 은 이미 잡혀 있다.

노드 확인:

```bash
kubectl get nodes          # Ready 노드 1개
```

현재 컨텍스트 확인:

```bash
kubectl config current-context
```

> 참고: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Deployment 생성 (3 레플리카)

`nginx:1.25` 이미지로 레플리카 3개짜리 Deployment `web` 을 만든다.

Deployment 생성:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/web            # 모두 Ready 까지 대기
```

Deployment 상태 확인:

```bash
kubectl get deploy web
```

파드 목록 확인:

```bash
kubectl get pods -l app=web -o wide
```

`kubectl get deploy web` 의 `READY` 열이 `3/3` 이면 성공이다. ReplicaSet 이 파드 3개를
만들었는지 `kubectl get rs` 로도 확인해 보라.

## 2. 롤링 업데이트

이미지를 `nginx:1.26` 으로 올린다. Deployment 는 새 ReplicaSet 을 만들고 파드를 몇 개씩
교체하며(기본 `maxUnavailable=25%`, `maxSurge=25%`) 서비스 중단 없이 갈아끼운다.

이미지 교체:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # 모든 컨테이너 이미지 교체
```

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/web             # 롤아웃 완료까지 대기
```

이벤트로 교체 과정 확인:

```bash
kubectl describe deploy web | grep -A2 Events # 이벤트로 교체 과정 확인
```

ReplicaSet 확인:

```bash
kubectl get rs                                # 구/신 ReplicaSet 공존 → 신규만 3개
```

`kubectl rollout status` 가 `successfully rolled out` 을 출력하면 완료다.

> 참고: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. 롤백

방금 배포에 문제가 있었다고 치고 **직전 리비전으로 되돌린다.** Deployment 는 리비전
히스토리를 보관하므로 즉시 롤백할 수 있다.

리비전 목록 확인:

```bash
kubectl rollout history deploy/web           # 리비전 목록
```

직전 리비전으로 롤백:

```bash
kubectl rollout undo deploy/web              # 직전 리비전(nginx:1.25)으로 롤백
```

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/web
```

현재 이미지 확인:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

이미지가 다시 `nginx:1.25` 로 돌아오고 리비전이 하나 더 쌓이면 성공이다. 특정 리비전으로
되돌리려면 `kubectl rollout undo deploy/web --to-revision=<N>` 을 쓴다.

> 참고: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
