# CPU 與記憶體管理

接到伺服器變慢的報告時,首先要看的就是 **CPU 和記憶體**。本模組從觀察資源的工具開始,到調整程序優先順序,再到容器/Pod 的實際上限 — **cgroup 記憶體限制與 OOM**。

> 這個實驗環境是執行著 systemd 的 **容器(Pod)**。資源限制也以與真實 k8s Pod 相同的方式(由 systemd 管理的 cgroup v2)處理 — 與物理伺服器不同的地方會隨時指出。

先大致看看當前狀態。

檢視 CPU 數量:

```
nproc
```

- `nproc` — 當前程序可以使用的 CPU(核)數量。在容器中,這個值已反映了 cgroup 和親和性限制。

檢視記憶體情況:

```
free -h
```

- `free` — 記憶體與交換空間的使用量。`-h` 以 Gi/Mi 為單位顯示。
- `available` 列表示"新程序實際能用到的量"(含可回收的快取),比 `free` 列更重要。

每隔 1 秒彙總 3 次:

```
vmstat 1 3
```

- `vmstat <間隔> <次數>` — 每隔 1 秒輸出一次,共 3 次。第一行是開機以來的平均值,所以從第二行開始看。
- `r` 等待執行的程序數,`si/so` 交換換入/換出,`us/sy/id/wa` CPU 使用者態/核心態/空閒/IO 等待的比例。

來一張 top 快照:

```
top -b -n1 | head -12
```

- `top -b` — 以文字方式輸出(batch),而不是互動介面,`-n1` — 只輸出一次。`| head -12` 只看彙總區和前幾個程序。

## 觀察資源

`free` 彙總記憶體,`vmstat` 把記憶體、交換空間和 CPU 彙總成一行。原始數值在 `/proc/meminfo` 和 `/proc/cpuinfo` 中。

| 命令 | 看什麼 |
|---|---|
| `free -h` | 總/已用/可用記憶體、swap |
| `vmstat 1` | 每秒的記憶體、swap in/out(si/so)、CPU |
| `nproc` | 此環境中可用的 CPU 數量 |
| `cat /proc/meminfo` | MemTotal、MemAvailable 等原始資料 |

任務:把當前記憶體總量和 CPU 數量儲存為快照。在 `~/work/snapshot.txt` 中儲存 **/proc/meminfo 的 MemTotal 行** 和 **`cpus=<nproc 的值>`** 行。

準備工作目錄:

```
mkdir -p ~/work
```

- `mkdir -p` — 連同上級目錄一起建立,已存在也不報錯。

儲存 MemTotal 行:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — 只挑出總記憶體那一行,用 `>` 儲存到檔案(新寫入)。

追加 cpus 行:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — 雙引號中的 `$( )` 同樣會被替換,得到 `cpus=4` 這樣的字串。
- `>>` — **追加** 到檔案末尾(`>` 是覆蓋)。

檢視儲存的內容:

```
cat ~/work/snapshot.txt
```

- 確認是否包含兩行(MemTotal、cpus=…)。

記錄好後點選 **[驗證]**。

## 優先順序與 CPU 親和性

CPU 不夠用時,不可能對所有程序一視同仁。用 **nice 值**(-20 最高 ~ 19 最低)設定排程優先順序,用 **taskset** 決定程序在哪個核上執行(CPU 親和性)。

| 命令 | 作用 |
|---|---|
| `nice -n 19 CMD` | 以低優先順序啟動新程序 |
| `renice -n 5 -p PID` | 修改執行中程序的 nice 值 |
| `taskset -c 0 CMD` | 固定在 0 號 CPU 上執行 |
| `taskset -pc PID` | 檢視/修改執行中程序的親和性 |

