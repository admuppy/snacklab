# 最初のインスタンスを起動する

このラボは Pod の中で動く **あなた専用のオールインワン OpenStack**(Caracal)で進めます。keystone・glance・
neutron・nova がすべてこの中で動いており、ターミナルには管理者の認証情報がすでに設定されているので、
`openstack` CLI をすぐに使えます(`os` エイリアスもあります)。

> 注意: このラボの nova は **fake ドライバー** で動作します — インスタンスは実際の VM なしで状態遷移だけで
> 起動するため、すぐに立ち上がりリソースもほとんど使いません。コンソール接続や SSH はできませんが、API・CLI の
> 流れは実際の OpenStack と同じです。

### サービスカタログを読む

OpenStack は 1 つのプログラムではなく、**役割の異なる複数のサービスの集まり** です。各サービスは
自分の REST API を持ち、互いを呼ぶときは keystone に登録された **サービスカタログ** から相手の
エンドポイントのアドレスを探します。`openstack service list` はそのカタログに何が登録されているかを表示します。

このラボで出会うサービスは次のとおりです。

| サービス | タイプ | 役割 |
|---|---|---|
| keystone | identity | 認証・認可。ログインするとトークンを発行し、ほかのサービスはそのトークンで要求者を確認する |
| glance | image | インスタンスを作るときに使うディスクイメージを保管・配布する |
| neutron | network | ネットワーク・サブネット・ポートなどの仮想ネットワークを担当する |
| nova | compute | インスタンス(仮想マシン)の作成・起動・停止などのライフサイクルを担う |
| placement | placement | どのホストにリソース(vCPU・メモリ・ディスク)が残っているかを追跡し、nova の配置判断を助ける |

サービスカタログの確認:

```bash
openstack service list
```

- `openstack <対象> <動作>` — OpenStack CLI の基本形。ここでは対象が `service`、動作が `list`。
- keystone のサービスカタログに登録されたサービスを一覧表示する。エンドポイントの URL まで見るなら `openstack endpoint list`。

出力の `Name` はサービス名、`Type` は役割を表す標準のタイプ文字列です。CLI はこの **タイプ** で
エンドポイントを探します。たとえば `openstack image list` はカタログから `image` タイプを探して glance を
呼び出します。つまりコマンドの最初の単語(`image`・`network`・`server`…)とここに見えるタイプがつながっています。

### コンピュートサービスの構成を読む

nova 自体も **複数のプロセスに分かれて** います。`openstack compute service list` はそれらのプロセスが
どのホストで生きているかを表示します。

| コンポーネント | 役割 |
|---|---|
| nova-scheduler | 新しいインスタンスを **どのコンピュートホストに置くか** を選ぶ。placement が候補を絞り込む |
| nova-conductor | DB アクセスや長時間の処理を代わりに行う。コンピュートノードが DB に直接つながらないようにする中間層 |
| nova-compute | 実際のハイパーバイザーを操作してインスタンスを起動・停止する。コンピュートホストごとに 1 つ動く |

コンピュートホストの確認:

```bash
openstack compute service list
```

- nova のバックグラウンドプロセス(scheduler・conductor・compute)と、そのホスト・`Status`(enabled/disabled)・`State`(up/down)を表示する。

`State` が `up` ならそのプロセスは生きており、`Status` は運用者が無効化(disabled)しているかどうかを
示します。インスタンスが `ERROR` に落ちたときに最初に見る表がこれです — nova-compute が `down` なら
どんな要求もホストまで届きません。

一覧に **nova-api は出てきません。** API サービスは Web サーバーとして動き、カタログ(`openstack service list`)に
エンドポイントとして登録されます。ここに出るのはバックグラウンドプロセスです。このラボはオールインワンなので、
3 つのコンポーネントがすべて同じホスト名で見えます。

