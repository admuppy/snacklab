# Service 與叢集網路

Pod 隨時可能掛掉,並以新的 IP 重新啟動。**Service** 透過標籤選擇一組 Pod,為它們提供穩定的
虛擬 IP、DNS 名稱和負載均衡。本實驗把已經在執行的 Deployment `web`(標籤 `app=web`,2 個副本)
透過三種 Service 型別暴露出來。

檢視 Deployment:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — 確認要暴露的 Deployment 存在,且 Pod 全部 `READY`。

檢視後端 Pod:

```bash
kubectl get pods -l app=web -o wide     # 檢視後端 Pod 的 IP
```

- `-l app=web` — 用 Service 選擇器將要使用的同一個標籤來查詢 Pod。
- `-o wide` — 會顯示 Pod IP 列,稍後可與 Service 的端點對比。

> 參考: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. 用 ClusterIP 暴露

預設型別 **ClusterIP** 會建立一個只能在叢集內部訪問的虛擬 IP。Service 名為 `web`,埠 80。

建立 Service:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — 直接沿用 Deployment 的 Pod 選擇器(`app=web`)建立 Service。
- `--name=web` — 要建立的 Service 名稱,這個名稱同時也是 DNS 名。
- `--port=80` — Service 接收的埠,`--target-port=80` — 流量轉發到的容器埠。
- 省略 `--type` 時預設為 `ClusterIP`。

檢視 Service:

```bash
kubectl get svc web
```

- `svc` 是 `service` 的縮寫。`CLUSTER-IP` 列是隻在叢集內部使用的虛擬 IP。

檢視端點:

```bash
kubectl get endpoints web           # 選擇器選中的 Pod IP:埠列表
```

- `endpoints` — Service 實際傳送流量的後端(Pod IP:埠)列表。只有匹配選擇器且 **Ready** 的 Pod 才會列入。

從叢集內部測試訪問:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — 啟動一個用完即棄的測試 Pod `t`。
- `--restart=Never --rm -it` — 不重啟、只執行一次,連線終端(`-it`)檢視結果,結束後刪除 Pod(`--rm`)。
- `--` 之後是要在容器內執行的命令。行尾的 `\` 表示命令延續到下一行。
- `wget -qO- <URL>` — 安靜地(`-q`)獲取內容,輸出到標準輸出(`-O-`)而不是檔案。
- `web.default.svc.cluster.local` — `<服務>.<名稱空間>.svc.cluster.local` 形式的 Service DNS 名。

`kubectl get endpoints web` 中出現 Pod IP,說明路由已建立。若端點為空,則是選擇器(`app=web`)
與 Pod 標籤不匹配。

## 2. 用 NodePort 對外暴露

**NodePort** 會在所有節點上開放一個固定埠(預設 30000–32767),使叢集外部也能訪問。
建立 Service `web-np`。

建立 NodePort Service:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — 在 ClusterIP 的基礎上,再在 **所有節點的同一個埠**(從 30000–32767 中自動分配)上開放,供叢集外部訪問。
- `--name=web-np` — 換一個名字,避免與前面的 `web` Service 衝突。

檢視分配的埠:

```bash
kubectl get svc web-np                          # PORT(S) 列中的 80:3xxxx/TCP
```

- `PORT(S)` 中的 `80:3xxxx/TCP` — 前面是 Service 埠,後面是在節點上開放的 nodePort。

把 nodePort 存入變數:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — 命令替換,把括號內命令的輸出存入 shell 變數 `np`。
- `{.spec.ports[0].nodePort}` — 只取出第一個埠項 nodePort 值的 JSONPath。

在節點上直接訪問:

```bash
curl -s http://127.0.0.1:$np | head -1          # 在節點(即本 Pod)上直接訪問
```

- `curl -s` — 不顯示進度(silent)地傳送 HTTP 請求。`$np` 會替換為前面儲存的 nodePort。
- `127.0.0.1` — 在本實驗中終端本身就是節點,所以用節點自己的地址訪問。
- `| head -1` — 只看響應的第一行。

像 `80:3xxxx/TCP` 這樣分配了 nodePort,且 curl 返回 nginx 響應,即為成功。

## 3. Headless Service 與 DNS

`clusterIP: None` 的 **Headless Service** 沒有虛擬 IP 和代理,DNS 查詢會直接把
**每個 Pod 的 IP** 作為 A 記錄返回。常用於 StatefulSet 中按 Pod 訪問等場景。

建立 Headless Service:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `clusterIP: None` — 宣告不建立虛擬 IP 的 Headless Service。`selector` 選中的 Pod IP 會直接登記到 DNS。

檢視 CLUSTER-IP:

```bash
kubectl get svc web-h                 # CLUSTER-IP 為 None
```

- `CLUSTER-IP` 為 `None` 即表示 Headless,不參與 kube-proxy 的負載均衡。

測試 DNS 查詢:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # Pod 有幾個就有幾條 A 記錄
```

- `kubectl run t --image=busybox:1.36` — 啟動一個用完即棄的測試 Pod `t`。
- `--restart=Never --rm -it` — 不重啟、只執行一次,連線終端(`-it`)檢視結果,結束後刪除 Pod(`--rm`)。
- `--` 之後是要在容器內執行的命令。行尾的 `\` 表示命令延續到下一行。
- `nslookup <名稱>` — 向 DNS 查詢名稱並輸出 A 記錄(IP)。Headless 會返回與 Pod 數量相同的 IP。

`CLUSTER-IP` 為 `None`,且 nslookup 返回與 Pod 數量相同的 IP,即為成功。

> 參考: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
