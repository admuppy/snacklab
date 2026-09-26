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

- `-l app=web` 로 서버 파드를, `-o wide` 로 그 IP 를 본다. NetworkPolicy 도 이 라벨로 파드를 고른다.

client 파드 확인:

```bash
kubectl get pod client -o wide
```

- 클라이언트 파드. `kubectl get pod client --show-labels` 로 `app=client` 라벨을 확인해 두자 — 3단계 허용 규칙의 기준이다.

> 참고: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. 기본 연결 확인

정책이 없을 때 client 에서 web 으로 접속되는지 확인하고, 그 결과를 베이스라인 기록으로
`~/work/baseline.txt` 에 남긴다(2·3단계에서 차단·허용과 비교할 근거).

client → web 접속 확인:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx 응답
```

- `kubectl exec client -- …` — client 파드 **안에서** 요청을 보낸다(출처가 client 가 되도록).
- `wget -q -T 3 -O- http://web` — 3초 타임아웃(`-T 3`)으로 `web` Service 에 요청해 응답을 표준출력(`-O-`)으로 낸다.
- `| head -1` — 응답의 첫 줄만 본다.

기록용 디렉터리 생성:

```bash
mkdir -p ~/work
```

- `mkdir -p` — 중간 경로까지 만들고, 이미 있어도 에러를 내지 않는다.

베이스라인 응답 저장:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> 파일` — 명령의 표준출력을 파일로 저장(덮어쓰기)한다. `kubectl exec` 의 출력은 내 터미널 쪽으로 오므로 파일도 로컬에 생긴다.

저장 내용 확인:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <파일>` — 파일의 첫 줄만 출력한다.

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

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `podSelector` — 정책을 적용할 대상 파드(`app=web`). 빈 셀렉터 `{}` 면 네임스페이스의 모든 파드.
- `policyTypes: [Ingress]` 인데 `ingress:` 규칙이 없다 → 선택된 파드로 들어오는 트래픽을 전부 거부.

차단 확인 (타임아웃 예상):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # 타임아웃(차단)
```

- `-t 1` — 재시도 1회만. 막혀 있으면 3초 뒤 `timed out` 으로 끝난다(거부 패킷 없이 조용히 버려진다).

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

- `ingress[].from[].podSelector` — 같은 네임스페이스에서 `app=client` 라벨을 가진 파드만 출처로 허용한다.
- `ports` — 허용 포트/프로토콜(TCP 80). `from` 과 `ports` 가 한 항목 안에 있으면 둘 다 만족해야 한다.
- 정책은 OR 로 합쳐지므로 default-deny 가 있어도 이 허용이 추가로 적용된다.

client → web 재확인:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # 다시 성공
```

client → web 이 다시 열리면 성공이다. `app=client` 라벨이 없는 다른 파드로 시험하면 여전히
막힌다 — 그게 마이크로세그멘테이션이다.

> 참고: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
