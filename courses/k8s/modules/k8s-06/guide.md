# 스케줄링 — 어피니티·테인트·DaemonSet

스케줄러는 파드를 어느 노드에 놓을지 결정한다. **nodeAffinity/nodeSelector** 로 파드가 특정
노드를 *원하게* 하고, **taint/toleration** 으로 노드가 특정 파드를 *밀어내게* 한다. 둘은
반대 방향의 도구다. **DaemonSet** 은 (조건에 맞는) 모든 노드에 파드를 하나씩 깐다.

이 클러스터는 노드가 1개다. 노드 이름은 아래로 확인한다:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — 명령 치환. `{.items[0].metadata.name}` 으로 첫 노드 이름을 뽑아 셸 변수 `node` 에 담는다.
- `; echo "$node"` — 담긴 값을 출력해 확인한다. 이후 명령은 `"$node"` 로 이 이름을 쓴다.

> 참고: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. 노드 레이블과 nodeAffinity

노드에 `disktype=ssd` 레이블을 붙이고, `requiredDuringScheduling` nodeAffinity 로 그 레이블이
있는 노드에만 앉는 파드 `affine` 을 만든다.

노드에 레이블 부여:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <리소스> <이름> 키=값` — 레이블을 붙인다. 이미 있는 키를 바꾸려면 `--overwrite`, 지우려면 `키-` 형식을 쓴다.

nodeAffinity 파드 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: affine }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disktype, operator: In, values: ["ssd"] }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `requiredDuringSchedulingIgnoredDuringExecution` — 스케줄 시점엔 **반드시** 만족해야 하고, 이미 실행 중인 파드는 나중에 레이블이 바뀌어도 쫓아내지 않는다.
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — `disktype` 레이블 값이 `ssd` 인 노드만 후보가 된다. (`NotIn`, `Exists` 등 연산자도 있다.)

파드 배치 확인:

```bash
kubectl get pod affine -o wide      # NODE 열에 우리 노드
```

- `-o wide` 의 `NODE` 열로 파드가 어느 노드에 배치됐는지 확인한다.

레이블을 지우면(`kubectl label node "$node" disktype-`) 새 파드는 `Pending` 이 된다 — 직접
확인해 보라.

## 2. 테인트와 톨러레이션

노드에 `lab=demo:NoSchedule` **테인트** 를 걸면, 그 테인트를 **톨러레이트** 하지 않는 파드는
스케줄되지 못한다. 톨러레이션을 가진 `tolerant` 만 착지한다.

노드에 테인트 설정:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <노드> 키=값:효과` — 노드에 테인트를 건다. 효과는 `NoSchedule`(새 파드 거부), `PreferNoSchedule`(가급적 회피), `NoExecute`(기존 파드도 축출).
- 해제는 끝에 `-` 를 붙인다: `kubectl taint nodes "$node" lab=demo:NoSchedule-`

톨러레이션 없는 파드는 Pending (확인용):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — 앞 명령이 끝나면 뒤 명령을 이어서 실행한다. 파드를 만든 직후 상태를 조회한다.
- 톨러레이션이 없으므로 `STATUS` 가 `Pending` 에 머문다. `kubectl describe pod notol` 의 Events 에 `untolerated taint` 가 보인다.

확인용 파드 삭제:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <이름>` — 파드를 삭제한다. 확인용 파드가 남아 있으면 이후 체크에 방해가 된다.

톨러레이션 가진 파드 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: tolerant }
spec:
  tolerations:
    - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `tolerations` — 이 파드가 견딜 수 있는 테인트 목록. `key`·`value`·`effect` 가 노드 테인트와 일치해야 한다.
- `operator: Equal` 은 값까지 비교, `Exists` 는 키만 있으면 허용한다.

파드 상태 확인:

```bash
kubectl get pod tolerant -o wide     # Running
```

- 톨러레이션이 있으니 테인트된 노드에도 배치되어 `Running` 이 된다.

> `NoSchedule` 은 새 파드만 막고 기존 파드는 두지만, `NoExecute` 는 톨러레이트 안 하는 기존
> 파드까지 축출한다.

## 3. DaemonSet

**DaemonSet** 은 모든 노드에 파드 1개씩 유지한다(로그 수집기·노드 에이전트 등). 우리가 노드에
`lab` 테인트를 걸어 뒀으므로, DaemonSet 파드도 **톨러레이션이 있어야** 노드에 앉는다.

DaemonSet 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
        - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
      containers:
        - name: agent
          image: busybox:1.36
          args: ["/bin/sh","-c","sleep 3600"]
          resources: { requests: { cpu: "10m", memory: "16Mi" } }
EOF
```

- `kind: DaemonSet` — `replicas` 가 없다. 조건에 맞는 노드마다 파드를 정확히 하나씩 유지한다.
- `selector.matchLabels` 는 `template.metadata.labels` 와 같아야 한다.
- 노드에 걸린 `lab` 테인트 때문에 여기에도 같은 `tolerations` 가 필요하다.

DaemonSet 상태 확인:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` 는 `daemonset` 의 축약형. `DESIRED` — 파드가 있어야 할 노드 수, `CURRENT` — 만들어진 수, `READY` — 준비된 수.

`DESIRED`·`READY` 가 노드 수(1)와 같아지면 성공이다.

> 참고: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
