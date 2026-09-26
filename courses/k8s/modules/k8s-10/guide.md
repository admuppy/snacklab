# 종합 — 고장난 배포 살리기

전자상거래 앱 두 개(`shop`, `cart`)가 배포됐는데 **아무것도 뜨지 않는다.** 세 곳에 서로 다른
장애가 심어져 있다. 이 캡스톤은 새 개념을 배우는 게 아니라, 지금까지 익힌 진단 도구
—`kubectl get`, `describe`, `logs`, `get events`— 로 **스스로 원인을 찾아 고치는** 훈련이다.

먼저 전체를 훑어라:

전체 리소스 훑기:

```bash
kubectl get deploy,pods,svc
```

- 쉼표로 여러 리소스 종류를 한 번에 조회한다. Deployment 의 `READY`, 파드의 `STATUS`, Service 목록을 함께 보며 이상한 곳을 찾는다.

최근 이벤트 확인:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — 네임스페이스에서 일어난 이벤트(스케줄·이미지 풀·실패 등).
- `--sort-by=.lastTimestamp` — 마지막 발생 시각 순으로 정렬, `| tail -20` — 가장 최근 20줄만.

> 참고: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. 이미지 풀 실패 수리

`shop` 파드가 `ImagePullBackOff`/`ErrImagePull` 이다. 원인을 확인한다.

shop 파드 상태 확인:

```bash
kubectl get pods -l app=shop
```

- `STATUS` 열의 `ImagePullBackOff`/`ErrImagePull` — 노드가 이미지를 받지 못해 재시도 간격을 늘리며 대기 중이라는 뜻.

이벤트에서 원인 확인:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # "not found" 태그가 보인다
```

- `describe` 맨 아래 `Events` 가 실패 원인을 가장 직접적으로 알려 준다. `grep -A5 -i events` 로 그 부분만 본다.

현재 이미지 태그 확인:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — Deployment 가 파드를 만들 때 쓰는 이미지 이름:태그.

존재하지 않는 이미지 태그가 문제다. 유효한 태그로 고친다:

이미지 태그 교체:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — 컨테이너 이름 `web` 의 이미지를 교체한다. 템플릿이 바뀌므로 새 파드가 롤아웃된다.

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/shop
```

- 새 파드가 모두 Ready 가 될 때까지 기다린다. 끝나지 않으면 `Ctrl+C` 후 다시 `describe` 로 원인을 본다.

`shop` 이 2/2 Ready 가 되면 ① 해결.

## 2. 서비스 셀렉터 수리

파드는 이제 떴는데 Service `shop` 이 트래픽을 못 보낸다. 엔드포인트가 비어 있는지 본다.

엔드포인트 확인:

```bash
kubectl get endpoints shop            # <none> — 아무 파드도 안 붙음
```

- `ENDPOINTS` 가 `<none>` 이면 Service 셀렉터에 맞는 Ready 파드가 하나도 없다는 뜻이다.

Service 셀렉터 확인:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX (오타)
```

- `{.spec.selector}` — Service 가 파드를 고르는 라벨 조건을 JSON 으로 본다.

실제 파드 라벨 확인:

```bash
kubectl get pods -l app=shop --show-labels                  # 실제 라벨은 app=shop
```

- `--show-labels` — 각 파드에 붙은 레이블 전체를 `LABELS` 열로 보여 준다. 셀렉터와 한 글자씩 비교해 보자.

Service 셀렉터가 파드 라벨과 안 맞는다. 셀렉터를 고친다:

셀렉터 수정:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — 리소스의 일부 필드만 즉석에서 고친다.
- `--type=merge` — `-p` 로 준 JSON 을 기존 오브젝트에 병합(JSON merge patch)한다.
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — 바꿀 부분만 적은 패치. 셸이 해석하지 않도록 작은따옴표로 감싼다.

엔드포인트 재확인:

```bash
kubectl get endpoints shop            # 이제 파드 IP 가 채워짐
```

엔드포인트가 채워지면 ② 해결.

## 3. 누락된 ConfigMap 수리

`cart` 파드는 `CreateContainerConfigError` 로 멈춰 있다. 이유를 본다.

cart 파드 상태 확인:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — 이미지는 받았지만 컨테이너 설정(참조하는 ConfigMap/Secret 등)을 만들 수 없는 상태.

이벤트에서 원인 확인:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- Events 에서 어떤 오브젝트가 없는지(`configmap "cart-config" not found`) 이름까지 확인할 수 있다.

참조 중인 envFrom 확인:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — 컨테이너가 환경변수로 통째로 가져오는 ConfigMap/Secret 참조 목록.

없는 ConfigMap `cart-config` 를 참조하고 있다. 만들어 주면 kubelet 이 파드를 정상 기동한다:

ConfigMap 생성:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- `--from-literal=키=값` 을 두 번 줘서 키 두 개짜리 ConfigMap 을 만든다. 생성되면 kubelet 이 재시도하다가 컨테이너를 띄운다.

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/cart
```

`cart` 가 1/1 Ready 가 되면 ③ 해결 — 세 장애를 모두 살렸다.

```bash
kubectl get deploy,svc,endpoints      # 최종 확인
```

- 세 장애가 모두 풀렸는지 Deployment READY, Service, 엔드포인트를 한 번에 확인한다.
