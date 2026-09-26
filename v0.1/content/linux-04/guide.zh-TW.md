# Bash 指令碼

當某條單行命令開始被反覆使用時,就該把它寫成腳本了。本模組要學的不是 **永遠不死的腳本,而是一出問題就立刻終止(fail-fast)的腳本** — 因為悄無聲息地給出錯誤結果的腳本才是最危險的。

所有檔案都寫在 `~/work/` 下。編輯器用 vim 或 nano 都可以,也可以用 `cat > 檔案 <<'EOF'` 這樣的 heredoc 來建立。

## 安全的腳本骨架

所有腳本的前兩行基本上是固定的。

```
#!/bin/bash
set -euo pipefail
```

| 選項 | 效果 |
|---|---|
| `-e` | 命令失敗時立即退出 |
| `-u` | 引用未定義的變數時報錯(防止拼寫錯誤) |
| `-o pipefail` | 管道中間某一步失敗也視為失敗 |

任務:編寫 `~/work/sysinfo.sh`。要求:

- bash 的 shebang + `set -euo pipefail`
- 輸出一行 `host=<主機名>` 和一行 `uptime=<秒數>`
- 可執行權限

編寫腳本:

```
cat > ~/work/sysinfo.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
EOF
```

- `cat > 檔案 <<'EOF'` … `EOF` — heredoc。把兩個 `EOF` 之間的各行作為 `cat` 的輸入,再用 `>` 儲存到檔案。像 `'EOF'` 這樣加上引號,正文中的 `$(...)` 就不會現在執行,而是按原樣儲存。
- `#!/bin/bash` — shebang,告訴核心用哪個直譯器來執行這個檔案。
- `$(uname -n)` — 主機名,`awk '{print $1}' /proc/uptime` — 開機後經過的秒數(第一個欄位)。

賦予執行權限:

```
chmod +x ~/work/sysinfo.sh
```

- `chmod +x` — 新增執行(x)權限。沒有它,用 `./腳本` 執行時會報 `Permission denied`。

執行一下:

```
~/work/sysinfo.sh
```

- 透過路徑直接執行時,由 shebang 中的 `/bin/bash` 來執行腳本(用 `bash 檔案` 執行則不需要執行權限)。

確認執行正常後點選 **[驗證]**。

## 引數處理與退出碼

腳本的引數透過 `$1 $2 …` 接收,引數個數是 `$#`。慣例是:呼叫方式不對時,**把 usage 輸出到 stderr,並以非 0 的退出碼結束** — 因為呼叫方(其他腳本、CI)必須能察覺到失敗。

任務:編寫 `~/work/logcut.sh <日誌檔案> <狀態碼>`。

- 在 `/opt/lab/data/app.log` 格式(`… status=200 msg=…`)中,輸出對應狀態碼的行數
- 引數不是 2 個時輸出 usage + 退出碼 2

編寫腳本:

```
cat > ~/work/logcut.sh <<'EOF'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
grep -c "status=$2 " "$1" || true
EOF
```

- `usage() { …; }` — 定義函式。`>&2` 把訊息輸出到標準錯誤,`exit 2` 以退出碼 2 結束。
- `[ $# -eq 2 ] || usage` — 引數個數(`$#`)不是 2 時(`||`)呼叫 usage。`[ ]` 是檢查條件的命令(`test`)。
- `grep -c "status=$2 " "$1"` — 第二個引數所指狀態碼的行數。變數用雙引號括起來,即使路徑含空格也安全。

賦予執行權限:

```
chmod +x ~/work/logcut.sh
```

- 每個新腳本都要賦予執行權限。

> `grep -c` 匹配為 0 條時會返回 **退出碼 1**。在 `set -e` 下腳本會因此直接終止,所以用 `|| true` 明確表示"0 條也是正常的" — 既要開啟 fail-fast,又不能把不是失敗的情況當成失敗,這種分寸感很重要。

測試後點選 **[驗證]**。

正常呼叫 — 輸出 500 的行數:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

