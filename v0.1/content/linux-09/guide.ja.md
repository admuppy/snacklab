# CPU・メモリ管理

サーバーが遅くなったという報告が来たら、最初に見るのは **CPU とメモリ** です。このモジュールでは、リソースを観察するツールから、プロセスの優先度の調整、そしてコンテナ/Pod の実質的な上限である **cgroup のメモリ制限と OOM** までを扱います。

> この実習環境は systemd が動く **コンテナ(Pod)** です。リソース制限も実際の k8s Pod と同じ方式(systemd が管理する cgroup v2)で扱います — 物理サーバーと違う部分はその都度指摘します。

まず現在の状態をざっと見ます。

CPU 数の確認:

```
nproc
```

- `nproc` — 現在のプロセスが使える CPU(コア)の数。コンテナでは cgroup やアフィニティの制限が反映された値になる。

メモリの状況確認:

```
free -h
```

- `free` — メモリ・スワップの使用量。`-h` で Gi/Mi 単位。
- `available` 列が「新しいプロセスが実際に使える量」(キャッシュの回収分を含む)なので、`free` 列より重要。

1 秒間隔の要約を 3 回:

```
vmstat 1 3
```

- `vmstat <間隔> <回数>` — 1 秒間隔で 3 回表示。最初の行は起動からの平均なので、2 行目から見る。
- `r` 実行待ちのプロセス、`si/so` スワップの in/out、`us/sy/id/wa` CPU のユーザー/カーネル/アイドル/IO 待ちの割合。

top のスナップショットを 1 枚:

```
top -b -n1 | head -12
```

- `top -b` — 対話画面の代わりにテキストで出力(batch)、`-n1` — 1 回だけ。`| head -12` で要約部分と上位のプロセスいくつかだけ。

## リソースの観察

`free` はメモリを、`vmstat` はメモリ・スワップ・CPU を 1 行に要約します。元の数値は `/proc/meminfo` と `/proc/cpuinfo` にあります。

| コマンド | 何を見るか |
|---|---|
| `free -h` | 全体/使用中/利用可能なメモリ、swap |
| `vmstat 1` | 1 秒間隔のメモリ・swap in/out(si/so)・CPU |
| `nproc` | この環境で使える CPU の数 |
| `cat /proc/meminfo` | MemTotal・MemAvailable などの元データ |

課題: 現在のメモリ総量と CPU 数をスナップショットとして残します。`~/work/snapshot.txt` に **/proc/meminfo の MemTotal の行** と **`cpus=<nproc の値>`** の行を保存してください。

作業ディレクトリの準備:

```
mkdir -p ~/work
```

- `mkdir -p` — 上位のディレクトリまで作り、すでにあってもエラーにしない。

MemTotal の行を保存:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — 総メモリの行だけを選び、`>` でファイルに保存(新規に書く)する。

cpus の行を追加:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — ダブルクォートの中でも `$( )` が置換され、`cpus=4` のような文字列になる。
- `>>` — ファイルの末尾に **追加** する(`>` は上書き)。

保存内容の確認:

```
cat ~/work/snapshot.txt
```

- 2 行(MemTotal、cpus=…)が入っているかを確認する。

記録したら **[チェック]** してください。

## 優先度と CPU アフィニティ

CPU が足りないとき、すべてのプロセスを同じように扱うわけにはいきません。**nice 値**(-20 高い 〜 19 低い)でスケジューラーの優先度を、**taskset** でどのコアで動くか(CPU アフィニティ)を決めます。

| コマンド | 役割 |
|---|---|
| `nice -n 19 CMD` | 低い優先度で新しいプロセスを開始 |
| `renice -n 5 -p PID` | 実行中のプロセスの nice を変更 |
| `taskset -c 0 CMD` | CPU 0 番だけに固定して実行 |
| `taskset -pc PID` | 実行中のプロセスのアフィニティを参照/変更 |

