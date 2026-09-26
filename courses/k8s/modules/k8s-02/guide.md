# Service 와 클러스터 네트워킹

파드는 언제든 죽고 새 IP 로 다시 뜬다. **Service** 는 라벨 셀렉터로 파드 집합을 골라 안정적인
가상 IP·DNS 이름·부하분산을 제공한다. 이 랩에서는 이미 떠 있는 Deployment `web`(라벨
`app=web`, 2 레플리카)을 세 가지 Service 타입으로 노출한다.

Deployment 확인:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — 노출할 대상 Deployment 가 있는지, 파드가 모두 `READY` 인지 확인한다.

백엔드 파드 확인:

```bash
kubectl get pods -l app=web -o wide     # 백엔드 파드 IP 확인
```

- `-l app=web` — Service 셀렉터가 고르게 될 바로 그 라벨로 파드를 조회한다.
- `-o wide` — 파드 IP 열이 보인다. 나중에 Service 엔드포인트와 비교해 보자.

> 참고: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. ClusterIP 로 노출

기본 타입 **ClusterIP** — 클러스터 내부에서만 접근 가능한 가상 IP 를 만든다. Service 이름
`web`, 포트 80.

Service 생성:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — Deployment 의 파드 셀렉터(`app=web`)를 그대로 가져와 Service 를 만든다.
- `--name=web` — 만들 Service 이름. 이 이름이 곧 DNS 이름이 된다.
- `--port=80` — Service 가 받는 포트, `--target-port=80` — 트래픽을 넘길 컨테이너 포트.
- `--type` 을 생략하면 기본값 `ClusterIP` 다.

Service 확인:

```bash
kubectl get svc web
```

- `svc` 는 `service` 의 축약형. `CLUSTER-IP` 열이 클러스터 내부에서만 쓰이는 가상 IP 다.

엔드포인트 확인:

```bash
kubectl get endpoints web           # 셀렉터가 고른 파드 IP:포트 목록
```

- `endpoints` — Service 가 실제로 트래픽을 보내는 백엔드(파드 IP:포트) 목록. 셀렉터에 맞는 **Ready** 파드만 들어간다.

내부에서 접근 테스트:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — 테스트용 일회성 파드 `t` 를 띄운다.
- `--restart=Never --rm -it` — 재시작 없이 한 번만 실행하고, 터미널을 붙여(`-it`) 결과를 본 뒤 끝나면 파드를 지운다(`--rm`).
- `--` 뒤는 컨테이너 안에서 실행할 명령이다. 줄 끝 `\` 는 다음 줄로 이어지는 한 명령이라는 뜻.
- `wget -qO- <URL>` — 조용히(`-q`) 받아 파일 대신 표준출력(`-O-`)으로 보여 준다.
- `web.default.svc.cluster.local` — `<서비스>.<네임스페이스>.svc.cluster.local` 형식의 Service DNS 이름.

`kubectl get endpoints web` 에 파드 IP 가 채워지면 라우팅이 성립한 것이다. 엔드포인트가
비어 있다면 셀렉터(`app=web`)가 파드 라벨과 안 맞는 것.

## 2. NodePort 로 외부 노출

**NodePort** 는 모든 노드의 고정 포트(기본 30000–32767)를 열어 클러스터 밖에서도 접근하게
한다. Service `web-np` 를 만든다.

NodePort Service 생성:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — ClusterIP 에 더해 **모든 노드의 같은 포트**(30000–32767 중 자동 할당)를 열어 클러스터 밖에서 접근하게 한다.
- `--name=web-np` — 앞의 `web` Service 와 겹치지 않게 다른 이름을 준다.

할당된 포트 확인:

```bash
kubectl get svc web-np                          # PORT(S) 열의 80:3xxxx/TCP
```

- `PORT(S)` 의 `80:3xxxx/TCP` — 앞은 Service 포트, 뒤가 노드에 열린 nodePort 다.

nodePort 값을 변수에 저장:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — 명령 치환. 괄호 안 명령의 출력을 셸 변수 `np` 에 담는다.
- `{.spec.ports[0].nodePort}` — 첫 번째 포트 항목의 nodePort 값만 뽑는 JSONPath.

노드에서 직접 접근:

```bash
curl -s http://127.0.0.1:$np | head -1          # 노드(=이 파드)에서 직접 접근
```

- `curl -s` — 진행률 표시 없이(silent) HTTP 요청을 보낸다. `$np` 자리에 앞에서 저장한 nodePort 가 들어간다.
- `127.0.0.1` — 이 랩에선 터미널이 곧 노드이므로 노드 자신의 주소로 접근한다.
- `| head -1` — 응답의 첫 줄만 본다.

`80:3xxxx/TCP` 처럼 nodePort 가 할당되고 curl 이 nginx 응답을 주면 성공이다.

## 3. Headless Service 와 DNS

`clusterIP: None` 인 **Headless Service** 는 가상 IP·프록시 없이, DNS 질의에 **각 파드의 IP**
를 그대로 A 레코드로 돌려준다. StatefulSet 의 파드별 접근 등에 쓰인다.

Headless Service 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: web-h, namespace: default }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `clusterIP: None` — 가상 IP 를 만들지 않는 Headless Service 선언. `selector` 로 고른 파드 IP 가 DNS 에 그대로 올라간다.

CLUSTER-IP 확인:

```bash
kubectl get svc web-h                 # CLUSTER-IP 가 None
```

- `CLUSTER-IP` 가 `None` 이면 Headless 다. kube-proxy 부하분산 대상이 아니다.

DNS 질의 테스트:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # 파드 개수만큼 A 레코드
```

- `kubectl run t --image=busybox:1.36` — 테스트용 일회성 파드 `t` 를 띄운다.
- `--restart=Never --rm -it` — 재시작 없이 한 번만 실행하고, 터미널을 붙여(`-it`) 결과를 본 뒤 끝나면 파드를 지운다(`--rm`).
- `--` 뒤는 컨테이너 안에서 실행할 명령이다. 줄 끝 `\` 는 다음 줄로 이어지는 한 명령이라는 뜻.
- `nslookup <이름>` — DNS 에 이름을 질의해 A 레코드(IP)를 출력한다. Headless 는 파드 수만큼 IP 가 나온다.

`CLUSTER-IP` 가 `None` 이고 nslookup 이 파드 수만큼 IP 를 반환하면 성공이다.

> 참고: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
