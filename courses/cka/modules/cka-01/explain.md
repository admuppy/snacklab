# 해설

제출 후 만점을 받지 못한 문항에만 아래 해설이 화면에 표시된다.
정답은 하나가 아니다 — 채점은 "결과가 규격대로인가"를 보므로, 아래는 가장 짧은 기준 답이다.

## Q1 RBAC — ServiceAccount·Role·RoleBinding

읽기 전용 신원 만들기는 명령형으로 세 줄이면 끝난다. 시험에서 YAML 을 손으로 쓰면 시간을 버린다.

```bash
kubectl create serviceaccount deploy-bot -n app-prod
kubectl create role pod-reader -n app-prod --verb=get,list,watch --resource=pods,deployments.apps
kubectl create rolebinding deploy-bot-rb -n app-prod --role=pod-reader --serviceaccount=app-prod:deploy-bot
```

자주 틀리는 곳

- `--resource=deployments` 만 쓰면 apiGroup 이 core 로 잡힌다. `deployments.apps` 로 써야 한다.
- `ClusterRole`/`ClusterRoleBinding` 으로 만들면 권한이 다른 네임스페이스까지 새어 감점된다.
- `--serviceaccount=app-prod:deploy-bot` 처럼 **네임스페이스:이름** 형식이어야 한다.

채점은 `kubectl auth can-i --as=system:serviceaccount:app-prod:deploy-bot` 결과로 하므로,
규칙을 어떻게 적었든 **실제 부여된 권한**만 맞으면 된다.

## Q2 CSR 승인과 사용자 권한 부여

```bash
kubectl certificate approve dev-user
kubectl create rolebinding dev-user-view -n app-prod --clusterrole=view --user=dev-user
```

자주 틀리는 곳

- `--serviceaccount=` 로 바인딩하면 User `dev-user` 가 아니라 SA 에 권한이 간다. **`--user=`** 여야 한다.
- `edit`/`admin` 을 바인딩하면 삭제까지 가능해져 감점된다. 읽기 전용은 기본 ClusterRole `view` 다.
- 승인 후 `kubectl get csr dev-user -o jsonpath='{.status.certificate}'` 가 비어 있지 않아야 한다.
  거부(`deny`)한 CSR 은 되돌릴 수 없으니 랩을 다시 시작해야 한다.

## Q3 정적 파드(static pod) 생성

정적 파드는 apiserver 가 아니라 **kubelet 이 디스크의 매니페스트 디렉터리에서** 읽어 띄운다.
k3s 의 경로는 `/var/lib/rancher/k3s/agent/pod-manifests/` 다.

```bash
kubectl run ops-static --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sh -c "sleep 86400" > /tmp/ops-static.yaml
sudo cp /tmp/ops-static.yaml /var/lib/rancher/k3s/agent/pod-manifests/
```

자주 틀리는 곳

- `kubectl apply` 로 만들면 일반 파드다. 채점은 `kubernetes.io/config.source=file` 애너테이션을 본다.
- 미러 파드 이름은 매니페스트의 이름 뒤에 **노드명이 붙는다**(`ops-static-<node>`). 그대로 두면 된다.
- 파일을 놓고 나서 kubelet 이 집어갈 때까지 몇 초 걸린다.

## Q4 ResourceQuota·LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: ops-quota, namespace: ops }
spec:
  hard:
    pods: "5"
    requests.cpu: "1"
    requests.memory: 1Gi
---
apiVersion: v1
kind: LimitRange
metadata: { name: ops-limits, namespace: ops }
spec:
  limits:
    - type: Container
      defaultRequest: { cpu: 100m, memory: 128Mi }
      default: { cpu: 200m, memory: 256Mi }
```

자주 틀리는 곳

- `pods: 5` 처럼 숫자로 쓰면 파싱 오류다 — 쿼터 값은 **문자열**(`"5"`)이어야 한다.
- LimitRange 의 `default` 는 limit, `defaultRequest` 는 request 다. 둘을 바꿔 쓰기 쉽다.
- `type: Container` 여야 한다(`Pod` 이면 다른 의미).

## Q5 Deployment 와 롤아웃 전략

```bash
kubectl create deploy web -n app-prod --image=nginx:1.26 --replicas=3 --dry-run=client -o yaml > web.yaml
```
로 뼈대를 만들고 `strategy` 와 `resources.requests` 만 채워 넣는 것이 가장 빠르다.

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:
    spec:
      containers:
        - name: web
          image: nginx:1.26
          resources: { requests: { cpu: 50m, memory: 64Mi } }
```

자주 틀리는 곳

- `maxUnavailable: 0` 을 빼먹으면 기본값 25% 가 적용돼 감점된다.
- `resources.limits` 가 아니라 **`requests`** 다.
- 이 문항의 `web` 파드는 Q8·Q9 의 채점 대상이기도 하다. 먼저 3개가 Ready 인지 확인하라.

