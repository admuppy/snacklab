# 스케줄링 — 어피니티·테인트·DaemonSet

스케줄러는 파드를 어느 노드에 놓을지 결정한다. **nodeAffinity/nodeSelector** 로 파드가 특정
노드를 *원하게* 하고, **taint/toleration** 으로 노드가 특정 파드를 *밀어내게* 한다. 둘은
반대 방향의 도구다. **DaemonSet** 은 (조건에 맞는) 모든 노드에 파드를 하나씩 깐다.

이 클러스터는 노드가 1개다. 노드 이름은 아래로 확인한다:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

> 참고: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. 노드 레이블과 nodeAffinity

노드에 `disktype=ssd` 레이블을 붙이고, `requiredDuringScheduling` nodeAffinity 로 그 레이블이
있는 노드에만 앉는 파드 `affine` 을 만든다.

노드에 레이블 부여:

```bash
kubectl label node "$node" disktype=ssd
```

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

파드 배치 확인:

```bash
kubectl get pod affine -o wide      # NODE 열에 우리 노드
```

레이블을 지우면(`kubectl label node "$node" disktype-`) 새 파드는 `Pending` 이 된다 — 직접
확인해 보라.

## 2. 테인트와 톨러레이션

노드에 `lab=demo:NoSchedule` **테인트** 를 걸면, 그 테인트를 **톨러레이트** 하지 않는 파드는
스케줄되지 못한다. 톨러레이션을 가진 `tolerant` 만 착지한다.

노드에 테인트 설정:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

톨러레이션 없는 파드는 Pending (확인용):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

확인용 파드 삭제:

```bash
kubectl delete pod notol
```

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

파드 상태 확인:

```bash
kubectl get pod tolerant -o wide     # Running
```

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

DaemonSet 상태 확인:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

`DESIRED`·`READY` 가 노드 수(1)와 같아지면 성공이다.

> 참고: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