- 第一個引數進入 `$1`(日誌檔案),第二個引數進入 `$2`(狀態碼)。

不帶引數呼叫 — 確認退出碼為 2:

```
~/work/logcut.sh; echo "exit=$?"
```

- `$?` — 上一條命令的退出碼。用 `;` 接著執行,確認 usage 之後的退出碼是否為 2。

## 用 trap 保證清理

建立臨時檔案的腳本如果中途終止,就會留下垃圾。`trap '…' EXIT` 是一個清理鉤子,**無論正常結束還是出錯**,腳本結束時都一定會執行。

任務:編寫 `~/work/withtmp.sh`。

- 用 `mktemp -d` 建立臨時目錄,並在其中隨便建立一個檔案
- 用 `trap` 在退出時刪除臨時目錄
- 把臨時目錄的路徑作為 **最後一行輸出**(驗證時會檢查這個路徑是否已被刪除)

編寫腳本:

```
cat > ~/work/withtmp.sh <<'EOF'
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
date > "$tmp/scratch.txt"
echo "$tmp"
EOF
```

- `mktemp -d` — 建立一個名稱不會重複的臨時目錄,並輸出其路徑。
- `trap '命令' EXIT` — 無論腳本因何結束,都會在退出前執行該命令。這裡是刪除臨時目錄。
- `rm -rf "$tmp"` — 連同內容(`-r`)不經確認(`-f`)刪除目錄。trap 的正文用的是單引號,所以 `$tmp` 在執行時才展開。

賦予執行權限:

```
chmod +x ~/work/withtmp.sh
```

- 賦予執行權限。

執行後確認已刪除:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # 出現 "No such file" 才是正常
```

- `d=$(腳本)` — 把腳本的輸出(臨時路徑)存入變數 `d`。
- `ls -d "$d"` — 查詢目錄本身。用 `2>&1` 讓錯誤資訊也顯示在螢幕上。目錄已被刪除,所以出現 `No such file` 是正常的。

確認後點選 **[驗證]**。

## 修復出故障的腳本

最後是現實中最常做的事 — **修別人寫的腳本**。`/opt/lab/bin/backup.sh` 是把目錄備份到 /tmp 的腳本,但路徑中 **一有空格** 就會失敗。

檢視腳本內容:

```
cat /opt/lab/bin/backup.sh
```

- 修之前先讀。找找看沒加引號就使用的 `$src`、`$dest`。

準備含空格路徑的測試目錄:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

- 路徑中有空格,所以用雙引號括起來作為一個引數傳入。再用 `;` 接著建立一個測試檔案。

用含空格的路徑執行:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # 失敗!
```

- 呼叫時用引號傳入了一個引數,但腳本內部一旦不加引號使用 `$src`,它又會被拆成兩個單詞(單詞拆分)。

原因是 **沒有加引號(quoting)的變數展開**。`$src` 為 `/tmp/my app` 時,`cp -r $src/*` 會被拆成 `/tmp/my` 和 `app/*` 兩個引數。這是 shell 腳本 bug 中經典中的經典。

任務:複製為 `~/work/backup-fixed.sh` 後修復。

- 所有變數展開都用 `"…"` 括起來(`"$dest"`、`"$src"/*` — 萬用字元 `*` 要放在引號外面!)
- 新增 `set -euo pipefail`
- 用含空格的路徑執行,確認成功

建立副本:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

- `cp <源> <目標>` — 保留原檔案不動,在自己的工作目錄中建立副本。

用編輯器修改:

```
vim ~/work/backup-fixed.sh
```

- vim:按 `i` 進入輸入模式,改完後 `Esc` → `:wq` 儲存並退出。不熟悉的話也可以用 `nano`(`Ctrl+O` 儲存,`Ctrl+X` 退出)。

用含空格的路徑執行確認:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

- `A && B` — 只有 A 成功(退出碼 0)時才執行 B。看到 `OK` 就說明修復成功。

成功後點選 **[驗證]** — 模組完成。
