# systemd サービスと journald

linux-02 では nohup でデーモンを起動しましたが、実務のデーモンはすべて **systemd ユニット** です — 起動時の自動開始、落ちたら再起動、ログは journald が自動で収集。このモジュールではユニットを自分で書き、壊れたユニットを journal で診断・修理し、タイマーで cron を置き換えます。

今のシステムのユニットをざっと見てみましょう。

サービスユニットの一覧をざっと見る:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — メモリに読み込まれたユニットの一覧。`--type=service` でサービスだけ、`--no-pager` で less を通さずそのまま表示。
- `| head -15` — 先頭 15 行だけ。列は LOAD(ファイルの読み込み)・ACTIVE(上位の状態)・SUB(詳細な状態)の順。

cron サービスの状態確認:

```
systemctl status cron --no-pager
```

- `systemctl status <ユニット>` — 状態(`Active:`)、メイン PID、cgroup のプロセスツリー、最近のログ数行を 1 画面で表示する。

## サービスユニットを書く

最小のサービスユニットは 3 つのセクションで足ります。

| セクション | 役割 |
|---|---|
| `[Unit]` | 説明、依存関係(Description、After など) |
| `[Service]` | 実行方法(ExecStart、Restart、User など) |
| `[Install]` | enable 時にどこにぶら下がるか(WantedBy) |

課題: 8080 番ポートで静的 HTTP サーバーを動かす `hello-web.service` を作ってください。

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

- `sudo tee <ファイル> <<'EOF'` — ヒアドキュメントの本文を root 権限の `tee` がファイルに書く(`sudo cat > ファイル` はリダイレクトを自分のシェルが行うので権限エラーになる)。
- `/etc/systemd/system/` — 管理者が作るユニットファイルの置き場所。パッケージのユニット(`/usr/lib/systemd/system/`)より優先される。
- `ExecStart=` — 実行するコマンド(絶対パス)。`WantedBy=multi-user.target` — enable すると通常の起動ターゲットにぶら下がる。

ユニットファイルを作ったり直したりしたあとは **必ず daemon-reload** — systemd はファイルを直接読まず、メモリに読み込んだコピーを使います。

変更の再読み込み:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — systemd にユニットファイルを読み直させる。サービスの再起動はしない。

起動時の登録 + 即座に開始:

```
sudo systemctl enable --now hello-web
```

- `enable` — `WantedBy` のターゲットにシンボリックリンクを作って起動時に自動開始、`--now` — 同時に今すぐ `start` まで。
- ユニット名の `.service` サフィックスは省略できる。

サービスの状態確認:

```
systemctl status hello-web --no-pager
```

- `Active: active (running)` とメイン PID(`python3`)が見えれば正常に起動している。

応答の確認:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — 進捗表示なしで HTTP リクエストを送り、レスポンス本文を表示する。`| head -3` で先頭 3 行(ディレクトリ一覧の HTML)だけを見る。

`enable --now` は「起動時の自動開始を登録 + 今すぐ開始」です。応答を確認したら **[チェック]** してください。

## journald で壊れたユニットを修理する

`lab-report.service` というユニットが配置されていますが、起動に失敗します。見てみましょう。

サービスの起動を試す:

```
sudo systemctl start lab-report
```

- `systemctl start` — サービスを今すぐ起動する(起動時の登録とは無関係)。失敗すると `Job … failed` というメッセージとともに確認用のコマンドを案内する。

失敗の状態を確認:

```
systemctl status lab-report --no-pager
```

- `Active: failed` と `code=exited, status=…` の行で失敗の原因コードを確認する。

原因の調査は **journalctl** で行います。`-u` でユニットを指定し、`-e`(末尾へ移動)や `--no-pager` を添えます。

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — journald のログを参照する。`-u <ユニット>` そのユニットのログだけ、`--no-pager` でそのまま表示、`| tail -20` 最新の 20 行。
- リアルタイムの追跡は `-f`、今回の起動分だけなら `-b`、時間範囲は `--since "10 min ago"`。

`status=203/EXEC` が見えるはずです — systemd の終了コードの定番で、**ExecStart の実行ファイルを実行できない**(パスのタイプミス、実行権限なし、シバンの問題)という意味です。ユニットが指しているパスと実際のファイルを突き合わせてみましょう。

ユニットが指しているパスの確認:

```
systemctl cat lab-report
```

- `systemctl cat <ユニット>` — systemd が実際に使っているユニットファイル(ドロップインを含む)の内容とパスを表示する。`ExecStart=` の行を確認しよう。

実際のファイルの確認:

```
ls -l /opt/lab/bin/
```

- `ls -l` — ファイル名と権限(`x` の有無)を一緒に見る。ユニットのパスと 1 文字ずつ比べる。

課題: ExecStart のパスを直して(daemon-reload を忘れずに)サービスを起動してください。

