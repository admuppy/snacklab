# 啟動第一臺例項

本實驗在 Pod 內執行的 **你專屬的一體化 OpenStack**(Caracal)中進行。keystone、glance、
neutron、nova 都在其中執行,終端裡已經配置好管理員憑據,可以直接使用 `openstack` CLI
(也有 `os` 別名)。

> 注意: 本實驗的 nova 使用 **fake 驅動** — 例項沒有真實的虛擬機器,只按狀態機啟動,
> 因此能立即起來且幾乎不佔資源。無法使用控制檯和 SSH,但 API、CLI 的流程與真實的 OpenStack 相同。

### 閱讀服務目錄

OpenStack 不是一個程式,而是 **一組各司其職的服務**。每個服務都有自己的 REST API,
相互呼叫時,會從 keystone 中登記的 **服務目錄** 裡查詢對方的端點地址。`openstack service list`
會顯示目錄裡登記了哪些服務。

本實驗中會接觸到的服務如下。

| 服務 | 型別 | 作用 |
|---|---|---|
| keystone | identity | 認證與授權。登入後簽發令牌,其他服務用這個令牌確認請求者 |
| glance | image | 儲存並分發建立例項時使用的磁碟映像 |
| neutron | network | 負責網路、子網、埠等虛擬網路 |
| nova | compute | 負責例項(虛擬機器)的建立、啟動、停止等生命週期 |
| placement | placement | 跟蹤哪些主機還有剩餘資源(vCPU、記憶體、磁碟),協助 nova 做排程決策 |

檢視服務目錄:

```bash
openstack service list
```

- `openstack <物件> <動作>` — OpenStack CLI 的基本格式。這裡物件是 `service`,動作是 `list`。
- 列出 keystone 服務目錄中登記的服務。要看端點 URL,用 `openstack endpoint list`。

輸出中的 `Name` 是服務名,`Type` 是表示角色的標準型別字串。CLI 按這個 **型別** 查詢端點。
例如 `openstack image list` 會在目錄中查詢 `image` 型別並呼叫 glance。也就是說,命令的第一個詞
(`image`、`network`、`server`…)與這裡看到的型別是對應的。

### 閱讀計算服務的構成

nova 本身也 **拆分成了多個程序**。`openstack compute service list` 顯示這些程序在哪臺主機上存活。

| 元件 | 作用 |
|---|---|
| nova-scheduler | 決定新例項 **放到哪臺計算主機上**,placement 會先縮小候選範圍 |
| nova-conductor | 代為處理資料庫訪問和耗時任務,是防止計算節點直接連線資料庫的中間層 |
| nova-compute | 操作真實的虛擬化層來啟動、停止例項。每臺計算主機上執行一個 |

檢視計算主機:

```bash
openstack compute service list
```

- 顯示 nova 的背景程序(scheduler、conductor、compute)及其主機、`Status`(enabled/disabled)、`State`(up/down)。

`State` 為 `up` 表示該程序存活,`Status` 表示運維人員是否將其關閉(disabled)。例項掉進 `ERROR` 時,
首先要看的就是這張表 — 如果 nova-compute 是 `down`,任何請求都到不了主機。

列表中 **看不到 nova-api。** API 服務以 Web 伺服器形式執行,作為端點登記在目錄(`openstack service list`)中;
這裡顯示的是背景程序。本實驗是一體化部署,所以三個元件顯示的都是同一個主機名。

