# ユーザー・グループと sudo 最小権限

サーバーに新しい同僚が来たらアカウントを作り、チームのグループに入れ、**必要な分だけ** sudo を開放します。退職したらアカウントをロックします。このモジュールはそのライフサイクル全体を扱います。

まずアカウント情報がどこに保存されているかを見てみましょう。

| ファイル | 内容 |
|---|---|
| `/etc/passwd` | ユーザー一覧(名前:x:UID:GID:説明:ホーム:シェル) |
| `/etc/shadow` | パスワードのハッシュ + 有効期限ポリシー(root だけが読める) |
| `/etc/group` | グループとメンバー |
| `/etc/sudoers`、`/etc/sudoers.d/` | sudo の権限ルール |

learner アカウントの参照:

```
getent passwd learner
```

- `getent <データベース> <キー>` — NSS を通じて項目を 1 つ参照する。`passwd` データベースから `learner` の行を表示する。

shadow の先頭を見る:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` は root しか読めないので `sudo` が必要。2 番目のフィールドがパスワードのハッシュ(`*`・`!` はログイン不可)。

> `getent` はファイルを直接開く代わりに NSS(LDAP などの外部ソースを含む)を通じて参照します — `cat /etc/passwd` より正確な習慣です。

## ユーザーの作成

デプロイ担当のアカウント `deploy` を作ってください。要件:

- ホームディレクトリを作成(`-m` — 付けないとホームのないアカウントになります)
- ログインシェル `/bin/bash`(`-s` — ディストリビューションのデフォルトは sh であることが多い)

deploy ユーザーの作成:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — 新しいユーザーを作る。`-m` ホームディレクトリを作成(`/etc/skel` の内容をコピー)、`-s /bin/bash` ログインシェルを指定、最後の引数がユーザー名。
- パスワードは別途 `passwd deploy` で設定する(このラボでは不要)。

passwd の項目を確認:

```
getent passwd deploy
```

- コロン区切りのフィールドのうち最後の 2 つがホームディレクトリとシェル。`/home/deploy`、`/bin/bash` かを確認。

ホームディレクトリの確認:

```
ls -ld /home/deploy
```

- `ls -ld` — 中身ではなくディレクトリ **そのもの**(`-d`)の権限・所有者を見る。所有者が `deploy` であるべき。

`useradd` は低レベルのツールなので **何も聞いてきません**。オプションを付け忘れてもそのまま作ってしまうので、作ったあとの確認が必須です。確認したら **[チェック]** してください。

## グループの構成

運用チームのグループ `ops` を作り、deploy を入れます。ここに古典的な落とし穴が 1 つ —

| コマンド | 結果 |
|---|---|
| `usermod -aG ops deploy` | ops を **補助グループとして追加** ✔ |
| `usermod -G ops deploy` | 補助グループを ops **1 つに置き換え**(既存のものが全部外れる!) |
| `usermod -g ops deploy` | **プライマリグループを置き換え**(ファイル作成時のデフォルトグループが変わる) |

`-a`(append)なしの `-G` は事故への近道です。補助グループとして追加してください。

ops グループの作成:

```
sudo groupadd ops
```

- `groupadd <グループ>` — 新しいグループを作る。`/etc/group` に 1 行追加される。

補助グループとして追加:

```
sudo usermod -aG ops deploy
```

- `usermod` — 既存ユーザーの属性を変更する。`-G ops` 補助グループの指定、`-a` 既存の補助グループに **追加**(append)。
- すでにログインしているセッションには、ログインし直さないと新しいグループが反映されない。

グループの確認:

```
id deploy
```

- `id <ユーザー>` — UID、プライマリグループ(`gid=`)、すべてのグループ(`groups=`)を 1 行で表示する。

`id` の出力で `gid=`(プライマリ)と `groups=`(全体)を区別して読んでみましょう。確認したら **[チェック]** してください。

## sudoers の最小権限

deploy にサービス状態の参照は許可しつつ、**それ以上は禁止** したいとします。ルールは `/etc/sudoers` を直接直さず、`/etc/sudoers.d/` の下にドロップインとして作るのが慣例です。

文法: `誰が どこで=(誰として) [NOPASSWD:] コマンド群`

ドロップインルールの作成:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo 'ルール' | sudo tee <ファイル>` — `sudo echo … > ファイル` はリダイレクトを自分のシェルが処理するので権限エラーになる。そこで root で動く `tee` にファイルを書かせる。
- ルール: `deploy` がすべてのホスト(`ALL`)で、誰としてでも(`(ALL)`)、パスワードなしで(`NOPASSWD:`)`systemctl status *` だけを実行できる。

権限を 440 に:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — 所有者(root)・グループは読み取り専用。sudo はほかのユーザーに書き込み権限がある sudoers ファイルを拒否する。

**文法の検証は必須です。** sudoers が壊れると sudo そのものが使えなくなり、復旧が困難になります。`visudo -cf` がその安全装置です。

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — 文法チェックだけ(check)、`-f <ファイル>` — 検査するファイルを指定。`parsed OK` と出るはず。
- 本来 sudoers の編集は `sudo visudo`(保存前に自動チェック)で行うのが定石。

deploy の立場で何ができるか確認してみましょう。

deploy の sudo 権限一覧:

```
sudo -l -U deploy
```

- `sudo -l` — 許可された sudo コマンドの一覧、`-U deploy` — 別のユーザーの一覧を参照する(root 権限が必要)。

許可されたコマンド — 成功するはずです:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # 許可されたもの
```

- `sudo -u deploy <コマンド>` — deploy ユーザーとしてコマンドを実行する。その中でさらに `sudo` を呼び、deploy の sudo 権限を試す。
- `sudo -n` — パスワードを聞かない(non-interactive)。聞く必要がある状況ならすぐに失敗する。
- `--no-pager` — 出力を less に渡さず、そのまま表示する。

禁止されたコマンド — 拒否されるはずです:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # 拒否されるもの
```

- ルールにない `restart` なので拒否される。`2>&1` でエラーメッセージもパイプに渡し、`tail -1` で最後の行だけを見る。

許可/拒否が意図どおりなら **[チェック]** してください。

## アカウントのロックとパスワードポリシー

`olduser` は退職者のアカウントです。削除(`userdel`)はファイルの所有権整理の問題があるので、普通はまず **ロック** します。

アカウントのロック:

```
sudo usermod -L olduser
```

- `usermod -L` — アカウントをロック(Lock)する。shadow のハッシュの前に `!` を付けて、パスワードでのログインを止める。解除は `-U`。

ロック状態の確認:

```
sudo passwd -S olduser
```

- `passwd -S <ユーザー>` — パスワード状態の要約。2 番目のフィールドが `L` ならロック、`P` なら使用可能、`NP` ならパスワードなし。

`passwd -S` の 2 番目のフィールドが `L`(locked)なら成功です。ロックは shadow のハッシュの前に `!` を付けるだけなので、いつでも `-U` で元に戻せます。

続いて deploy に、パスワードの **最大使用期間 90 日** のポリシーを適用してください。

最大 90 日のポリシーを適用:

```
sudo chage -M 90 deploy
```

- `chage` — パスワードの有効期限ポリシー(change age)を変更する。`-M 90` — 最大使用日数を 90 日に。

ポリシーの確認:

```
sudo chage -l deploy
```

- `chage -l` — 最終変更日・有効期限・最大/最小期間など、現在のポリシーを一覧(list)で表示する。

2 つとも確認したら **[チェック]** — モジュール完了です。