ユニットファイルの修正:

```
sudo vim /etc/systemd/system/lab-report.service
```

- ユニットファイルは root 所有なので `sudo` で開く。vim: `i` で入力、`Esc` → `:wq` で保存・終了。
- 修正後に `daemon-reload` を忘れると、systemd は古いパスで失敗し続ける。

変更の再読み込み:

```
sudo systemctl daemon-reload
```

サービスの起動:

```
sudo systemctl start lab-report
```

ログをリアルタイムで確認:

```
tail -f /var/log/lab/report.log   # Ctrl-C で抜ける
```

- `tail -f` — ファイルの末尾を追いかけ(follow)、新しい行ができるたびに表示する。サービスが実際に動いているかを確かめる用途。

active(running)になったら **[チェック]** してください。

## Restart ポリシーで自己修復

プロセスは死にます — OOM、バグ、ミス。systemd の `Restart=` は、そのとき自動で生き返らせるセーフティネットです。

| 値 | 再起動の条件 |
|---|---|
| `no`(デフォルト) | 生き返らせない |
| `on-failure` | 異常終了(コード≠0、シグナル)のときだけ |
| `always` | 正常終了でも無条件に |

課題: hello-web に `Restart=on-failure` と `RestartSec=1` を追加してください。ユニットファイルを直接直してもよいし、元ファイルに手を付けない **ドロップイン**(`systemctl edit` は対話式なので、ここではファイルで)方式も良い方法です。

ドロップインディレクトリの作成:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<ユニット>.d/` — ドロップインディレクトリ。中の `*.conf` ファイルが元のユニットの上に上書きされる。パッケージが元ファイルを更新しても自分の設定が保たれる。

ドロップインファイルの作成:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- `[Service]` セクションに追加するキーだけを書く。`Restart=on-failure` 異常終了時に再起動、`RestartSec=1` 再起動前に 1 秒待つ。

変更の再読み込み:

```
sudo systemctl daemon-reload
```

サービスの再起動:

```
sudo systemctl restart hello-web
```

- `restart` — stop のあと start。新しい設定(ドロップイン)が適用された状態でプロセスが立ち上がり直す。

本当に生き返るか実験してみましょう。メイン PID を SIGKILL で殺し、数秒後に状態を見てください。

メイン PID の確認:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — ユニットの属性を `キー=値` で表示する。`-p MainPID` で属性 1 つだけ、`--value` で `MainPID=` なしの値だけ。

プロセスの強制終了:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- `$( ... )` で得たメイン PID に `kill -9`(SIGKILL)— 横取りできない強制終了。これは「異常終了」なので `on-failure` の対象になる。

少し待ってから状態を確認:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- `sleep 3` で再起動(RestartSec=1)の時間を与えてから、状態の先頭 5 行を見る。`Main PID` が前と違っているはず。

PID が変わった状態で再び active なら成功 — **[チェック]** してください。(チェックでも同じ実験をもう一度行います。)

## タイマーで定期ジョブ

cron の systemd 版の置き換えが **タイマー** です。ログが journal に残り、失敗をユニットとして管理できるので、最近のディストリビューションの定期ジョブはほとんどがタイマーです。構成は **サービス(やること)+ タイマー(いつ)** の 1 組です。

課題: 1 分ごとに `/var/log/lab/tick.log` に時刻を記録する `lab-tick` タイマーを作ってください。

サービスユニット(やること)の作成:

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — 実行して終わるジョブ。コマンドが終了すると成功とみなして非アクティブ状態に戻る。
- `bash -c '…'` — リダイレクト(`>>`、追記)はシェルの機能なので bash を経由して実行する。`date -Is` は ISO 8601 形式の時刻。

タイマーユニット(いつ)の作成:

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

- `OnCalendar=*-*-* *:*:00` — `年-月-日 時:分:秒` のカレンダー式。毎日・毎時・毎分の 0 秒 = 1 分ごと。
- `AccuracySec=1s` — 実行時刻の許容誤差(デフォルト 1 分)を 1 秒に縮める。
- タイマーは同じ名前の `.service`(ここでは `lab-tick.service`)を実行する。`WantedBy=timers.target` で enable される。

変更の再読み込み:

```
sudo systemctl daemon-reload
```

タイマーの登録・開始:

```
sudo systemctl enable --now lab-tick.timer
```

- `.timer` まで名前を正確に書く必要がある。省略すると `.service` と解釈される。

`Type=oneshot` は「1 回実行して終わる」ジョブ用です。enable の対象が **service ではなく timer** であることに注意してください。登録状態を確認して **[チェック]** すればモジュール完了です。

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — 有効なタイマーの次回(`NEXT`)・前回(`LAST`)の実行時刻。
- `grep -E 'NEXT|lab-tick'` — ヘッダー行と lab-tick の行だけを残す(`|` は拡張正規表現の OR)。
