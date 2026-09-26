# 行程與訊號

伺服器變慢或行為異常時,首先要做的就是 **檢視程序**。本模組中你將用 ps 和 /proc 探查程序,用訊號控制程序,讓任務脫離終端在背景執行,並追查佔用埠的程序。

實驗環境中已經以 systemd 單元的形式執行著三個守護程序。

| 程序 | 身份 |
|---|---|
| `lab-worker` | 普通的工作程序 — 第 1 步的探查物件 |
| `lab-stubborn` | **會忽略 SIGTERM** 的頑固傢伙 — 第 2 步中解決它 |
| `lab-listener` | 佔用 127.0.0.1:5555 的某個東西 — 第 4 步中追查 |

## 探查程序 — ps 與 /proc

先瀏覽一下所有程序。

瀏覽完整列表:

```
ps aux | head
```

- `ps aux` — 顯示所有使用者(`a`,以及 `x`:包括沒有終端的)的程序,並附帶使用者、CPU%、MEM%、命令(`u`)。
- `| head` — 只看前 10 行。

以樹形檢視:

```
ps -ef --forest | head -30
```

- `ps -ef` — 以包含 PID、PPID 的完整格式(`-f`)顯示所有程序(`-e`)。
- `--forest` — 用縮排的樹形畫出父子關係。`head -30` 只看前 30 行。

來找一下 `lab-worker`。`pgrep -f` 會在整條命令列中匹配模式並返回 PID。

```
pgrep -f /opt/lab/bin/lab-worker
```

- `pgrep <模式>` — 只輸出名稱匹配模式的程序的 PID。
- `-f` — 不是按程序名,而是在 **整條命令列**(含路徑和引數)中查詢。

ps 顯示的所有資訊都來自 **/proc 檔案系統**。直接看看 PID 目錄裡面(cmdline 以 NUL(\0)分隔,所以用 tr 替換後再讀)。

把 PID 存入變數:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

- `$( ... )` — 命令替換。把輸出(PID)存入 shell 變數 `pid`,之後用 `$pid` 引用。
- `| head -1` — 即使匹配到多個,也只取第一個 PID。

檢視 PID 目錄內容:

```
ls /proc/$pid/
```

- `/proc/<PID>/` — 核心以檔案形式展示程序資訊的虛擬目錄。其中有 `cmdline`(執行引數)、`status`(狀態、記憶體)、`fd/`(開啟的檔案)、`environ`(環境變數)等。

讀取 cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

- `tr '\0' ' '` — 把輸入中的 NUL 字元替換(translate)為空格。
- `< 檔案` — 把檔案作為標準輸入。`; echo` 在末尾補一個換行。

任務:把結果儲存到檔案。

- `~/work/worker.pid` — lab-worker 的 PID
- `~/work/worker.cmdline` — `/proc/<PID>/cmdline` 的內容(tr 轉換後的)

建立工作目錄:

```
mkdir -p ~/work
```

- `mkdir -p` — 連同所需的上級目錄一起建立,已存在也不報錯。

儲存 PID:

```
echo "$pid" > ~/work/worker.pid
```

- `echo "$pid"` — 輸出變數的值。用 `> 檔案` 把輸出儲存(覆蓋)到檔案。

儲存 cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

- 與前面輸出到螢幕的 `tr` 命令相同,這次用 `>` 把結果儲存到檔案。

儲存好後點選 **[驗證]**。

## 用訊號控制程序

`kill` 不是殺死程序的命令,而是 **傳送訊號** 的命令。

| 訊號 | 編號 | 特點 |
|---|---|---|
| SIGTERM | 15 | 預設值。程序 **可以忽略它,或清理後再退出** |
| SIGKILL | 9 | 核心立即移除程序。**無法忽略**,沒有清理的機會 |
| SIGHUP | 1 | 按慣例常用於"重新載入配置" |

`lab-stubborn` 被寫成用 trap 忽略 TERM 和 INT。親自確認一下。

確認它是否存活:

```
pgrep -f /opt/lab/bin/lab-stubborn
```

- 輸出 PID 說明存活。什麼都沒有輸出(退出碼 1)說明沒有該程序。

傳送 SIGTERM:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

- `pkill` — 向匹配模式的程序傳送訊號(`pgrep` + `kill`)。
- `-TERM` — 要傳送的訊號(SIGTERM,15)。`-f` 在整條命令列中查詢。
- `sudo` — 這是其他使用者(root)啟動的程序,需要管理員權限。

