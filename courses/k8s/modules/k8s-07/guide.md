# 스토리지 — PV·PVC·StatefulSet

파드는 사라지면 파일도 사라진다(임시). 영속 저장은 **PersistentVolume(PV)** — 실제 저장공간 —
을 **PersistentVolumeClaim(PVC)** — "이만큼 필요하다"는 요청 — 으로 요구해서 얻는다.
**StorageClass** 는 PVC 가 들어오면 PV 를 **동적 프로비저닝** 한다.

이 k3s 는 기본 StorageClass `local-path` 를 제공한다. 이 클래스는
`volumeBindingMode: WaitForFirstConsumer` 라서 **PVC 를 소비하는 파드가 스케줄될 때** 비로소
PV 를 만들고 바인딩한다 — 그래서 처음엔 PVC 가 `Pending` 인 게 정상이다.

```bash
kubectl get storageclass         # local-path (default)
```

- `storageclass` (축약 `sc`) — PV 를 동적으로 만들어 주는 프로비저너 설정. 이름 옆 `(default)` 표시가 붙은 것이 PVC 에 클래스를 안 쓸 때 쓰인다.
- `VOLUMEBINDINGMODE` 열에서 `WaitForFirstConsumer` 를 확인할 수 있다.

> 참고: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. PVC 생성

100Mi 를 요청하는 PVC `data` 를 만든다. 기본 StorageClass 가 쓰인다.

PVC 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 100Mi } }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `accessModes: [ReadWriteOnce]` — 한 노드에서만 읽기/쓰기로 마운트(RWO). 여러 노드 공유는 `ReadWriteMany`(RWX).
- `resources.requests.storage: 100Mi` — 요청 용량. `storageClassName` 을 생략했으므로 기본 클래스가 쓰인다.

PVC 상태 확인:

```bash
kubectl get pvc data       # STATUS 는 Pending (WaitForFirstConsumer)
```

- `pvc` 는 `persistentvolumeclaim` 의 축약형. `STATUS` 가 `Pending` → `Bound` 로 바뀌면 PV 와 연결된 것이고, `VOLUME` 열에 연결된 PV 이름이 나온다.

아직 파드가 없으니 `Pending` 이 정상이다. 다음 단계에서 파드가 붙으면 `Bound` 가 된다.

## 2. 파드에 마운트·바인딩·기록

PVC `data` 를 `/data` 로 마운트하는 파드 `writer` 를 만든다. 파드가 스케줄되면 PVC 가
`Bound` 로 바뀌고, 컨테이너가 `/data/marker.txt` 를 기록한다.

PVC 를 마운트하는 파드 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox:1.36
      args: ["/bin/sh","-c","echo 'persisted by writer' > /data/marker.txt; sleep 3600"]
      volumeMounts: [{ name: vol, mountPath: /data }]
  volumes:
    - name: vol
      persistentVolumeClaim: { claimName: data }
EOF
```

- `volumes[].persistentVolumeClaim.claimName: data` — 파드 볼륨을 PVC `data` 에 연결한다.
- `volumeMounts[].mountPath: /data` — 그 볼륨을 컨테이너 안 `/data` 에 붙인다. 컨테이너는 시작하자마자 파일을 하나 쓴다.

파드 Ready 대기:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

- `kubectl wait --for=condition=Ready` — 파드가 Ready 가 될 때까지 기다린다. 볼륨 프로비저닝 시간이 있으니 넉넉히 `--timeout=90s`.

PVC 바인딩 확인:

```bash
kubectl get pvc data                       # 이제 Bound
```

기록된 파일 읽기:

```bash
kubectl exec writer -- cat /data/marker.txt
```

- `kubectl exec <파드> -- <명령>` — 컨테이너 안에서 명령을 실행한다. PVC 위에 기록된 파일을 읽어 본다.

PVC 가 `Bound` 가 되고 `/data/marker.txt` 를 읽을 수 있으면 성공이다. 파드를 지웠다 다시
만들어도(같은 PVC 마운트) 파일이 남아 있는 걸 확인해 보라 — 그게 영속성이다.

## 3. StatefulSet 와 volumeClaimTemplates

**StatefulSet** 은 파드마다 안정적인 이름(web-0, web-1…)과 **전용 PVC** 를 준다.
`volumeClaimTemplates` 에 적으면 파드별로 PVC 가 자동 생성된다(이름 규칙: `<템플릿>-<파드>`,
여기선 `www-web-0`).

StatefulSet 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web-h
  replicas: 1
  selector: { matchLabels: { app: sts-web } }
  template:
    metadata: { labels: { app: sts-web } }
    spec:
      containers:
        - name: app
          image: nginx:1.26
          volumeMounts: [{ name: www, mountPath: /usr/share/nginx/html }]
  volumeClaimTemplates:
    - metadata: { name: www }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 100Mi } }
EOF
```

- `kind: StatefulSet` — 파드 이름이 `web-0`, `web-1` … 처럼 순번으로 고정되고 순서대로 생성·삭제된다.
- `serviceName: web-h` — 파드별 DNS(`web-0.web-h`)를 제공할 Headless Service 이름.
- `volumeClaimTemplates` — 파드마다 PVC 를 하나씩 찍어 내는 틀. 파드를 지워도 PVC 는 남아 같은 파드가 다시 붙는다.

롤아웃 완료 대기:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

- `kubectl rollout status statefulset/web` — Deployment 처럼 StatefulSet 의 롤아웃 완료도 기다릴 수 있다.
- `--timeout=120s` — PV 프로비저닝·이미지 풀까지 고려한 대기 시간.

자동 생성된 PVC 확인:

```bash
kubectl get pvc                 # www-web-0 이 Bound
```

- 인자 없이 `kubectl get pvc` — 네임스페이스의 모든 PVC. 템플릿에서 자동 생성된 `www-web-0` 이 보인다.

파드 `web-0` 이 Ready 이고 자동 생성된 PVC `www-web-0` 이 `Bound` 면 성공이다.

> 참고: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
