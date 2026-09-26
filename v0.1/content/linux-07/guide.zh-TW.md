# 網路診斷

"服務連不上"的原因大多是以下四種之一 — **IP 不對、埠沒開、繫結錯了、名稱解析不了。** 本模組將學習按順序診斷這四種情況的工具(ip、ss、curl、getent)。

實驗環境中執行著一個名為 `lab-api` 的 API 服務 — 但已經收到"外部無法連線"的報告。做到最後,你會找出原因並修復它。

## 檢查網路介面與 IP

網路診斷的起點是確認 **我是誰**(IP)。如今的標準工具是 `ip`(ifconfig 已經退役)。

檢視介面列表:

```
ip link
```

- `ip link` — 顯示網路介面(L2)列表及其狀態(`UP`/`DOWN`)、MAC 地址、MTU。

檢視 IPv4 地址:

```
ip -4 addr show
```

- `ip addr show` — 各介面的 IP 地址。`-4` 只看 IPv4。以 `inet 10.x.x.x/24` 這樣的地址/字首長度(CIDR)形式顯示。

檢視路由表:

```
ip route
```

- `ip route` — 路由表。`default via <閘道器>` 這一行是通往外部的預設路由。

容器中通常能看到 `lo`(環回)和 `eth0` 兩個介面。適合在腳本中使用的單行提取方法:

把 eth0 輸出為一行:

```
ip -4 -o addr show eth0
```

- `-o` — 把一個介面的資訊輸出為 **一行**(oneline),便於用 `grep`、`awk` 處理。
- `show eth0` — 只看指定的介面。

只提取 CIDR 欄位:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

- `awk '{print $4}'` — 只取出按空白分隔的第 4 個欄位(`10.x.x.x/24`)。

任務:把 eth0 的 IPv4 地址 **不帶 CIDR,只儲存地址** 到 `~/work/myip.txt`。`/24` 這樣的字尾用 `cut -d/ -f1` 去掉。

只取地址並儲存:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

- `cut -d/ -f1` — 以 `/` 為分隔符(`-d`)切分,只取第一個欄位(`-f1`)→ 地址部分。
- `> ~/work/myip.txt` — 把結果儲存到檔案。

檢視儲存的內容:

```
cat ~/work/myip.txt
```

- 輸出儲存的地址進行確認。之後的命令會以 `$(cat ~/work/myip.txt)` 的形式複用它。

儲存好後點選 **[驗證]**。

## 追蹤監聽套接字

下一個問題:**什麼在哪個埠上監聽。** 先從 `ss` 的必備組合開始。

| 選項 | 含義 |
|---|---|
| `-l` | 只看監聽套接字 |
| `-t` / `-u` | TCP / UDP |
| `-n` | 埠以數字顯示(省略服務名轉換) |
| `-p` | 顯示程序(其他使用者的需要 sudo) |

```
sudo ss -ltnp
```

- 上表中的選項組合。結果中的 `Local Address:Port` 告訴你在哪個地址和埠上監聽,`users:((…))` 告訴你是哪個程序。

任務:找出 `lab-api.service` 監聽的 **連接埠號**,儲存到 `~/work/api-port.txt`。從單元的主 PID 入手也是個好辦法。

檢視 lab-api 的主 PID:

```
systemctl show -p MainPID --value lab-api
```

- `systemctl show -p MainPID --value <單元>` — 只輸出單元主程序的 PID 值。

查詢該 PID 的監聽套接字:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

- 雙引號中的 `$( … )` 也會被替換 → 變成 `grep "pid=1234"`,只留下該 PID 的套接字行。

從 Local Address 列的 `127.0.0.1:埠` 中讀出埠即可。儲存後點選 **[驗證]**。

## 診斷並修復繫結問題

你可能已經在剛才的 ss 輸出中注意到了 — lab-api 的 Local Address 是 `127.0.0.1:9090`。它 **只繫結在環回地址上**,所以在這個容器裡能用,從外部(其他 Pod、節點)訪問就會出現 connection refused。來複現一下。

透過環回地址連線:

```
curl -s http://127.0.0.1:9090/status.json        # 成功
```

- `curl -s <URL>` — 安靜地傳送請求,只輸出響應正文。透過環回地址(`127.0.0.1`)可以連通。

透過容器 IP 連線:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # 失敗!
```

- `--max-time 3` — 把整個請求限制在 3 秒內(沒有響應就不再等待)。
- `$(cat ~/work/myip.txt)` — 把儲存好的容器 IP 嵌入 URL。

同一個程序,結果卻取決於 **請求從哪個地址進來**。需要把繫結改為 `0.0.0.0`(所有介面)。

任務:把單元檔案中的 `--bind 127.0.0.1` 改為 `--bind 0.0.0.0` 並重啟。

修改單元檔案:

```
sudo vim /etc/systemd/system/lab-api.service
```

- 找到 `ExecStart=` 行中的 `--bind 127.0.0.1` 並修改。vim:`i` 輸入,`Esc` → `:wq` 儲存並退出。

重新載入更改:

```
sudo systemctl daemon-reload
```

- 修改了單元檔案,所以要讓 systemd 重新讀取。

重啟服務:

```
sudo systemctl restart lab-api
```

- 用新的繫結地址重新啟動程序。

檢視繫結地址:

```
sudo ss -ltn | grep 9090
```

- 不需要程序名,所以不加 `-p`。顯示 `0.0.0.0:9090` 表示在所有介面上接收連線。

再次透過容器 IP 連線:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # 現在成功了
```

- 再次傳送同樣的請求,確認這次是否有響應。

變為 `0.0.0.0:9090` 且透過容器 IP 能得到響應,就點選 **[驗證]**。

## 名稱解析 — hosts 與 DNS

最後一塊拼圖是 **名稱 → IP**。解析順序通常是 `/etc/hosts` → DNS(`/etc/resolv.conf` 中的域名伺服器),這個順序規則由 `/etc/nsswitch.conf` 中的 `hosts:` 行決定。

檢視 DNS 伺服器配置:

```
cat /etc/resolv.conf
```

- `nameserver` — 要查詢的 DNS 伺服器,`search` — 依次附加在短名稱後嘗試的域名列表。

檢視解析順序規則:

```
grep hosts /etc/nsswitch.conf
```

- `hosts: files dns` — 表示先查 `files`(即 `/etc/hosts`),查不到再查 `dns`。

查詢工具的用途各不相同:`nslookup`/`dig` **直接向 DNS 伺服器** 查詢,而 `getent hosts` 走的是 **系統實際的解析路徑**(包括 hosts 檔案)。應用程式看到的結果與 getent 一致。

任務:讓 lab-api 能透過 `api.lab.local` 這個名稱訪問。DNS 伺服器改不了,所以登記到 `/etc/hosts` 中。

在 hosts 檔案中登記名稱:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

- `tee -a` — 不覆蓋檔案,而是 **追加**(append)到末尾。漏掉的話整個 hosts 檔案就只剩這一行了!
- 格式:`<IP> <名稱> [別名…]`。

按系統解析路徑查詢:

```
getent hosts api.lab.local
```

- `getent hosts <名稱>` — 按 nsswitch 的順序(包括 hosts 檔案)解析名稱,與應用程式看到的結果相同。

用名稱連線:

```
curl -s http://api.lab.local:9090/status.json
```

- 用名稱而不是 IP 傳送請求。curl 也使用系統解析器,所以 `/etc/hosts` 中的條目會生效。

收到響應後點選 **[驗證]** — 模組完成。
