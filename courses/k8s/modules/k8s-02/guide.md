# Service 와 클러스터 네트워킹

파드는 언제든 죽고 새 IP 로 다시 뜬다. **Service** 는 라벨 셀렉터로 파드 집합을 골라 안정적인
가상 IP·DNS 이름·부하분산을 제공한다. 이 랩에서는 이미 떠 있는 Deployment `web`(라벨
`app=web`, 2 레플리카)을 세 가지 Service 타입으로 노출한다.

Deployment 확인:

```bash
kubectl get deploy web
```

백엔드 파드 확인:

```bash
kubectl get pods -l app=web -o wide     # 백엔드 파드 IP 확인
```

> 참고: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. ClusterIP 로 노출

기본 타입 **ClusterIP** — 클러스터 내부에서만 접근 가능한 가상 IP 를 만든다. Service 이름
`web`, 포트 80.

Service 생성:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

Service 확인:

```bash
kubectl get svc web
```

엔드포인트 확인:

```bash
kubectl get endpoints web           # 셀렉터가 고른 파드 IP:포트 목록
```

내부에서 접근 테스트:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

`kubectl get endpoints web` 에 파드 IP 가 채워지면 라우팅이 성립한 것이다. 엔드포인트가
비어 있다면 셀렉터(`app=web`)가 파드 라벨과 안 맞는 것.

## 2. NodePort 로 외부 노출

**NodePort** 는 모든 노드의 고정 포트(기본 30000–32767)를 열어 클러스터 밖에서도 접근하게
한다. Service `web-np` 를 만든다.

NodePort Service 생성:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

할당된 포트 확인:

```bash
kubectl get svc web-np                          # PORT(S) 열의 80:3xxxx/TCP
```

nodePort 값을 변수에 저장:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

노드에서 직접 접근:

```bash
curl -s http://127.0.0.1:$np | head -1          # 노드(=이 파드)에서 직접 접근
```

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

CLUSTER-IP 확인:

```bash
kubectl get svc web-h                 # CLUSTER-IP 가 None
```

DNS 질의 테스트:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # 파드 개수만큼 A 레코드
```

`CLUSTER-IP` 가 `None` 이고 nslookup 이 파드 수만큼 IP 를 반환하면 성공이다.

> 참고: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