確認它是否仍然存活:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # 仍然存活
```

- `sleep 1` — 等待 1 秒,給訊號處理留出時間,然後用 `;` 接著再次確認。

注意:這個程序由 **systemd 單元**(lab-stubborn.service)管理。只對程序 kill -9 也可以,但由單元管理的程序,按常規應在單元層面處理。不過 `systemctl stop` 會先傳送 TERM 並等待超時(預設 90 秒),對這個傢伙來說太慢了 — 請使用 **透過單元直接傳送 SIGKILL** 的方法。

透過單元傳送 SIGKILL:

```
sudo systemctl kill -s KILL lab-stubborn
```

- `systemctl kill <單元>` — 向單元中的 **所有程序** 傳送訊號。
- `-s KILL` — 把要傳送的訊號設為 SIGKILL(9)。程序無法攔截,會被立即移除。

確認已終止:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "terminated"
```

- `A || B` — 只有 A 失敗(退出碼 ≠ 0)時才執行 B。`pgrep` 什麼都沒找到時就會輸出這條訊息。

確認它已終止後點選 **[驗證]**。

## 脫離會話的背景執行

在終端中用 `&` 啟動的程序,在終端斷開時會收到 SIGHUP 並一起終止。要讓它在會話結束後依然存活,需要使用 **nohup**(忽略 HUP + 重定向輸出)或 **setsid**(脫離到新會話)。

`/opt/lab/bin/lab-batch` 是一個批處理任務,每 10 秒向第一個引數指定的檔案寫入時間戳。請讓它脫離終端啟動,並把日誌寫到 `~/work/batch.log`。

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

- `nohup <命令>` — 讓命令忽略 SIGHUP,終端關閉後仍繼續執行。
- `>/dev/null 2>&1` — 丟棄標準輸出,並把標準錯誤(2)也送到與標準輸出(1)相同的地方。
- 末尾的 `&` — 在背景執行,並立即返回提示符。

檢視一下父程序。脫離 shell 成為孤兒程序後,會被 PID 1(在 Pod 中是 systemd)收養。

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

- `ps -o pid,ppid,cmd` — 把輸出列指定為 PID、父 PID、命令。
- `-p $(pgrep ...)` — 只查詢透過命令替換得到的 PID 的程序。

檢視日誌:

```
tail ~/work/batch.log
```

- `tail <檔案>` — 檔案末尾 10 行。要持續跟蹤用 `tail -f`(Ctrl+C 退出)。

PPID 為 1 且日誌在不斷增加,就點選 **[驗證]**。

> 實際工作中,比起這種臨時守護程序,systemd 單元(或 `systemd-run`)才是正解 — 在 linux-06 模組中介紹。

## 追查佔用埠的程序

"這個埠被誰佔著?"是最常見的診斷問題。用 `ss`(socket statistics)找出 5555 埠的主人。要看到程序名需要 `-p`,其他使用者的程序需要 sudo 才能看到。

檢視所有監聽套接字:

```
sudo ss -ltnp
```

- `ss` — 檢視套接字狀態(netstat 的繼任者)。`-l` 只看監聽套接字,`-t` TCP,`-n` 埠以數字而非名稱顯示,`-p` 連同開啟套接字的程序一起顯示。

只查詢 5555 埠:

```
sudo ss -ltnp sport = :5555
```

- `sport = :5555` — 過濾表示式,只顯示源(本地)埠為 5555 的套接字。

用 `lsof` 也能得到同樣的答案。

```
sudo lsof -i :5555
```

- `lsof` — 列出開啟的檔案(在 Linux 中套接字也是檔案)。`-i :5555` — 只看使用 5555 埠的網路連線。

任務:把佔用 5555 埠的 **程序名** 儲存到 `~/work/port-owner.txt`。

提取並儲存程序名:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

- `grep -o` — 不輸出整行,**只輸出匹配的部分**。從 `users:(("python3",pid=…))` 中只取出名稱。
- 用 `head -1` 只留一個,再用 `>` 儲存。

檢視儲存的內容:

```
cat ~/work/port-owner.txt
```

- `cat <檔案>` — 原樣輸出檔案內容。

如果好奇這個 python3 到底是什麼,就用 PID 再去翻一翻 /proc — 正是第 1 步學到的方法。儲存好後點選 **[驗證]**。
