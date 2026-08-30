# 종합 — 고장난 배포 살리기

전자상거래 앱 두 개(`shop`, `cart`)가 배포됐는데 **아무것도 뜨지 않는다.** 세 곳에 서로 다른
장애가 심어져 있다. 이 캡스톤은 새 개념을 배우는 게 아니라, 지금까지 익힌 진단 도구
—`kubectl get`, `describe`, `logs`, `get events`— 로 **스스로 원인을 찾아 고치는** 훈련이다.

먼저 전체를 훑어라:

전체 리소스 훑기:

```bash
kubectl get deploy,pods,svc
```

최근 이벤트 확인:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

> 참고: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. 이미지 풀 실패 수리

`shop` 파드가 `ImagePullBackOff`/`ErrImagePull` 이다. 원인을 확인한다.

shop 파드 상태 확인:

```bash
kubectl get pods -l app=shop
```

이벤트에서 원인 확인:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # "not found" 태그가 보인다
```

현재 이미지 태그 확인:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

존재하지 않는 이미지 태그가 문제다. 유효한 태그로 고친다:

이미지 태그 교체:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/shop
```

`shop` 이 2/2 Ready 가 되면 ① 해결.

## 2. 서비스 셀렉터 수리

파드는 이제 떴는데 Service `shop` 이 트래픽을 못 보낸다. 엔드포인트가 비어 있는지 본다.

엔드포인트 확인:

```bash
kubectl get endpoints shop            # <none> — 아무 파드도 안 붙음
```

Service 셀렉터 확인:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX (오타)
```

실제 파드 라벨 확인:

```bash
kubectl get pods -l app=shop --show-labels                  # 실제 라벨은 app=shop
```

Service 셀렉터가 파드 라벨과 안 맞는다. 셀렉터를 고친다:

셀렉터 수정:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

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

이벤트에서 원인 확인:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

참조 중인 envFrom 확인:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

없는 ConfigMap `cart-config` 를 참조하고 있다. 만들어 주면 kubelet 이 파드를 정상 기동한다:

ConfigMap 생성:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

롤아웃 완료 대기:

```bash
kubectl rollout status deploy/cart
```

`cart` 가 1/1 Ready 가 되면 ③ 해결 — 세 장애를 모두 살렸다.

```bash
kubectl get deploy,svc,endpoints      # 최종 확인
```