## Q6 DaemonSet 배포

DaemonSet 은 `kubectl create` 로 만들 수 없다. Deployment 뼈대를 뽑아 `kind` 를 바꾸고
`replicas`·`strategy` 를 지우는 것이 시험장의 정석이다.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: ops }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 86400"]
          resources: { requests: { cpu: 10m, memory: 16Mi } }
```

자주 틀리는 곳

- `replicas` 를 남겨두면 DaemonSet 스키마에 없는 필드라 거부된다.
- busybox 는 기본 명령이 즉시 끝나 CrashLoop 에 빠진다. `sleep` 류 명령을 반드시 준다.
- `resources.requests` 의 cpu·memory 를 **둘 다** 적어야 한다.

## Q7 사이드카 컨테이너와 공유 볼륨

핵심은 **같은 볼륨을 두 컨테이너가 같은 경로에 마운트**하는 것이다.

```yaml
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 5; done"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: sidecar
      image: busybox:1.36
      command: ["sh", "-c", "tail -f /var/log/app/app.log"]
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
```

자주 틀리는 곳

- 볼륨을 두 개 만들면 스펙은 그럴듯해도 실제로는 공유가 안 된다. 채점은 sidecar 에서
  `/var/log/app/app.log` 를 **실제로 읽어** 확인한다.
- 두 컨테이너 이름은 `app`, `sidecar` 로 지정돼 있다.

## Q8 Service — ClusterIP 와 NodePort

```bash
kubectl expose deploy web -n app-prod --name=web-svc --port=80 --target-port=80
kubectl expose deploy web -n app-prod --name=web-np --type=NodePort --port=80 --target-port=80
kubectl patch svc web-np -n app-prod --type=merge -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'
```

자주 틀리는 곳

- `nodePort` 는 `expose` 로 지정할 수 없다 — 만든 뒤 patch 하거나 YAML 로 만든다.
- 엔드포인트가 비면 셀렉터가 파드 라벨(`app=web`)과 어긋난 것이다. `kubectl get endpoints web-svc -n app-prod` 로 확인한다.
- 채점은 `client` 파드에서 `web-svc.app-prod.svc.cluster.local` 로 **실제 HTTP 응답**까지 본다.

## Q9 NetworkPolicy 로 트래픽 차단

두 장 필요하다 — 전체 차단(default deny) 한 장과, 예외 허용 한 장.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: app-prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client, namespace: app-prod }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { role: client } }
      ports: [{ protocol: TCP, port: 80 }]
```

자주 틀리는 곳

- `podSelector: {}` 가 "네임스페이스의 모든 파드"라는 뜻이다. 비워두는 것과 생략하는 것은 다르다.
- `from` 에 `- podSelector:` 와 `- namespaceSelector:` 를 **한 항목 안에** 나란히 쓰면 AND 가 된다.
  별개 항목(`-` 두 개)이면 OR 다.
- 채점은 정책 모양뿐 아니라 `client` 는 되고 `intruder` 는 막히는지 실제 통신으로 판정한다.
  Q5 의 `web` 파드가 떠 있어야 이 판정이 가능하다.

## Q10 Ingress 리소스 작성

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web-ing, namespace: app-prod }
spec:
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
```

자주 틀리는 곳

- `pathType` 은 필수 필드다. 빠뜨리면 생성 자체가 거부된다.
- `extensions/v1beta1` 은 오래전에 제거됐다 — `networking.k8s.io/v1` 이다.
- 백엔드는 `serviceName`/`servicePort`(구버전)가 아니라 `service.name`/`service.port.number` 다.

## Q11 PV·PVC 정적 바인딩

정적 바인딩은 **PV 와 PVC 의 storageClassName·accessModes·용량이 서로 맞아야** 붙는다.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 1Gi }
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  hostPath: { path: /mnt/data, type: DirectoryOrCreate }
```
PVC 도 같은 `storageClassName: manual` 과 `ReadWriteOnce`, 1Gi 로 만들고 파드에서 `/data` 에 마운트한다.

자주 틀리는 곳

- PVC 에 `storageClassName` 을 안 적으면 기본 SC(local-path)로 **동적 생성**돼 pv-data 가 아닌 볼륨에 붙는다.
  채점은 `spec.volumeName == pv-data` 까지 본다.
- 이미 잘못 Bound 된 PVC 는 수정이 안 된다. 지우고 다시 만들어야 한다.

