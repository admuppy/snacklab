# 檔案權限與特殊權限

Linux 安全的第一步是 **檔案權限**。本模組涵蓋基本權限(rwx)與 umask、setgid 和 sticky bit 等特殊權限、用 ACL 做細粒度訪問控制,最後是在真實系統上找出並修復危險權限的審計。

先確認一下當前使用者。`learner` 是可以使用 sudo 的普通使用者。

```
id
```

- `id` — 顯示當前使用者的 UID、主組(`gid`)以及所屬的全部組(`groups`)。

你需要能在兩種權限表示法之間自如切換。

| 表示法 | 示例 | 含義 |
|---|---|---|
| 符號 | `rwxr-x---` | 所有者 rwx / 組 r-x / 其他人 無 |
| 八進位制 | `750` | r=4、w=2、x=1 之和 |

## 基本權限與 umask

建立檔案時的預設權限由 **umask** 決定。

檢視當前 umask 值:

```
umask
```

- `umask` — 從新建檔案/目錄中 **去掉** 的權限位。常見的 `0022` 會去掉組和其他人的寫(w)權限 → 檔案 644,目錄 755。

建立一個檔案,看看它實際以什麼權限生成:

```
touch /tmp/t1 && stat -c %a /tmp/t1
```

- `touch` — 建立空檔案(已存在則只更新修改時間)。`&&` — 前一條命令成功才接著執行。
- `stat -c %a` — 用格式指定(`-c`)只輸出八進位制權限(`%a`)。

現在建立一個只有你能訪問的工作區。要求:

- `~/work` 目錄 — 權限 **700**(只有所有者 rwx)
- `~/work/secret.txt` 檔案 — 內容隨意,權限 **600**(只有所有者 rw)

建立工作目錄並設為 700:

```
mkdir -p ~/work && chmod 700 ~/work
```

- `mkdir -p` — 連同上級路徑一起建立,已存在也不報錯。
- `chmod 700` — 用八進位制指定權限:所有者 rwx(7),組和其他人無(0)。

建立秘密檔案:

```
echo "top secret" > ~/work/secret.txt
```

- `echo "…" > 檔案` — 把字串寫入檔案(不存在則建立,存在則覆蓋)。新檔案的權限遵循 umask。

把檔案權限設為 600:

```
chmod 600 ~/work/secret.txt
```

- `600` — 所有者 rw(6 = 4+2),組和其他人無。符號寫法為 `chmod u=rw,go= <檔案>`。

用 `stat` 確認後點選 **[驗證]**。

```
stat -c '%a %n' ~/work ~/work/secret.txt
```

- `%a` 為八進位制權限,`%n` 為檔名。傳入多個檔案時每個輸出一行。

> 目錄的 `x` 是"透過(進入)權限"。即使目錄有 `r`,沒有 `x` 也無法訪問其中的檔案 — 在第 3 步 ACL 中還會遇到。

## setgid 與 sticky bit

建立團隊共享目錄時常用的兩種特殊權限:

| 位 | 八進位制 | 對目錄的效果 |
|---|---|---|
| setgid | 2000 | 在其中建立的檔案 **繼承目錄的組** |
| sticky | 1000 | 只有 **所有者** 才能刪除檔案(與 `/tmp` 相同) |

建立 `share` 組的共享目錄 `/srv/share`。要求:

- 建立組:`share`
- `/srv/share` 目錄,所屬組為 `share`
- 權限 **3775** = setgid(2000)+ sticky(1000)+ 775

建立組:

```
sudo groupadd -f share
```

- `groupadd` — 建立組。`-f` 表示即使已存在也不報錯,以成功結束。

建立共享目錄:

```
sudo mkdir -p /srv/share
```

- `/srv` 屬於 root,所以要用 `sudo` 建立。

把所屬組改為 share:

```
sudo chgrp share /srv/share
```

- `chgrp <組> <路徑>` — 只修改所屬組。連所有者也改的話用 `chown 使用者:組`。

連同特殊權限設為 3775:

```
sudo chmod 3775 /srv/share
```

