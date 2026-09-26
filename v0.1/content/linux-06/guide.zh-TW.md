# systemd 服務與 journald

在 linux-02 中我們用 nohup 啟動了守護程序,但實際工作中的守護程序全都是 **systemd 單元** — 開機自動啟動、掛掉後自動重啟、日誌由 journald 自動收集。本模組中你將親手編寫單元,用 journal 診斷並修復出故障的單元,並用定時器取代 cron。

先瀏覽一下當前系統的單元。

瀏覽服務單元列表:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — 已載入到記憶體的單元列表。`--type=service` 只看服務,`--no-pager` 不經 less 直接輸出。
- `| head -15` — 只看前 15 行。列依次為 LOAD(檔案載入)、ACTIVE(總體狀態)、SUB(詳細狀態)。

檢視 cron 服務狀態:

```
systemctl status cron --no-pager
```

- `systemctl status <單元>` — 在一屏中顯示狀態(`Active:`)、主 PID、cgroup 程序樹以及最近幾行日誌。

## 編寫服務單元

最小的服務單元只需要三個段。

| 段 | 作用 |
|---|---|
| `[Unit]` | 描述、依賴關係(Description、After 等) |
| `[Service]` | 執行方式(ExecStart、Restart、User 等) |
| `[Install]` | enable 時掛到哪裡(WantedBy) |

任務:建立在 8080 埠執行靜態 HTTP 伺服器的 `hello-web.service`。

```
sudo tee /etc/systemd/system/hello-web.service <<'EOF'
[Unit]
Description=hello web

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 127.0.0.1

[Install]
WantedBy=multi-user.target
EOF
```

- `sudo tee <檔案> <<'EOF'` — 由以 root 權限執行的 `tee` 把 heredoc 正文寫入檔案(`sudo cat > 檔案` 的重定向由你自己的 shell 處理,會報權限錯誤)。
- `/etc/systemd/system/` — 管理員建立的單元檔案存放位置,優先於軟體包自帶的單元(`/usr/lib/systemd/system/`)。
- `ExecStart=` — 要執行的命令(絕對路徑)。`WantedBy=multi-user.target` — enable 後會掛到常規啟動目標上。

建立或修改單元檔案後,**一定要 daemon-reload** — systemd 不會直接讀檔案,而是使用已載入到記憶體中的副本。

重新載入更改:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — 讓 systemd 重新讀取單元檔案。不會重啟服務。

註冊開機啟動 + 立即啟動:

```
sudo systemctl enable --now hello-web
```

- `enable` — 在 `WantedBy` 目標中建立符號連結,實現開機自動啟動;`--now` — 同時立即執行 `start`。
- 單元名的 `.service` 字尾可以省略。

檢視服務狀態:

```
systemctl status hello-web --no-pager
```

- 看到 `Active: active (running)` 和主 PID(`python3`)就說明啟動正常。

檢視響應:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — 不顯示進度地傳送 HTTP 請求並輸出響應正文。`| head -3` 只看前 3 行(目錄列表 HTML)。

`enable --now` 的意思是"註冊開機自動啟動 + 現在就啟動"。確認有響應後點選 **[驗證]**。

## 用 journald 修復出故障的單元

系統中部署了一個名為 `lab-report.service` 的單元,但啟動失敗。親自看看。

嘗試啟動服務:

```
sudo systemctl start lab-report
```

- `systemctl start` — 立即啟動服務(與開機註冊無關)。失敗時會輸出 `Job … failed` 的訊息,並提示可用於排查的命令。

檢視失敗狀態:

```
systemctl status lab-report --no-pager
```

- 透過 `Active: failed` 和 `code=exited, status=…` 這一行確認失敗原因程式碼。

原因調查要用 **journalctl**。用 `-u` 指定單元,再配合 `-e`(跳到末尾)或 `--no-pager`。

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — 檢視 journald 日誌。`-u <單元>` 只看該單元的日誌,`--no-pager` 直接輸出,`| tail -20` 最近 20 行。
- 實時跟蹤用 `-f`,只看本次啟動用 `-b`,時間範圍用 `--since "10 min ago"`。

你會看到 `status=203/EXEC` — 這是 systemd 退出碼中的經典,意思是 **無法執行 ExecStart 中的可執行檔案**(路徑拼寫錯誤、沒有執行權限、shebang 問題)。把單元指向的路徑和實際檔案對照一下。

檢視單元指向的路徑:

```
systemctl cat lab-report
```

- `systemctl cat <單元>` — 顯示 systemd 實際使用的單元檔案(含 drop-in)的內容和路徑。看看 `ExecStart=` 這一行。

檢視實際檔案:

```
ls -l /opt/lab/bin/
```

- `ls -l` — 同時檢視檔名和權限(有沒有 `x`)。與單元中的路徑逐字比對。

任務:修正 ExecStart 路徑(別忘了 daemon-reload)並啟動服務。

