# qcow2 イメージを作ってアップロードする

インスタンスは **イメージ** から起動します。イメージは OS がインストールされたディスクを 1 つのファイルに
固めたもので、glance がそのファイルを保管します。このラボではディスクファイルを自分で作り、フォーマットを
変換したあと、glance にアップロードしてそのイメージでインスタンスを起動します。

**qcow2**(QEMU Copy On Write 2)は OpenStack で最も広く使われるディスクフォーマットです。
2 つの性質が重要です。

- **スパース割り当て(sparse)** — 仮想サイズが 1GiB でも、実際に書き込んだデータの分だけファイルを占有する。
  そのためイメージをやり取りするときの転送量が小さい。
- **メタデータを持つ** — バッキングファイル、スナップショット、圧縮などの情報をファイル内に持てる。

反対に **raw** はディスクのバイトをそのまま並べたフォーマットです。構造がないので扱いが単純で I/O も
1 層少なく済みますが、ファイルサイズは仮想サイズ分を占めるのが普通です。運用では「配布は qcow2、
ストレージに載せるときは raw」と使い分けることがよくあります。

> 参考: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> 注意: このラボの nova は fake ドライバーなので、インスタンスの中で OS が実際に起動するわけではありません。
> イメージが正しく登録され、nova がそのイメージでインスタンスを作る流れまでが確認の対象です。

作業ディレクトリは `~/images` で、ブートストラップがあらかじめ作っています。インスタンスを接続する
ネットワーク `net1` も用意されています。

## 1. 空の qcow2 ディスクを作る

`qemu-img` はディスクイメージを作成・変換するツールです。まず何も入っていない qcow2 ディスクを
1 つ作り、ファイルの構造を見てみます。

仮想サイズ 1GiB の空の qcow2 ディスクを作成:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — 新しいディスクイメージファイルを作る。
- `-f qcow2` — 作るファイルのフォーマット、続いてファイルのパス、最後の `1G` — ゲストから見える仮想サイズ。

作ったディスクの情報を確認:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — イメージのフォーマット(`file format`)、仮想サイズ、実サイズ、クラスターサイズなどのメタデータを表示する。

`virtual size` はゲストから見えるディスクサイズ、`disk size` はファイルが実際に占めるサイズです。
作ったばかりのディスクは中身がないので、両者の差が大きくなります。これがスパース割り当てです。

ファイルが実際にどれだけ占めているかを確認:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — ファイルの詳細情報(権限・所有者・サイズ・時刻)、`-h` — サイズを K/M/G のような読みやすい単位で。
- ここに表示されるのはファイルの「見かけ上」のサイズ。実際に使っているブロックは `du -h` で見られる。

## 2. ディスクフォーマットの変換(qcow2 ↔ raw)

今度は本物の OS が入ったディスクを扱います。glance にすでにある `cirros` イメージをダウンロードして
フォーマットを変えてみます。

glance に登録されたイメージのフォーマットを確認:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <名前>` — glance イメージの属性。`-c` で `disk_format`・`container_format`・`size`(バイト)の列だけを選ぶ。

`disk_format` はディスクファイル自体のフォーマット(qcow2・raw・vmdk…)で、`container_format` はそのディスクを
包むメタデータの封筒を意味します。封筒なしでディスクだけを上げるときの値が `bare` で、実務ではほとんど
この値を使います。

イメージファイルをローカルにダウンロード:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <名前> --file <パス>` — glance に保存されたイメージデータをローカルファイルにダウンロードする。名前に反して「ダウンロード」のコマンド。

ダウンロードしたファイルのフォーマットを確認:

```bash
qemu-img info ~/images/cirros-src.img
```

- 拡張子が `.img` でも、実際のフォーマットは中身で判別される。`file format` の行を確認しよう。

qcow2 を raw に変換(`-f` は元のフォーマット、`-O` は出力フォーマット):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — イメージを別のフォーマットにコピー変換する(元ファイルはそのまま)。
- `-f qcow2` — 入力フォーマット(小文字の f)、`-O raw` — 出力フォーマット(大文字の O)。その後に元のパス、出力先のパスの順。

変換した raw ディスクを確認:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw はメタデータがないので、`file format: raw` とサイズ情報くらいしか出ない。

raw は構造がないので `disk size` が `virtual size` に近くなります。このままでは転送に不利なので、
qcow2 に戻します。

raw を再び qcow2 に変換:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 今度は入力 raw → 出力 qcow2。空のブロックは書き込まないので、ファイルがまた小さくなる(`-c` を付けると圧縮もする)。

3 つのファイルのサイズを一度に比べる:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 複数のファイルを一度に並べ、元ファイル・raw・再変換した qcow2 のサイズを並べて比べる。

## 3. glance にアップロードしてインスタンスを起動

作った qcow2 ファイルを glance に登録します。アップロードするときは **ディスクフォーマットとコンテナフォーマットを
必ず正しく** 指定する必要があります。実際のファイルは qcow2 なのに `--disk-format raw` で上げると、登録はできても
起動で壊れます。

一緒に指定する値の意味は次のとおりです。

- `--min-disk` / `--min-ram` — このイメージを使うには最低どれだけのディスク・メモリが必要かを知らせる
  ヒント。条件に満たないフレーバーは nova が除外する。
- `--property` — 任意のメタデータを付ける。`os_distro` のように標準で使われるキーは、スケジューリングや
  ハイパーバイザーの設定に使われることもある。

qcow2 ファイルを glance イメージとして登録:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — 新しい glance イメージ `cirros-lab` を登録する。
- `--disk-format qcow2 --container-format bare` — ファイルの実際のフォーマットと封筒(なし)。
- `--min-disk 1 --min-ram 64` — 必要な最小ディスク(GB)・メモリ(MB)、`--property os_distro=cirros` — 任意のメタデータ。
- `--file <パス>` — アップロードするローカルファイル。アップロードが終わると `status` が `active` になる。

登録結果の確認(`status` が `active` であること):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- 登録時に指定した値がそのまま保存されたかを、必要な列だけ選んで確認する。`--property` で指定した値は `properties` に入っている。

イメージ一覧でも確認:

```bash
openstack image list
```

- 一覧に `cirros-lab` が `active` で見えれば、インスタンスに使える。

自分で作ったイメージでインスタンス `vm2` を起動:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- モジュール 1 と同じ形だが、`--image cirros-lab` で自分で作ったイメージを指定する。フレーバーが `--min-disk`/`--min-ram` の条件を満たしていないと作成されない。

状態と使われたイメージを確認:

```bash
openstack server show vm2 -c status -c image
```

- `image` 列に `cirros-lab` とその ID が出れば、さきほどアップロードしたイメージで作られたということ。