> 參考: [OpenStack CLI 文件](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. 建立網路和子網

先建立用於掛接例項的租戶網路。

建立網路 `net1`:

```bash
openstack network create net1
```

- 在 neutron 中建立 L2 虛擬網路 `net1`。此時還沒有 IP 地址段,例項拿不到地址 — 需要下一條命令建立的子網。

在 `net1` 上建立 `192.168.100.0/24` 網段的子網 `subnet1`:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

- `--network net1` — 子網所屬的網路。
- `--subnet-range 192.168.100.0/24` — CIDR 網段。閘道器(預設 `.1`)和 DHCP 分配範圍會自動確定。
- 最後一個引數 `subnet1` — 子網名稱。

檢視建立的網路:

```bash
openstack network list
```

- `Subnets` 列出現剛才掛上的子網 ID,網路就準備好了。

## 2. 啟動例項(ACTIVE)

用準備好的 `cirros` 映像和 `m1.tiny` 規格啟動例項 `vm1`。

檢視可用映像:

```bash
openstack image list
```

- glance 中登記的映像列表。只有 `Status` 為 `active` 的映像才能用來建立例項。

檢視規格(flavor):

```bash
openstack flavor list
```

- 規格(flavor)= 例項硬體規格(vCPU、記憶體、磁碟)的模板。`m1.tiny` 是最小的規格。

啟動例項:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

- `--flavor m1.tiny` — 硬體規格,`--image cirros` — 啟動用的磁碟映像,`--network net1` — 建立埠並掛接的網路。
- 最後一個引數 `vm1` — 例項名稱。命令只是提交請求後立即返回(`BUILD`),狀態需要另外檢視。

檢視直到狀態變為 `ACTIVE`(可能需要幾秒鐘):

```bash
openstack server show vm1 -c status -c addresses
```

- `openstack server show <名稱>` — 單個例項的詳細資訊。
- `-c <列>` — 只選擇要輸出的列(欄位),可以指定多次。`addresses` 中會顯示分配到的 IP,如 `net1=192.168.100.x`。

## 3. 查詢所有專案的例項

之前用的 `openstack server list` 只顯示 **你所屬專案的例項**。

**專案(project)** 是 OpenStack 中擁有資源的單位(舊稱 tenant)。網路、例項、卷、映像等資源都屬於某個專案,
配額也按專案來設。使用者透過在專案中被授予 **角色(role)** 來訪問,令牌也是"以某個專案的身份"簽發的。
所以同一個人,以哪個專案登入,看到的資源就不同。

檢視當前令牌是以哪個專案簽發的:

```bash
openstack token issue -c project_id -f value
```

- `openstack token issue` — 用當前憑據向 keystone 申請令牌並顯示其資訊。
- `-c project_id -f value` — 只輸出 `project_id` 列,以不帶表格邊框的值(`-f value`)形式。便於在腳本中使用。

本實驗中已經建立了 `admin`、`service`、`demo` 等專案。檢視專案列表:

```bash
openstack project list
```

- keystone 中的專案(ID、名稱)列表。可以在這裡對照上一條命令看到的 `project_id` 是哪個專案。

`--all-projects` 是"**一次顯示所有專案的資源**"的引數。它是需要檢視整個雲的運維人員用的選項,
因此必須有 admin 角色才能使用,普通使用者使用會報權限錯誤。

預設輸出中沒有專案 ID 列。因為需要知道例項屬於哪個專案,所以用 `-c 'Project ID'` 直接選中這一列。
`--long` 是另一個選項,會附加任務狀態、主機等運維資訊。

包含專案 ID 進行查詢:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

- `--all-projects` — 查詢所有專案的例項(需要 admin 角色)。
- `-c <列>` — 只選擇要輸出的列(欄位),可以指定多次。列名含空格時要加引號(`'Project ID'`)。

為了評分,把這個結果儲存到檔案:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

- `-f value` — 不輸出表格,只輸出以空格分隔的值。
- `> ~/all-servers.txt` — 把輸出儲存(覆蓋)到檔案。檢查腳本會讀取這個檔案。

> 參考: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. 停止例項(SHUTOFF)

停止已啟動的例項,完成整個生命週期。

停止例項:

```bash
openstack server stop vm1
```

- 正常關閉例項(關機)。磁碟、IP 等資源都保留,可以用 `openstack server start vm1` 再次開機。要徹底刪除,用 `openstack server delete`。

確認狀態為 `SHUTOFF`:

```bash
openstack server show vm1 -c status
```

- 確認 `status` 已變為 `SHUTOFF`。若沒有立即變化,幾秒後再執行一次。