修改單元檔案:

```
sudo vim /etc/systemd/system/lab-report.service
```

- 單元檔案屬於 root,所以用 `sudo` 開啟。vim:`i` 輸入,`Esc` → `:wq` 儲存並退出。
- 修改後如果忘了 `daemon-reload`,systemd 會繼續用舊路徑失敗。

重新載入更改:

```
sudo systemctl daemon-reload
```

啟動服務:

```
sudo systemctl start lab-report
```

實時檢視日誌:

```
tail -f /var/log/lab/report.log   # 用 Ctrl-C 退出
```

- `tail -f` — 持續跟蹤(follow)檔案末尾,每出現新行就輸出。用於確認服務是否真的在工作。

變為 active(running)後點選 **[驗證]**。

## 用 Restart 策略自愈

程序總會掛掉 — OOM、bug、失誤。systemd 的 `Restart=` 就是在那時自動把它拉起來的安全網。

| 值 | 重啟條件 |
|---|---|
| `no`(預設) | 不重啟 |
| `on-failure` | 僅在異常退出(退出碼≠0、訊號)時 |
| `always` | 即使正常退出也一律重啟 |

任務:給 hello-web 新增 `Restart=on-failure` 和 `RestartSec=1`。可以直接修改單元檔案,也可以採用不動原檔案的 **drop-in** 方式(`systemctl edit` 是互動式的,這裡直接寫檔案)。

建立 drop-in 目錄:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<單元>.d/` — drop-in 目錄。其中的 `*.conf` 檔案會覆蓋在原單元之上。即使軟體包更新了原檔案,你的配置也能保留。

編寫 drop-in 檔案:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- 只寫要加到 `[Service]` 段的鍵。`Restart=on-failure` 異常退出時重啟,`RestartSec=1` 重啟前等待 1 秒。

重新載入更改:

```
sudo systemctl daemon-reload
```

重啟服務:

```
sudo systemctl restart hello-web
```

- `restart` — 先 stop 再 start。程序會在應用了新配置(drop-in)的狀態下重新啟動。

來實驗一下是否真的會自動恢復。用 SIGKILL 殺掉主 PID,幾秒後檢視狀態。

檢視主 PID:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — 以 `鍵=值` 形式輸出單元屬性。`-p MainPID` 只取一個屬性,`--value` 只輸出值,不帶 `MainPID=`。

強制終止程序:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- 對透過 `$( ... )` 獲得的主 PID 執行 `kill -9`(SIGKILL)— 無法攔截的強制終止。這屬於"異常退出",因此適用 `on-failure`。

稍等片刻後檢視狀態:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- 用 `sleep 3` 給重啟(RestartSec=1)留出時間,然後檢視狀態的前 5 行。`Main PID` 應該和之前不同。

PID 變了且再次處於 active 就說明成功 — 點選 **[驗證]**。(校驗也會再做一次同樣的實驗。)

## 用定時器執行週期任務

cron 在 systemd 中的替代品就是 **定時器**。日誌會留在 journal 中,失敗也能作為單元來管理,所以如今發行版中的定期任務大多是定時器。它由 **服務(做什麼)+ 定時器(何時做)** 一對組成。

任務:建立 `lab-tick` 定時器,每分鐘把當前時間記錄到 `/var/log/lab/tick.log`。

編寫服務單元(做什麼):

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — 執行完就結束的任務。命令結束即視為成功,並回到非活動狀態。
- `bash -c '…'` — 重定向(`>>`,追加寫入)是 shell 的功能,所以要經由 bash 執行。`date -Is` 輸出 ISO 8601 格式的時間。

編寫定時器單元(何時做):

```
sudo tee /etc/systemd/system/lab-tick.timer <<'EOF'
[Unit]
Description=lab tick every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
```

- `OnCalendar=*-*-* *:*:00` — `年-月-日 時:分:秒` 形式的日曆表示式。每天每小時每分鐘的第 0 秒 = 每分鐘一次。
- `AccuracySec=1s` — 把執行時間的允許誤差(預設 1 分鐘)縮小到 1 秒。
- 定時器會執行同名的 `.service`(這裡是 `lab-tick.service`)。透過 `WantedBy=timers.target` 進行 enable。

重新載入更改:

```
sudo systemctl daemon-reload
```

註冊並啟動定時器:

```
sudo systemctl enable --now lab-tick.timer
```

- 名稱要寫全到 `.timer`。省略的話會被當作 `.service`。

`Type=oneshot` 用於"執行一次就結束"的任務。注意 enable 的物件是 **timer 而不是 service**。確認註冊狀態後點選 **[驗證]**,模組即完成。

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — 活動定時器的下次(`NEXT`)和上次(`LAST`)執行時間。
- `grep -E 'NEXT|lab-tick'` — 只保留表頭行和 lab-tick 那一行(`|` 是擴充套件正則中的"或")。
