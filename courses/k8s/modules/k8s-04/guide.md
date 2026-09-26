# 프로브와 자가치유

kubelet 은 세 가지 프로브로 컨테이너 상태를 감시한다. **livenessProbe** 가 실패하면
컨테이너를 **재시작**(자가치유)하고, **readinessProbe** 가 실패하면 파드를 Service
엔드포인트에서 **잠시 빼서** 트래픽을 안 보낸다. (startupProbe 는 느린 기동 보호용.)

이 랩의 컨테이너는 시작 시 `/tmp/healthy` 를 만들고 **30초 뒤 지운다.** 두 프로브 모두
그 파일을 확인하므로, 30초 후 liveness 가 실패해 자동 재시작이 일어나는 걸 관찰한다.

> 참고: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. livenessProbe 정의

아래 Deployment `web` 을 배포한다. `livenessProbe` 는 `cat /tmp/healthy` 를 5초마다 실행하고
1회 실패 시 컨테이너를 재시작한다.

Deployment 배포:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `livenessProbe.exec.command` — 컨테이너 안에서 이 명령을 실행해 종료코드 0 이면 성공으로 본다(`httpGet`, `tcpSocket` 방식도 있다).
- `initialDelaySeconds` — 첫 검사 전 대기, `periodSeconds` — 검사 간격, `failureThreshold: 1` — 1회 실패로 곧바로 재시작.
- `args` 의 셸 스크립트가 30초 뒤 `/tmp/healthy` 를 지워 일부러 장애를 만든다.

파드 확인:

```bash
kubectl get pod -l app=web
```

- `READY` 는 readiness 결과, `RESTARTS` 는 liveness 실패로 인한 재시작 횟수를 보여 준다.

## 2. readinessProbe 정의

위 매니페스트엔 `readinessProbe` 도 함께 들어 있다. 파드가 준비되면 `READY 1/1` 이 된다.

파드 상태 확인:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — 파드 IP·노드·readiness gate 등 추가 열을 함께 본다.

readiness 프로브 설정 확인:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — 라벨로 고른 파드의 상세 정보(프로브 설정 포함)를 출력한다.
- `grep -A3 -i readiness` — 대소문자 무시(`-i`)로 `readiness` 줄과 그 뒤 3줄을 본다.

`readinessProbe` 가 통과하는 동안 파드는 Ready 상태이고, 실패하면(파일이 지워진 뒤) 잠시
`READY 0/1` 로 빠졌다가 재시작 후 다시 Ready 로 돌아온다.

## 3. 장애 유발 → 자동 재시작

파일이 사라지는 30초 뒤부터 liveness 가 실패하기 시작한다. 파드를 지켜보면 `RESTARTS` 가
올라간다.

파드 관찰:

```bash
kubectl get pod -l app=web -w        # RESTARTS 가 0 → 1 로 (Ctrl+C 로 종료)
```

- `-w` (`--watch`) — 한 번 출력하고 끝나지 않고 변경될 때마다 새 줄을 출력한다. `Ctrl+C` 로 빠져나온다.

프로브 이벤트 확인:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` 는 기본 정규식의 OR. 프로브 실패(`Liveness`), 컨테이너 종료(`Killing`), 재기동(`Started`) 이벤트를 한꺼번에 본다.

`RESTARTS` 가 1 이상이 되면 자가치유가 동작한 것이다. 직접 앞당기려면
`kubectl exec deploy/web -- rm -f /tmp/healthy` 로 파일을 지워도 된다.

> 참고: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
