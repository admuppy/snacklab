# 綜合 —— 救活掛掉的服務

凌晨 2 點,告警響了:**"lab-app 起不來。"** 本模組是一個綜合場景,要調動至今學過的所有知識(systemd、journald、訊號與埠追蹤、檔案權限),從頭到尾處理一次真實的故障。

這次不會把命令一條條告訴你 — **診斷順序** 才是本模組的學習目標。卡住時,回想一下之前模組中的工具:`systemctl status/cat`、`journalctl -u`、`sudo ss -ltnp`、`ls -l`、`sudo -u <使用者>`。

先掌握一下現狀。

```
systemctl status lab-app --no-pager
```

- 從 `Active:` 行(狀態)和最後幾行日誌中尋找第一條線索。`--no-pager` 不經 less 直接輸出。

## 診斷啟動失敗 — 203/EXEC

只看 status 不夠的話,journal 知道答案。

```
journalctl -u lab-app --no-pager | tail -20
```

- `journalctl -u <單元>` — 只看該單元的日誌。用 `| tail -20` 聚焦在最近 20 行。

`status=203/EXEC` — 就是在 linux-06 中見過的那個程式碼。確認單元 **試圖執行什麼** 而失敗了。

```
systemctl cat lab-app
```

- 原樣檢視單元檔案內容。留意 `ExecStart=`(執行什麼)和 `User=`(以誰的身份執行)。

對照一下 ExecStart 中直譯器的路徑在這個系統上是否真的存在(`ls /usr/bin/python3*`)。它應該指向了一個不存在的版本 — 部署腳本是按另一臺伺服器寫的,這是常見的事故。

任務:把 ExecStart 改成實際存在的直譯器,並執行 `daemon-reload`。改好後點選 **[驗證]**。

> start 還不會成功 — 故障通常不止一層。進入下一步。

## 解決埠衝突

現在 start 會報另一個錯誤。

嘗試啟動服務:

```
sudo systemctl start lab-app
```

- 修復後再啟動一次試試。如果失敗,接下來的日誌會告訴你新的原因。

檢視錯誤日誌:

```
journalctl -u lab-app --no-pager | tail -5
```

- 只需要看這次嘗試的日誌,所以看最後 5 行。

`Address already in use` — lab-app 要用的 8080 被 **別人搶先佔用了**。用在 linux-02、07 中學到的埠追蹤方法找出元兇。

```
sudo ss -ltnp | grep 8080
```

- 找出在 8080 上監聽的套接字及其程序(`users:(("名稱",pid=…))`)。記下 PID。

要從 PID 反查單元,`systemctl status <PID>` 很方便。元兇是一個即將廢棄的遺留單元。只停止的話重啟後它還會復活,所以 **還必須 disable**。

任務:用 `disable --now` 關掉搶佔埠的單元,然後啟動 lab-app。lab-app 變為 active 後點選 **[驗證]**。

## 解決權限問題

服務起來了……但還沒結束。

```
curl -i http://127.0.0.1:8080/index.html
```

- `curl -i` — 在響應正文之前一併(include)輸出狀態行(`HTTP/1.0 404 …`)和響應頭。

**404** — 可是檔案明明存在(`ls -l /srv/lab-app/`)。為什麼?

線索有兩條。① 單元中有 `User=labapp` — 服務不是以 root,而是以 labapp 身份執行。② index.html 是 `root:root 600` — **labapp 讀不了它。** 這個伺服器(http.server)打不開檔案時就會返回 404。這是"檔案存在卻 404"的典型權限問題。

養成驗證猜想的習慣 — 以那個使用者的身份直接讀一下。

```
sudo -u labapp cat /srv/lab-app/index.html
```

- `sudo -u <使用者> <命令>` — 以該使用者的權限執行命令。這是用與服務相同的權限讀取檔案的驗證方法。

任務:修改所有權或權限,讓 labapp 能讀取(用 linux-01 的思路 — 不要放開得超出必要)。curl 返回 `LAB APP OK` 後點選 **[驗證]**。

## 防止復發與收尾

恢復工作要做到"現在能用" + **"下次也能用"** 才算完整。檢查清單:

1. lab-app 是否處於 **enable** 狀態?(重啟後又掛掉的恢復不算恢復)
2. 把最終響應留作證據 — 儲存到 `~/work/final.txt`

註冊開機自動啟動:

```
sudo systemctl enable lab-app
```

- `enable` — 註冊開機自動啟動(建立符號連結)。對當前正在執行的服務沒有影響。可用 `systemctl is-enabled lab-app` 確認。

儲存最終響應:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

- 用 `>` 把 `curl -s` 收到的響應正文儲存到檔案。

檢視儲存的內容:

```
cat ~/work/final.txt
```

- 確認儲存的響應是 `LAB APP OK`。

點選 **[驗證]** 就完成了 Linux 路線。請記住:今天處理的三重故障(錯誤的路徑 → 埠衝突 → 權限)是真實故障報告中最常見的組合,而且這三者 **journal、ss 和 ls -l 早就知道了**。
