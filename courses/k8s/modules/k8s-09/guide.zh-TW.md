# NetworkPolicy —— 微分段

預設情況下,叢集中的所有 Pod 都可以相互通訊。**NetworkPolicy** 是 Pod 級的防火牆,
針對按標籤選出的 Pod,規定允許哪些 **來源(from)/目的地(to)** 的流量。規則是 **允許(allow)列表** —
一旦某個 Pod 被策略"選中",它就只接受被明確允許的流量(其餘一律拒絕)。

本實驗中已經執行著伺服器 `web`(+Service `web`)和客戶端 Pod `client`(標籤 `app=client`)。
k3s 會真正強制執行 NetworkPolicy。

檢視 web Pod:

```bash
kubectl get pod -l app=web -o wide
```

- 用 `-l app=web` 檢視伺服器 Pod,用 `-o wide` 檢視其 IP。NetworkPolicy 也是按這個標籤選擇 Pod。

檢視 client Pod:

```bash
kubectl get pod client -o wide
```

- 客戶端 Pod。可以先用 `kubectl get pod client --show-labels` 確認它的 `app=client` 標籤 — 第 3 步的允許規則就基於它。

> 參考: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. 確認基本連通性

在沒有策略時確認 client 能訪問 web,並把結果作為基線記錄到 `~/work/baseline.txt`
(用於和第 2、3 步的阻斷、放行作對比)。

測試 client → web 連通:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx 響應
```

- `kubectl exec client -- …` — 在 client Pod **內部** 發出請求(使來源成為 client)。
- `wget -q -T 3 -O- http://web` — 以 3 秒超時(`-T 3`)請求 `web` Service,把響應輸出到標準輸出(`-O-`)。
- `| head -1` — 只看響應的第一行。

建立記錄用目錄:

```bash
mkdir -p ~/work
```

- `mkdir -p` — 連同中間目錄一起建立,已存在也不報錯。

儲存基線響應:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> 檔案` — 把命令的標準輸出儲存(覆蓋)到檔案。`kubectl exec` 的輸出會回到你的終端這邊,所以檔案也建立在本地。

檢視儲存的內容:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <檔案>` — 只輸出檔案的第一行。

出現 nginx HTML 的第一行(`<!DOCTYPE html>`)就說明是通的。

## 2. 預設拒絕(default-deny)

建立一個選中 `web` Pod、但 **不含任何 ingress 規則** 的策略。發往被選中 Pod 的所有入站流量都會被阻斷。

建立 default-deny 策略:

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

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `podSelector` — 策略作用的目標 Pod(`app=web`)。空選擇器 `{}` 表示名稱空間中的所有 Pod。
- `policyTypes: [Ingress]` 卻沒有 `ingress:` 規則 → 拒絕所有進入被選中 Pod 的流量。

確認已阻斷(預期超時):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # 超時(被阻斷)
```

- `-t 1` — 只嘗試 1 次。被阻斷時 3 秒後以 `timed out` 結束(資料包被靜默丟棄,沒有拒絕響應)。

`wget` 因超時失敗,說明策略已經擋住了流量。

## 3. 按來源放行

現在新增一個只允許來自帶 `app=client` 標籤 Pod 的 80 埠流量的策略。策略是累加的,
所以這條放行會疊加在 default-deny 之上,只有 client 能透過。

建立放行策略:

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

- `ingress[].from[].podSelector` — 只允許同一名稱空間中帶 `app=client` 標籤的 Pod 作為來源。
- `ports` — 允許的埠/協議(TCP 80)。`from` 與 `ports` 位於同一項內時必須同時滿足。
- 策略之間按"或"合併,所以即使有 default-deny,這條放行也會額外生效。

再次測試 client → web:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # 再次成功
```

client → web 恢復連通即為成功。換一個沒有 `app=client` 標籤的 Pod 來測試,仍會被阻斷 —
這就是微分段。

> 參考: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
