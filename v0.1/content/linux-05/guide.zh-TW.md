# 使用者、群組與 sudo 最小權限

伺服器上來了新同事,就要建立賬號、把他加入團隊組,並 **只按需** 開放 sudo 權限;同事離職時,則要鎖定賬號。本模組覆蓋這一整個生命週期。

先看看賬號資訊儲存在哪裡。

| 檔案 | 內容 |
|---|---|
| `/etc/passwd` | 使用者列表(名稱:x:UID:GID:說明:主目錄:shell) |
| `/etc/shadow` | 密碼雜湊 + 過期策略(只有 root 可讀) |
| `/etc/group` | 組及其成員 |
| `/etc/sudoers`、`/etc/sudoers.d/` | sudo 權限規則 |

查詢 learner 賬號:

```
getent passwd learner
```

- `getent <資料庫> <鍵>` — 透過 NSS 查詢一個條目。從 `passwd` 資料庫中輸出 `learner` 這一行。

檢視 shadow 的開頭部分:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` 只有 root 能讀,所以需要 `sudo`。第二個欄位是密碼雜湊(`*`、`!` 表示無法登入)。

> `getent` 不直接開啟檔案,而是透過 NSS(包括 LDAP 等外部來源)查詢 — 比 `cat /etc/passwd` 更準確的習慣。

## 建立使用者

建立部署專用賬號 `deploy`。要求:

- 建立主目錄(`-m` — 不加的話會得到一個沒有主目錄的賬號)
- 登入 shell 為 `/bin/bash`(`-s` — 很多發行版的預設值是 sh)

建立 deploy 使用者:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — 建立新使用者。`-m` 建立主目錄(複製 `/etc/skel` 的內容),`-s /bin/bash` 指定登入 shell,最後一個引數是使用者名稱。
- 密碼另外用 `passwd deploy` 設定(本實驗不需要)。

檢視 passwd 條目:

```
getent passwd deploy
```

- 以冒號分隔的欄位中,最後兩個是主目錄和 shell。確認是否為 `/home/deploy`、`/bin/bash`。

檢視主目錄:

```
ls -ld /home/deploy
```

- `ls -ld` — 檢視目錄 **本身**(`-d`)而不是其內容的權限和所有者。所有者應該是 `deploy`。

`useradd` 是底層工具,**什麼都不會問你**。漏了選項它也照樣建立,所以建立後必須確認。確認後點選 **[驗證]**。

## 配置組

建立運維團隊組 `ops`,並把 deploy 加進去。這裡有一個經典陷阱 —

| 命令 | 結果 |
|---|---|
| `usermod -aG ops deploy` | 把 ops **新增為附加組** ✔ |
| `usermod -G ops deploy` | 把附加組 **替換為只有 ops 一個**(原有的全部被移除!) |
| `usermod -g ops deploy` | **替換主組**(建立檔案時的預設組會改變) |

不帶 `-a`(append)的 `-G` 是通往事故的捷徑。請把它新增為附加組。

建立 ops 組:

```
sudo groupadd ops
```

- `groupadd <組>` — 建立新組,會在 `/etc/group` 中新增一行。

新增為附加組:

```
sudo usermod -aG ops deploy
```

- `usermod` — 修改已有使用者的屬性。`-G ops` 指定附加組,`-a` 表示 **追加**(append)到已有的附加組。
- 已經登入的會話需要重新登入才能生效新組。

檢視組:

```
id deploy
```

- `id <使用者>` — 在一行中顯示 UID、主組(`gid=`)和所有組(`groups=`)。

在 `id` 的輸出中,分清 `gid=`(主組)和 `groups=`(全部)。確認後點選 **[驗證]**。

## sudoers 最小權限

我們想允許 deploy 查詢服務狀態,但 **禁止更多操作**。慣例是不直接修改 `/etc/sudoers`,而是在 `/etc/sudoers.d/` 下建立附加檔案(drop-in)。

語法:`誰 在哪裡=(以誰的身份) [NOPASSWD:] 命令列表`

編寫 drop-in 規則:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo '規則' | sudo tee <檔案>` — 如果寫成 `sudo echo … > 檔案`,重定向由你自己的 shell 處理,會報權限錯誤。所以讓以 root 身份執行的 `tee` 來寫檔案。
- 規則:`deploy` 可以在所有主機(`ALL`)上、以任何身份(`(ALL)`)、無需密碼(`NOPASSWD:`)只執行 `systemctl status *`。

把權限設為 440:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — 所有者(root)和組只讀。sudo 會拒絕其他使用者可寫的 sudoers 檔案。

**語法檢查是必須的。** sudoers 一旦損壞,sudo 本身就無法使用,恢復會很麻煩。`visudo -cf` 就是這道保險。

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — 只做語法檢查(check),`-f <檔案>` — 指定要檢查的檔案。應輸出 `parsed OK`。
- 編輯 sudoers 的正規做法是用 `sudo visudo`(儲存前自動檢查)。

從 deploy 的角度確認一下能做什麼。

deploy 的 sudo 權限列表:

```
sudo -l -U deploy
```

- `sudo -l` — 列出允許的 sudo 命令,`-U deploy` — 查詢其他使用者的列表(需要 root 權限)。

允許的命令 — 應該成功:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # 允許的命令
```

- `sudo -u deploy <命令>` — 以 deploy 使用者身份執行命令。在其中再呼叫 `sudo`,測試 deploy 的 sudo 權限。
- `sudo -n` — 不詢問密碼(non-interactive)。需要詢問時會直接失敗。
- `--no-pager` — 不把輸出交給 less,直接列印。

禁止的命令 — 應該被拒絕:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # 被拒絕的命令
```

- `restart` 不在規則中,所以會被拒絕。用 `2>&1` 把錯誤資訊也送進管道,再用 `tail -1` 只看最後一行。

允許/拒絕符合預期,就點選 **[驗證]**。

## 鎖定賬號與密碼策略

`olduser` 是離職人員的賬號。刪除(`userdel`)會帶來檔案所有權清理的問題,所以通常先 **鎖定**。

鎖定賬號:

```
sudo usermod -L olduser
```

- `usermod -L` — 鎖定(Lock)賬號。在 shadow 的雜湊前加上 `!`,阻止密碼登入。解鎖用 `-U`。

檢視鎖定狀態:

```
sudo passwd -S olduser
```

- `passwd -S <使用者>` — 密碼狀態摘要。第二個欄位為 `L` 表示已鎖定,`P` 表示可用,`NP` 表示無密碼。

`passwd -S` 的第二個欄位是 `L`(locked)就說明成功了。鎖定只是在 shadow 的雜湊前加一個 `!`,隨時可以用 `-U` 恢復。

接著為 deploy 設定 **密碼最長使用期限 90 天** 的策略。

設定最長 90 天的策略:

```
sudo chage -M 90 deploy
```

- `chage` — 修改密碼過期策略(change age)。`-M 90` — 把最長使用天數設為 90 天。

檢視策略:

```
sudo chage -l deploy
```

- `chage -l` — 以列表(list)形式顯示當前策略:最後修改日期、過期日期、最長/最短期限等。

兩項都確認後點選 **[驗證]** — 模組完成。