> 参考: [OpenStack CLI ドキュメント](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. ネットワークとサブネットの作成

まずインスタンスを接続するテナントネットワークを作ります。

ネットワーク `net1` の作成:

```bash
openstack network create net1
```

- neutron に L2 仮想ネットワーク `net1` を作る。この時点では IP 帯域がないのでインスタンスはアドレスを受け取れない — 次のコマンドのサブネットが必要。

`192.168.100.0/24` 帯域のサブネット `subnet1` を `net1` に作成:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

- `--network net1` — サブネットを付けるネットワーク。
- `--subnet-range 192.168.100.0/24` — CIDR 帯域。ゲートウェイ(デフォルト `.1`)と DHCP の割り当て範囲が自動で決まる。
- 最後の引数 `subnet1` — サブネット名。

作成したネットワークの確認:

```bash
openstack network list
```

- `Subnets` 列にさきほど付けたサブネットの ID が見えればネットワークの準備完了。

## 2. インスタンスの起動(ACTIVE)

用意された `cirros` イメージと `m1.tiny` フレーバーでインスタンス `vm1` を起動します。

利用可能なイメージの確認:

```bash
openstack image list
```

- glance に登録されたイメージの一覧。`Status` が `active` のイメージだけがインスタンスの作成に使える。

フレーバーの確認:

```bash
openstack flavor list
```

- フレーバー = インスタンスのハードウェア規格(vCPU・RAM・ディスク)のテンプレート。`m1.tiny` が最も小さい規格。

インスタンスの起動:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

- `--flavor m1.tiny` — ハードウェア規格、`--image cirros` — 起動するディスクイメージ、`--network net1` — ポートを作って接続するネットワーク。
- 最後の引数 `vm1` — インスタンス名。コマンドは要求を受け付けるだけですぐ戻る(`BUILD`)ので、状態は別途確認する。

状態が `ACTIVE` になるまで確認(数秒かかることがあります):

```bash
openstack server show vm1 -c status -c addresses
```

- `openstack server show <名前>` — インスタンス 1 つの詳細情報。
- `-c <列>` — 表示する列(フィールド)だけを選ぶ。何度でも指定できる。`addresses` には `net1=192.168.100.x` のように割り当てられた IP が出る。

## 3. プロジェクト全体のインスタンスを参照する

これまで使った `openstack server list` は **自分が属するプロジェクトのインスタンスだけ** を表示します。

**プロジェクト(project)** は OpenStack でリソースを所有する単位です(以前の名前は tenant)。ネットワーク、
インスタンス、ボリューム、イメージなどのリソースはすべてどこかのプロジェクトに属し、クォータもプロジェクト単位で
かかります。ユーザーはプロジェクトに **ロール(role)** を与えられてアクセスし、トークンも「どのプロジェクトとして」
発行されます。そのため同じ人でも、どのプロジェクトでログインしたかによって見えるリソースが変わります。

今のトークンがどのプロジェクトとして発行されたかを確認:

```bash
openstack token issue -c project_id -f value
```

- `openstack token issue` — 現在の認証情報で keystone のトークンを発行してもらい、その情報を表示する。
- `-c project_id -f value` — `project_id` 列だけを、表の枠線なしの値(`-f value`)として出力する。スクリプトで使いやすい形式。

このラボには `admin`、`service`、`demo` のようなプロジェクトがすでに作られています。プロジェクト一覧の確認:

```bash
openstack project list
```

- keystone にあるプロジェクト(ID・名前)の一覧。前のコマンドで見た `project_id` がどのプロジェクトかをここで照らし合わせられる。

`--all-projects` は **すべてのプロジェクトのリソースを一度に見せてほしい** という引数です。クラウド全体を見る必要のある
運用者向けのオプションなので admin ロールがないと動かず、一般ユーザーが使うと権限エラーになります。

デフォルトの出力にはプロジェクト ID の列がありません。どのプロジェクトのインスタンスかを知る必要があるので、
`-c 'Project ID'` でその列を直接選びます。`--long` はタスク状態やホストなどの運用情報を追加する別のオプションです。

プロジェクト ID を含めて参照:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

- `--all-projects` — すべてのプロジェクトのインスタンスを参照する(admin ロールが必要)。
- `-c <列>` — 表示する列(フィールド)だけを選ぶ。何度でも指定できる。列名に空白があればクォートで囲む(`'Project ID'`)。

採点用にこの結果をファイルに残します:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

- `-f value` — 表の代わりに空白区切りの値だけを出力する。
- `> ~/all-servers.txt` — その出力をファイルに保存(上書き)する。チェックスクリプトがこのファイルを読む。

> 参考: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. インスタンスの停止(SHUTOFF)

起動したインスタンスを停止して、ライフサイクルを締めくくります。

インスタンスの停止:

```bash
openstack server stop vm1
```

- インスタンスを正常にシャットダウン(電源オフ)する。ディスクや IP などのリソースはそのまま残り、`openstack server start vm1` で再び起動できる。完全に消すなら `openstack server delete`。

状態が `SHUTOFF` かを確認:

```bash
openstack server show vm1 -c status
```

- `status` が `SHUTOFF` に変わったかを確認する。すぐに変わらなければ数秒後にもう一度実行する。
