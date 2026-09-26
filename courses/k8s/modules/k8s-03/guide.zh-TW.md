# ConfigMap 與 Secret

配置與程式碼分離是基本原則。**ConfigMap** 儲存明文配置,**Secret** 儲存密碼、令牌等敏感資訊
(以 base64 編碼),二者都可以作為 **環境變數** 或 **卷中的檔案** 注入到 Pod。

> 參考: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. 建立 ConfigMap

建立包含鍵 `APP_MODE` 和 `APP_GREETING` 的 ConfigMap `app-config`。

建立 ConfigMap:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — 以命令式方式建立 ConfigMap `app-config`。行尾的 `\` 表示把一條命令分成多行書寫。
- `--from-literal=鍵=值` — 直接寫入鍵值對,可以指定多次;含空格的值要用引號括起來。
- 從檔案建立用 `--from-file=<路徑>`,從 env 檔案建立用 `--from-env-file=<路徑>`。

檢視內容:

```bash
kubectl get cm app-config -o yaml
```

- `cm` 是 `configmap` 的縮寫。`-o yaml` 可原樣檢視儲存的物件(`data:` 下的鍵值)。

用 `kubectl describe cm app-config` 確認兩個鍵都已寫入。

## 2. 建立 Secret

建立包含鍵 `DB_PASSWORD` 的 **Opaque** Secret `app-secret`。`create secret generic`
會自動對值進行 base64 編碼。

建立 Secret:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — 建立用於任意鍵值的 `Opaque` 型別 Secret(另有 `tls`、`docker-registry` 型別)。
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — 儲存時值會自動 base64 編碼。單引號防止 shell 解釋特殊字元。

檢視編碼後的值:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — 只取出 Secret 的 `data` 中某一個鍵的值(base64 字串)。

解碼後檢視:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — 對 base64 解碼(`-d`),還原成原始值。也就是說,只要有讀取 Secret 的權限,任何人都能看到明文。

> 注意: Secret 的 data 只是編碼而不是加密。生產環境中要透過 etcd 加密和 RBAC 限制訪問 —
> [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. 在 Pod 中注入使用

建立 Pod `app`,把 **ConfigMap 作為環境變數(envFrom)**、**Secret 作為卷檔案**
(`/etc/app-secret`)注入。

建立 Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      envFrom:
        - configMapRef: { name: app-config }
      volumeMounts:
        - { name: secret-vol, mountPath: /etc/app-secret, readOnly: true }
  volumes:
    - name: secret-vol
      secret: { secretName: app-secret }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — 把到 `EOF` 行為止的 YAML 透過標準輸入交給 kubectl 應用。`-f -` 表示"從 stdin 讀取而不是檔案",加引號的 `'EOF'` 可防止 shell 替換正文中的 `$`。
- `envFrom.configMapRef` — 把 ConfigMap 的 **所有鍵** 注入為同名環境變數(只要一個鍵時用 `env[].valueFrom.configMapKeyRef`)。
- `volumes[].secret` + `volumeMounts` — 把 Secret 的每個鍵掛載為檔案 `/etc/app-secret/<鍵>`。

等待 Ready:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — 等到 Pod 的 `Ready` 條件為真。
- `--timeout=60s` — 超過這個時間仍未滿足則以失敗結束。

檢視環境變數:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → 環境變數
```

- `kubectl exec app -- <命令>` — 在執行中的容器裡執行命令,`--` 之後是在容器中執行的命令。
- `printenv A B` — 只輸出指定環境變數的值。

檢視 Secret 檔案:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → 檔案
```

- 以卷方式掛載的 Secret 會顯示為已經解碼的明文檔案,鍵名就是檔名。

環境變數中能看到 `APP_MODE`/`APP_GREETING`,且存在檔案 `/etc/app-secret/DB_PASSWORD`,即為成功。

> 參考: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