- 四位八進位制數的第一位是特殊位:`3` = setgid(2)+ sticky(1)。其餘 `775` 為所有者和組 rwx,其他人 r-x。

看看結果。在符號表示中,setgid 顯示為組位置上的 `s`,sticky 顯示為最後一位的 `t`(`drwxrwsr-t`)。

檢視權限和所屬組:

```
stat -c '%a %G %n' /srv/share
```

- `%G` — 所屬組的名稱。

檢視符號表示:

```
ls -ld /srv/share
```

- `ls -ld` — 以符號形式(`drwxrwsr-t`)顯示目錄 **本身**(`-d`),而不是其內容。

確認無誤後點選 **[驗證]**。

## 用 ACL 做細粒度訪問控制

`rwx` 只有所有者/組/其他人三欄。"只允許 **某一個特定使用者** 讀取這個檔案"要用 **ACL**(Access Control List)來解決。

系統中已經準備了審計賬號 `audit`。請把第 1 步建立的 `~/work/secret.txt` 以 **只讀** 方式開放給 audit。

授予 audit 讀取 ACL:

```
setfacl -m u:audit:r ~/work/secret.txt
```

- `setfacl -m` — 新增/修改(modify)ACL 條目。格式為 `u:<使用者>:<權限>`(組用 `g:`)。

檢視設定的 ACL:

```
getfacl ~/work/secret.txt
```

- `getfacl` — 顯示檔案的所有者、組、全部 ACL 條目以及 `mask`(ACL 的最大允許權限)。

但這還沒完 — audit 要 **到達** 這個檔案,必須能透過路徑上的目錄(`~` 和 `~/work`)。700 的目錄會擋住 audit。

只用 ACL 開放透過(x)權限:

```
setfacl -m u:audit:x ~ ~/work
```

- 目錄只給 `x`,表示只允許 **透過**,而不能列出內容(r)。一次作用於兩個路徑(`~`、`~/work`)。

從 audit 的角度驗證一下是否真的可行。

讀取 — 應該成功:

```
sudo -u audit cat ~/work/secret.txt
```

- `sudo -u <使用者> <命令>` — 以其他使用者身份執行命令,驗證實際權限。

寫入 — 應該失敗:

```
sudo -u audit sh -c 'echo x >> ~learner/work/secret.txt'
```

- `sh -c '…'` — 以 audit 身份啟動整個 shell,讓重定向(`>>`)也以 audit 的權限執行。
- `~learner` — learner 使用者的主目錄(對 audit 來說 `~` 是它自己的主目錄)。

設定了 ACL 的檔案,在 `ls -l` 中權限後面會帶一個 `+`。確認後點選 **[驗證]**。

## 權限審計與修復

最後是實戰任務。帶有 **SUID**(4000)位的可執行檔案會以所有者(通常是 root)的權限執行,因此是審計的頭號物件。

在整個系統中查詢 SUID 檔案並儲存:

```
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt
```

- `find /` — 從根目錄遞迴查詢。`-xdev` — 不跨入其他檔案系統(/proc 等)。
- `-perm -4000` — **包含** SUID 位的檔案(`-` 表示"具有這些位的全部")。`-type f` — 只要普通檔案。
- `> ~/work/suid.txt` — 把結果列表儲存到檔案。

檢視列表:

```
cat ~/work/suid.txt
```

- `cat` — 輸出儲存的 SUID 檔案列表。

想一想 `passwd` 為什麼是 SUID — 因為普通使用者需要更新屬於 root 的 `/etc/shadow`。

第二個任務:`/opt/lab/perm/danger.conf` 是包含資料庫密碼的配置檔案,卻以 **666**(任何人都可讀寫!)的權限部署了。

檢視當前權限:

```
ls -l /opt/lab/perm/
```

- `ls -l` — 檢視權限(`-rw-rw-rw-` = 666)以及所有者和組。

修復為 640:

```
sudo chmod 640 /opt/lab/perm/danger.conf
```

- `640` — 所有者 rw,組 r,其他人無。保留應用透過組權限讀取,其餘全部堵上。

修復後點選 **[驗證]**,模組即完成。
