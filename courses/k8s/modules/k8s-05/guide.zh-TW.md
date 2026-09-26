# 資源請求、限制與 QoS

為容器設定 **requests**(排程器預留的最小量)和 **limits**(上限 — 超出時 CPU 被限流,
記憶體會被 OOM Kill)。二者的組合決定 Pod 屬於三種 **QoS 類別** 中的哪一種,進而決定節點資源緊張時的
**驅逐(eviction)順序**:`BestEffort` → `Burstable` → `Guaranteed`,越靠前越先被驅逐。

> 參考: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. Guaranteed QoS 的 Pod

所有容器的 **cpu、memory 的 requests 與 limits 都設為相同值** 時,Pod 為 `Guaranteed`,
是受保護程度最高的類別。

建立 Pod:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `resources.requests` — 排程器在節點上預留的最小量,`limits` — 不可超過的上限。
- `cpu: "250m"` — 毫核單位(1000m = 1 個 CPU),`memory: "64Mi"` — 二進位制單位 MiB。
- requests 與 limits 相同即為 `Guaranteed`。

檢視 QoS 類別:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — 只取出 Pod status 中記錄的 QoS 類別(`Guaranteed`/`Burstable`/`BestEffort`)。

## 2. Burstable QoS 的 Pod

設定了 requests,但 limits 更大(或只設定了一部分)時為 `Burstable`。平時按 requests 使用,
有富餘時可以突增(burst)到 limits。

建立 Pod:

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

- limits(500m/128Mi)大於 requests(100m/32Mi)→ 平時少量預留,節點有空閒時才用到 limits(`Burstable`)。

檢視 QoS 類別:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — 只取出 Pod status 中記錄的 QoS 類別(`Guaranteed`/`Burstable`/`BestEffort`)。

> 完全不設定 requests、limits 時為 `BestEffort` — 驗證:先 `kubectl run be --image=nginx:1.26`,
> 再 `kubectl get pod be -o jsonpath='{.status.qosClass}'`。

## 3. LimitRange 預設值

**LimitRange** 為名稱空間規定預設的 requests/limits,即使開發者忘記設定,Pod 也會有資源上限。
**必須先於 Pod** 建立,預設值才會被注入。

建立 LimitRange:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # limits 預設值
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # requests 預設值
EOF
```

- `kind: LimitRange` — 適用於在此名稱空間中建立的容器的資源規則。
- `default` — 未寫 limits 的容器會被填入的 limits 預設值,`defaultRequest` — requests 預設值。
- 預設值在 Pod **建立時** 注入,不會追溯到已存在的 Pod。

建立不顯式設定 limits 的 Pod — LimitRange 會填入預設值:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <名稱> --image=<映像>` — 不經 Deployment,直接建立一個 Pod。這裡故意不設定 resources。

檢視注入的 resources:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — 以 JSON 檢視第一個容器的整個 resources 塊。你沒寫的值已由 LimitRange 填入。

Pod `defaulted` 的 `resources.limits.memory` 被填為 `128Mi` 即為成功。

> 參考: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