課題: CPU を燃やす負荷(`stress-ng --cpu 1`)を **CPU 0 番に固定** し、**nice 19**(最も譲る優先度)でバックグラウンド実行してください。バッチ処理を他のサービスの邪魔にならないように動かす典型的なパターンです。

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <コマンド>` — コマンドを CPU 0 番だけに固定して実行する(`-c` は CPU 番号のリスト、例: `0,2` や `0-3`)。
- `nice -n 19 <コマンド>` — nice 値 19(最も低い優先度)で実行する。2 つのラッパーは重ねて使える。
- `stress-ng --cpu 1 --timeout 1800s` — CPU 1 つを 30 分間 100% で燃やす負荷生成ツール。
- `>/dev/null 2>&1 &` — 出力は捨ててバックグラウンドで実行する。

本当にそのとおりに起動したか確認します。`top` で `NI` 列が 19 か、アフィニティが CPU 0 かを見てください。

負荷プロセスの PID を保存:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — コマンドライン全体から正規表現で探す(`.*` は任意の文字の繰り返し)。`head -1` で最初の PID だけを `pid` に保存。

nice 値の確認:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — PID・nice 値(`NI`)・コマンド名の列だけ。`-p "$pid"` でそのプロセス 1 つだけ。

CPU アフィニティの確認:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — 実行中のプロセスのアフィニティを参照する。`-c` を付けるとビットマスクの代わりに CPU 番号のリストで表示する。

/proc でクロスチェック:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `/proc/<PID>/status` の `Cpus_allowed_list` — カーネルが記録した「このプロセスが動ける CPU」の一覧。taskset の結果と一致するはず。

`NI=19`、アフィニティが `0` なら **[チェック]** してください。(負荷プロセスは動かし続けておきます — 次のステップには影響しません。)

## cgroup のメモリ制限と OOM

Linux でプロセスグループの CPU・メモリの上限を強制するのは **cgroup v2** です。コンテナのリソース制限、systemd サービスの `MemoryMax=`、そして **k8s Pod の `resources.limits.memory` はすべてこの上で** 動いています。ここでは **メモリ上限を付けた cgroup を作り**、メモリを超過させて、カーネルの **OOM Killer** が動作するのを目で確かめます。

まず cgroup のツリーとコントローラーを見ます。

ファイルシステムのタイプ確認:

```
stat -fc %T /sys/fs/cgroup        # cgroup2fs であること
```

- `stat -f` — ファイルではなく、そのファイルがある **ファイルシステム** の情報を、`-c %T` — 書式指定でタイプ名だけを表示する。`cgroup2fs` なら cgroup v2。

利用可能なコントローラーの確認:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- この cgroup で使えるコントローラーの一覧(`cpu`、`memory`、`io`、`pids` …)。`memory` がないとメモリ上限を設定できない。

> 💡 この Pod は **ホストの cgroup 名前空間** を共有しています。つまり `/sys/fs/cgroup` はノード全体のツリーです。ここに手で `mkdir` すると **ノードを汚染** し、ほかの Pod と衝突します。そこで上限付きの cgroup は systemd に任せて **Pod 自身のスライスの中に** 作ります — k8s が Pod ごとに cgroup を作ってくれるのとまったく同じ方式です。

課題: `lab.slice` というスライスに **メモリ 24M・スワップ 0** の上限をかけ、その中で 200MB を割り当てるプロセスを動かして OOM を起こしてください。

```
# スライスにメモリ上限を設定(--runtime = 再起動まで、ディスクには残さない)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <ユニット> キー=値…` — 実行中のユニット(ここではスライス)のリソース属性を変える。
- `MemoryMax=24M` — cgroup の `memory.max`(ハード上限)、`MemorySwapMax=0` — スワップに逃げられないようにする。
- `--runtime` — 再起動すると消える一時的な設定(`/run` に保存)。

次にそのスライスの中でメモリを超過して割り当てます。`systemd-run --slice=lab.slice --scope` は、指定したスライスの下に一時的なスコープを作ってコマンドを実行します。

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — コマンドを今のターミナルでそのまま実行しつつ、新しい一時的なスコープ(cgroup)に入れる。`--slice=lab.slice` で上限のかかったスライスの下に。
- `python3 -c "…"` — 4MB のバイト配列を 200 個(≈800MB)作る 1 行のプログラム。行末の `\` は次の行に続くという意味。

`Killed` が表示されるはずです — 24M の上限を超えた瞬間にカーネルがプロセスを殺したのです。痕跡はスライスの cgroup の `memory.events` に残ります。スライスの実際の cgroup パスは systemd が教えてくれます。

スライスの cgroup パスを保存:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — スライスの cgroup パス(`/…/lab.slice`)を表示する。先頭に `/sys/fs/cgroup` を付けて実際のディレクトリのパスを変数 `cg` に入れる。

メモリ上限の確認:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — この cgroup のメモリのハード上限(バイト)。24M = 24×1024×1024 = 25165824。

OOM イベントの確認:

```
cat "$cg/memory.events"     # oom_kill の項目を確認
```

- `memory.events` — この cgroup で起きたメモリイベントの累積回数。`max` 上限への到達、`oom` OOM の発生、`oom_kill` OOM で殺されたプロセスの数。

`oom_kill 1`(またはそれ以上)が見えれば OOM が実際に起きたということです。確認したら **[チェック]** でモジュール完了です。(`lab.slice` は Pod が生きている間は残り、Pod がなくなると自動で片付けられます。)