任務:把消耗 CPU 的負載(`stress-ng --cpu 1`)**固定在 0 號 CPU** 上,以 **nice 19**(最謙讓的優先順序)在背景執行。這是在不影響其他服務的前提下執行批處理任務的典型做法。

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <命令>` — 把命令固定在 0 號 CPU 上執行(`-c` 是 CPU 編號列表,如 `0,2` 或 `0-3`)。
- `nice -n 19 <命令>` — 以 nice 值 19(最低優先順序)執行。這兩個包裝命令可以疊加使用。
- `stress-ng --cpu 1 --timeout 1800s` — 讓一個 CPU 以 100% 執行 30 分鐘的負載生成器。
- `>/dev/null 2>&1 &` — 丟棄輸出並在背景執行。

確認它是否真的這樣啟動了。看看 `top` 中 `NI` 列是否為 19、親和性是否為 CPU 0。

儲存負載程序的 PID:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — 在整條命令列中用正規表示式查詢(`.*` 表示任意多個字元)。用 `head -1` 只把第一個 PID 存入 `pid`。

檢視 nice 值:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — 只輸出 PID、nice 值(`NI`)、命令名這幾列。`-p "$pid"` 只看這一個程序。

檢視 CPU 親和性:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — 檢視執行中程序的親和性。加 `-c` 則以 CPU 編號列表而不是位掩碼顯示。

在 /proc 中交叉驗證:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `/proc/<PID>/status` 中的 `Cpus_allowed_list` — 核心記錄的"此程序可以執行的 CPU"列表,應與 taskset 的結果一致。

`NI=19` 且親和性為 `0`,就點選 **[驗證]**。(負載程序讓它繼續執行 — 不會影響下一步。)

## cgroup 記憶體限制與 OOM

在 Linux 中,強制執行程序組 CPU、記憶體上限的是 **cgroup v2**。容器的資源限制、systemd 服務的 `MemoryMax=`,以及 **k8s Pod 的 `resources.limits.memory`,全都執行在它之上**。這裡我們 **建立一個設有記憶體上限的 cgroup**,讓記憶體超限,親眼看看核心的 **OOM Killer** 如何動作。

先看看 cgroup 樹和控制器(controller)。

檢視檔案系統型別:

```
stat -fc %T /sys/fs/cgroup        # 應為 cgroup2fs
```

- `stat -f` — 顯示的不是檔案本身,而是該檔案所在 **檔案系統** 的資訊,`-c %T` — 透過格式指定只輸出型別名。`cgroup2fs` 即為 cgroup v2。

檢視可用的控制器:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- 此 cgroup 中可用的控制器列表(`cpu`、`memory`、`io`、`pids` …)。必須有 `memory` 才能設定記憶體上限。

> 💡 這個 Pod 共享 **宿主機的 cgroup 名稱空間**,也就是說 `/sys/fs/cgroup` 是整個節點的樹。在這裡手動 `mkdir` 會 **汙染節點**,並與其他 Pod 衝突。所以設有上限的 cgroup 交給 systemd,**在 Pod 自己的 slice 內部** 建立 — 這與 k8s 為每個 Pod 建立 cgroup 的方式完全相同。

任務:給名為 `lab.slice` 的 slice 設定 **記憶體 24M、交換 0** 的上限,並在其中執行一個分配 200MB 的程序來觸發 OOM。

```
# 給 slice 設定記憶體上限(--runtime = 只到重啟為止,不寫入磁碟)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <單元> 鍵=值…` — 修改執行中單元(這裡是 slice)的資源屬性。
- `MemoryMax=24M` — cgroup 的 `memory.max`(硬上限),`MemorySwapMax=0` — 不允許逃到交換空間。
- `--runtime` — 重啟後即消失的臨時設定(儲存在 `/run` 中)。

接下來在這個 slice 中超額分配記憶體。`systemd-run --slice=lab.slice --scope` 會在指定的 slice 下建立臨時 scope 並在其中執行命令。

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — 命令仍在當前終端中執行,但被放入一個新的臨時 scope(cgroup)。`--slice=lab.slice` 把它放到設有上限的 slice 之下。
- `python3 -c "…"` — 一行程式,建立 200 個 4MB 的位元組陣列(≈800MB)。行尾的 `\` 表示接到下一行。

應該會看到 `Killed` — 超過 24M 上限的瞬間,核心就殺掉了程序。痕跡會留在該 slice 的 cgroup 的 `memory.events` 中。slice 的實際 cgroup 路徑可以由 systemd 告訴你。

儲存 slice 的 cgroup 路徑:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — 輸出 slice 的 cgroup 路徑(`/…/lab.slice`)。在前面加上 `/sys/fs/cgroup`,把實際目錄路徑存入變數 `cg`。

檢視記憶體上限:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — 該 cgroup 的記憶體硬上限(位元組)。24M = 24×1024×1024 = 25165824。

檢視 OOM 事件:

```
cat "$cg/memory.events"     # 檢視 oom_kill 項
```

- `memory.events` — 該 cgroup 中發生的記憶體事件的累計次數。`max` 達到上限,`oom` 發生 OOM,`oom_kill` 因 OOM 被殺掉的程序數。

看到 `oom_kill 1`(或更多)就說明 OOM 確實發生了。確認後點選 **[驗證]**,模組即完成。(`lab.slice` 在 Pod 存活期間一直保留,Pod 消失後會被自動清理。)
