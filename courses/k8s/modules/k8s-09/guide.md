# NetworkPolicy — 마이크로세그멘테이션

기본적으로 클러스터 안 모든 파드는 서로 통신할 수 있다. **NetworkPolicy** 는 파드 수준
방화벽으로, 라벨로 고른 파드에 대해 **어떤 출처(from)/목적지(to)** 의 트래픽을 허용할지
정한다. 규칙은 **허용(allow) 목록** 이다 — 어떤 파드를 정책이 "선택" 하는 순간 그 파드는
명시적으로 허용된 트래픽만 받는다(나머지는 거부).

이 랩엔 서버 `web`(+Service `web`)와 클라이언트 파드 `client`(라벨 `app=client`)가 이미 떠
있다. k3s 는 NetworkPolicy 를 실제로 강제한다.

web 파드 확인:

```bash
kubectl get pod -l app=web -o wide
```

client 파드 확인:

```bash
kubectl get pod client -o wide
```

> 참고: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. 기본 연결 확인

정책이 없을 때 client 에서 web 으로 접속되는지 확인하고, 그 결과를 베이스라인 기록으로
`~/work/baseline.txt` 에 남긴다(2·3단계에서 차단·허용과 비교할 근거).

client → web 접속 확인:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx 응답
```

기록용 디렉터리 생성:

```bash
mkdir -p ~/work
```

베이스라인 응답 저장:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

저장 내용 확인:

```bash
head -1 ~/work/baseline.txt
```

nginx HTML 첫 줄(`<!DOCTYPE html>`)이 나오면 열려 있는 것이다.

## 2. 기본 거부 (default-deny)

`web` 파드를 선택하되 **ingress 규칙을 하나도 두지 않는** 정책을 만든다. 선택된 파드로의
모든 인바운드가 차단된다.

default-deny 정책 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
```

차단 확인 (타임아웃 예상):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # 타임아웃(차단)
```

`wget` 이 타임아웃으로 실패하면 정책이 트래픽을 막은 것이다.

## 3. 출처 기반 허용

이제 `app=client` 라벨을 가진 파드에서 오는 80 포트만 허용하는 정책을 추가한다. 정책은
누적되므로 default-deny 위에 이 허용이 얹혀 client 만 통과한다.

허용 정책 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
```

client → web 재확인:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # 다시 성공
```

client → web 이 다시 열리면 성공이다. `app=client` 라벨이 없는 다른 파드로 시험하면 여전히
막힌다 — 그게 마이크로세그멘테이션이다.

> 참고: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
