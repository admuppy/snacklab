# 리소스 요청·제한과 QoS

컨테이너에 **requests**(스케줄러가 자리를 예약하는 최소량)와 **limits**(넘으면 CPU 는
스로틀, 메모리는 OOM Kill 되는 상한)를 건다. 둘의 조합으로 파드는 세 **QoS 클래스** 중
하나가 되고, 노드가 압박받을 때 **축출(eviction) 순서** 가 정해진다: `BestEffort` →
`Burstable` → `Guaranteed` 순으로 먼저 밀려난다.

> 참고: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. Guaranteed QoS 파드

모든 컨테이너에 **cpu·memory 의 requests 와 limits 를 똑같이** 주면 `Guaranteed` 가 된다.
가장 보호받는 등급이다.

파드 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `resources.requests` — 스케줄러가 노드에 예약하는 최소량, `limits` — 넘을 수 없는 상한.
- `cpu: "250m"` — 밀리코어 단위(1000m = CPU 1개), `memory: "64Mi"` — 2진 단위 메비바이트.
- requests 와 limits 를 똑같이 주면 `Guaranteed` 가 된다.

QoS 클래스 확인:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — kubelet 이 판정해 기록한 QoS 클래스(`Guaranteed`/`Burstable`/`BestEffort`)만 뽑아 본다.

## 2. Burstable QoS 파드

requests 는 있지만 limits 가 더 크거나 일부만 있으면 `Burstable` 이다. 평소엔 requests 만큼
쓰다가 여유가 있으면 limits 까지 치솟을(burst) 수 있다.

파드 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF
```

- requests(100m/32Mi)보다 limits(500m/128Mi)가 크다 → 평소엔 적게 예약하고 여유가 있을 때만 limits 까지 쓴다(`Burstable`).

QoS 클래스 확인:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — kubelet 이 판정해 기록한 QoS 클래스(`Guaranteed`/`Burstable`/`BestEffort`)만 뽑아 본다.

> requests·limits 를 아예 안 주면 `BestEffort` 가 된다 — 확인: `kubectl run be --image=nginx:1.26`
> 후 `kubectl get pod be -o jsonpath='{.status.qosClass}'`.

## 3. LimitRange 기본값

**LimitRange** 는 네임스페이스에 기본 requests/limits 를 정해, 개발자가 깜빡해도 파드가
자원 상한을 갖게 한다. **반드시 파드보다 먼저** 만들어야 기본값이 주입된다.

LimitRange 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # limits 기본
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # requests 기본
EOF
```

- `kind: LimitRange` — 이 네임스페이스에 만들어지는 컨테이너에 적용되는 자원 규칙.
- `default` — limits 를 안 쓴 컨테이너에 채울 limits 기본값, `defaultRequest` — requests 기본값.
- 기본값은 파드 **생성 시점**에 주입되므로 이미 있는 파드에는 소급되지 않는다.

limits 를 명시하지 않은 파드 생성 — LimitRange 가 기본값을 채워 준다:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <이름> --image=<이미지>` — Deployment 없이 파드 하나를 바로 만든다. 여기선 resources 를 일부러 비워 둔다.

주입된 resources 확인:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — 첫 컨테이너의 resources 블록 전체를 JSON 으로 본다. 직접 쓰지 않은 값이 LimitRange 에 의해 채워져 있다.

파드 `defaulted` 의 `resources.limits.memory` 가 `128Mi` 로 채워져 있으면 성공이다.

> 참고: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
