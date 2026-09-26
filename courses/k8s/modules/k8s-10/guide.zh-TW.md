# 綜合 —— 救活出故障的部署

兩個電商應用(`shop`、`cart`)已經部署,但 **什麼都沒跑起來。** 三處埋著不同的故障。
這個綜合實戰不是學習新概念,而是訓練你用學過的診斷工具 —`kubectl get`、`describe`、`logs`、
`get events`— **自己找到原因並修復**。

先從整體看起:

縱覽所有資源:

```bash
kubectl get deploy,pods,svc
```

- 用逗號分隔,一次查詢多種資源。同時檢視 Deployment 的 `READY`、Pod 的 `STATUS` 和 Service 列表,找出異常之處。

檢視最近事件:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — 名稱空間中發生的事件(排程、映像拉取、失敗等)。
- `--sort-by=.lastTimestamp` — 按最後發生時間排序,`| tail -20` — 只看最近 20 行。

> 參考: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. 修復映像拉取失敗

`shop` 的 Pod 處於 `ImagePullBackOff`/`ErrImagePull`。找出原因。

檢視 shop Pod 狀態:

```bash
kubectl get pods -l app=shop
```

- `STATUS` 列的 `ImagePullBackOff`/`ErrImagePull` — 節點無法拉取映像,正在逐步拉長重試間隔等待。

從事件中找原因:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # 能看到 "not found" 的標籤
```

- `describe` 最下方的 `Events` 最直接地說明了失敗原因。用 `grep -A5 -i events` 只看這一部分。

檢視當前映像標籤:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — Deployment 建立 Pod 時使用的映像名:標籤。

問題在於映像標籤不存在。改成有效的標籤:

更換映像標籤:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — 替換名為 `web` 的容器的映像。模板改變,新的 Pod 會被髮布。

等待發布完成:

```bash
kubectl rollout status deploy/shop
```

- 等到新 Pod 全部 Ready。如果一直不結束,按 `Ctrl+C` 後再用 `describe` 檢視原因。

`shop` 變為 2/2 Ready,① 就解決了。

## 2. 修復 Service 選擇器

Pod 已經起來了,但 Service `shop` 無法轉發流量。看看端點是否為空。

檢視端點:

```bash
kubectl get endpoints shop            # <none> — 沒有任何 Pod 關聯
```

- `ENDPOINTS` 為 `<none>`,說明沒有任何 Ready 的 Pod 匹配 Service 的選擇器。

檢視 Service 選擇器:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX(拼寫錯誤)
```

- `{.spec.selector}` — 以 JSON 檢視 Service 選擇 Pod 所用的標籤條件。

檢視 Pod 的實際標籤:

```bash
kubectl get pods -l app=shop --show-labels                  # 實際標籤是 app=shop
```

- `--show-labels` — 用 `LABELS` 列顯示每個 Pod 上的全部標籤。與選擇器逐字比對一下。

Service 選擇器與 Pod 標籤不匹配。修正選擇器:

修改選擇器:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — 就地修改資源的部分欄位。
- `--type=merge` — 把 `-p` 給出的 JSON 合併到現有物件中(JSON merge patch)。
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — 只寫要改的部分的補丁。用單引號括起來,避免 shell 解釋。

再次檢視端點:

```bash
kubectl get endpoints shop            # 現在填入了 Pod IP
```

端點被填上,② 就解決了。

## 3. 修復缺失的 ConfigMap

`cart` 的 Pod 卡在 `CreateContainerConfigError`。看看原因。

檢視 cart Pod 狀態:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — 映像已拉取,但無法生成容器配置(引用的 ConfigMap/Secret 等)。

從事件中找原因:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- 在 Events 中可以看到缺失的是哪個物件(`configmap "cart-config" not found`),連名稱都有。

檢視引用的 envFrom:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — 容器整體匯入為環境變數的 ConfigMap/Secret 引用列表。

它引用了不存在的 ConfigMap `cart-config`。建立它之後,kubelet 就會正常啟動 Pod:

建立 ConfigMap:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- 給兩次 `--from-literal=鍵=值`,建立含兩個鍵的 ConfigMap。建立後 kubelet 會在重試中啟動容器。

等待發布完成:

```bash
kubectl rollout status deploy/cart
```

`cart` 變為 1/1 Ready,③ 就解決了 — 三處故障全部修復。

```bash
kubectl get deploy,svc,endpoints      # 最終確認
```

- 一次性檢視 Deployment 的 READY、Service 和端點,確認三處故障都已修復。