## Q12 동적 프로비저닝과 데이터 쓰기

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-dyn, namespace: app-prod }
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources: { requests: { storage: 500Mi } }
```

자주 틀리는 곳

- local-path 는 `WaitForFirstConsumer` 다 — **파드가 뜨기 전에는 Pending 이 정상**이다. PVC 만 만들고
  Bound 를 기다리면 시간을 버린다.
- 용량 단위는 `500Mi`(500M 아님)여야 한다.
- 채점은 볼륨의 `/data/hello.txt` 내용까지 확인한다. 파드가 파일을 쓰게 하거나
  `kubectl exec writer -- sh -c 'echo cka > /data/hello.txt'` 로 직접 넣어도 된다.

## Q13 장애 조치 — 기동하지 않는 Deployment

```bash
kubectl -n broken describe pod -l app=api | tail -20   # ErrImagePull / InvalidImageName
kubectl -n broken set image deploy/api api=nginx:1.26
kubectl -n broken rollout status deploy/api
```

자주 틀리는 곳

- 파드가 Pending 인지 ImagePull 실패인지부터 구분한다. `describe` 의 Events 가 답을 말해 준다.
- 배포를 지우고 새로 만들어도 인정되지만 **이름·네임스페이스·replicas(2)** 는 그대로여야 한다.
- 고친 뒤 옛 ReplicaSet 의 실패 파드가 남아 있으면 감점된다. `rollout status` 로 수렴을 확인하라.

## Q14 장애 조치 — 엔드포인트가 비어 있는 Service

셀렉터와 targetPort **두 곳**이 어긋나 있다. 파드 라벨과 컨테이너 포트를 먼저 확인한다.

```bash
kubectl -n broken get pod --show-labels
kubectl -n broken get svc cache-svc -o yaml | head -30
kubectl -n broken patch svc cache-svc --type=merge \
  -p '{"spec":{"selector":{"app":"cache"},"ports":[{"port":80,"targetPort":80}]}}'
kubectl -n broken get endpoints cache-svc
```

자주 틀리는 곳

- `port` 는 서비스가 여는 포트, `targetPort` 는 컨테이너 포트다. 서비스 포트 80 은 그대로 두어야 한다.
- 엔드포인트가 채워져도 targetPort 가 틀리면 응답이 없다. 채점은 실제 HTTP 응답까지 본다.
- `kubectl edit svc` 로 고쳐도 되지만, patch 가 시험에서 더 빠르고 실수가 적다.

## Q15 장애 조치 — CrashLoopBackOff 와 원인 보고

```bash
kubectl -n broken logs deploy/worker --previous     # 설정 파일/키를 못 찾는다는 로그
kubectl -n broken describe pod -l app=worker        # 마운트한 ConfigMap 키 확인
kubectl -n broken get cm worker-config -o yaml
```

컨테이너가 기대하는 키와 ConfigMap 의 키가 어긋나 있다. ConfigMap 을 고치고 롤아웃을 다시 돌린다.

```bash
kubectl -n broken rollout restart deploy/worker
echo "configmap/worker-config" > ~/answers/q15.txt
```

자주 틀리는 곳

- 원인 보고 파일은 `~/answers/q15.txt` 에 **`configmap/worker-config`** 한 줄이어야 한다(대소문자·공백 무시).
- ConfigMap 을 고쳐도 **이미 뜬 파드는 갱신되지 않는다**. `rollout restart` 가 필요하다.
- 채점은 파드가 재시작 없이 20초 이상 살아 있는지 본다 — 고친 직후 바로 제출하면 미달일 수 있다.

## Q16 etcd 백업과 오프라인 복구

백업은 `etcdctl`, 오프라인 복구는 `etcdutl` — 실제 시험에서 쓰는 도구 그대로다.
인증서가 root 소유라 두 명령 모두 `sudo` 가 필요하다.

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  snapshot save ~/backup/etcd-snap.db
sudo etcdutl snapshot restore ~/backup/etcd-snap.db --data-dir ~/backup/restored
sudo etcdutl snapshot status ~/backup/etcd-snap.db   # 검증 습관
```

자주 틀리는 곳

- `--cacert`/`--cert`/`--key` 세 개 중 하나라도 빠지면 TLS 핸드셰이크에서 실패한다.
- `--data-dir` 가 이미 존재하면 restore 가 거부한다 — 새 디렉터리 이름을 줘야 한다.
- `etcdctl snapshot restore` 는 deprecated 경고가 뜨지만 동작은 한다. 시험에선 `etcdutl` 을 쓰자.
- 채점은 스냅샷의 리비전과 복구 디렉터리의 `member/snap/db` 존재를 본다 — 빈 파일·빈 디렉터리는
  점수가 없다.

## Q17 노드 비우기(drain) — worker-1 유지보수

한 줄이면 된다. drain 은 cordon 을 포함한다.

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n maint -o wide   # 4개 모두 worker-2 에서 Running 이면 끝
```

자주 틀리는 곳

- `--ignore-daemonsets` 없이 drain 하면 DaemonSet 파드 때문에 거부될 수 있다.
- `cordon` 만 하면 새 스케줄만 막을 뿐 기존 파드가 남는다 — 축출까지 해야 drain 이다.
- drain 후 `uncordon` 하면 감점이다. 유지보수 시나리오이므로 스케줄 금지 상태를 유지해야 한다.
