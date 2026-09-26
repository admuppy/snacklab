# 製作並上傳 qcow2 映像

例項都是從 **映像** 啟動的。映像是把裝好作業系統的磁碟固化成的單個檔案,由 glance 儲存。
本實驗中你會親手製作磁碟檔案、轉換格式,然後上傳到 glance,並用這個映像啟動例項。

**qcow2**(QEMU Copy On Write 2)是 OpenStack 中最常用的磁碟格式。關鍵在於兩個特性。

- **稀疏分配(sparse)** — 即使虛擬大小是 1GiB,檔案也只佔用實際寫入的資料量。因此傳輸映像時的
  資料量很小。
- **帶有後設資料** — 可以在檔案內儲存後端檔案(backing file)、快照、壓縮等資訊。

相反,**raw** 是把磁碟位元組原樣排列的格式。它沒有結構,處理簡單、I/O 也少一層,但檔案大小通常等於
虛擬大小。生產中常見的做法是"分發用 qcow2,放到儲存上用 raw"。

> 參考: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> 注意: 本實驗的 nova 使用 fake 驅動,例項內部並不會真正啟動作業系統。驗證的範圍是:
> 映像被正確登記,並且 nova 用這個映像建立出例項的整個流程。

工作目錄是 `~/images`,引導腳本已經提前建立好。用於掛接例項的網路 `net1` 也已準備好。

## 1. 建立空的 qcow2 磁碟

`qemu-img` 是用來建立和轉換磁碟映像的工具。先建立一個什麼都沒有的 qcow2 磁碟,看看檔案結構。

建立虛擬大小為 1GiB 的空 qcow2 磁碟:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — 建立新的磁碟映像檔案。
- `-f qcow2` — 要建立的檔案格式,接著是檔案路徑,最後的 `1G` — 客戶機看到的虛擬大小。

檢視剛建立的磁碟資訊:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — 顯示映像的格式(`file format`)、虛擬大小、實際大小、簇大小等後設資料。

`virtual size` 是客戶機看到的磁碟大小,`disk size` 是檔案實際佔用的大小。剛建立的磁碟沒有內容,
所以兩者相差很大。這就是稀疏分配。

檢視檔案實際佔用多少:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — 檔案的詳細資訊(權限、所有者、大小、時間),`-h` — 以 K/M/G 等易讀單位顯示大小。
- 這裡顯示的是檔案的"表面"大小。實際佔用的塊可以用 `du -h` 檢視。

## 2. 轉換磁碟格式(qcow2 ↔ raw)

這次來處理裝有真實作業系統的磁碟。把 glance 中已有的 `cirros` 映像下載下來,轉換一下格式。

檢視 glance 中登記的映像格式:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <名稱>` — glance 映像的屬性。用 `-c` 只選 `disk_format`、`container_format`、`size`(位元組)列。

`disk_format` 是磁碟檔案本身的格式(qcow2、raw、vmdk…),`container_format` 指包裹磁碟的後設資料信封。
不帶信封、只上傳磁碟時用的值是 `bare`,實際工作中幾乎都用這個值。

把映像檔案下載到本地:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <名稱> --file <路徑>` — 把 glance 中儲存的映像資料下載到本地檔案。名字叫 save,實際上是"下載"命令。

檢視下載檔案的格式:

```bash
qemu-img info ~/images/cirros-src.img
```

- 即使副檔名是 `.img`,實際格式也是根據內容判斷的。看 `file format` 這一行。

把 qcow2 轉換為 raw(`-f` 是源格式,`-O` 是輸出格式):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — 把映像複製轉換為另一種格式(原始檔保持不變)。
- `-f qcow2` — 輸入格式(小寫 f),`-O raw` — 輸出格式(大寫 O)。之後依次是源路徑、目標路徑。

檢視轉換後的 raw 磁碟:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw 沒有後設資料,基本只顯示 `file format: raw` 和大小資訊。

raw 沒有結構,所以 `disk size` 接近 `virtual size`。這樣不利於傳輸,再轉回 qcow2。

把 raw 再轉回 qcow2:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 這次是輸入 raw → 輸出 qcow2。空塊不會寫入,所以檔案又變小了(加 `-c` 還會壓縮)。

一次比較三個檔案的大小:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 一次列出多個檔案,並排比較原始檔、raw、重新轉換的 qcow2 的大小。

## 3. 上傳到 glance 並啟動例項

把製作好的 qcow2 檔案登記到 glance。上傳時 **必須正確指定磁碟格式和容器格式**。
實際檔案是 qcow2 卻用 `--disk-format raw` 上傳的話,雖然能登記成功,啟動時卻會出錯。

一起指定的各個值含義如下。

- `--min-disk` / `--min-ram` — 提示使用此映像至少需要多少磁碟、記憶體。不滿足條件的規格會被
  nova 過濾掉。
- `--property` — 附加任意後設資料。像 `os_distro` 這樣的標準鍵,有時也會被用於排程或虛擬化層配置。

把 qcow2 檔案登記為 glance 映像:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — 登記新的 glance 映像 `cirros-lab`。
- `--disk-format qcow2 --container-format bare` — 檔案的實際格式和信封(無)。
- `--min-disk 1 --min-ram 64` — 所需的最小磁碟(GB)、記憶體(MB),`--property os_distro=cirros` — 任意後設資料。
- `--file <路徑>` — 要上傳的本地檔案。上傳完成後 `status` 變為 `active`。

檢視登記結果(`status` 必須為 `active`):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- 只選需要的列,確認登記時給的值是否原樣儲存。透過 `--property` 給的值在 `properties` 中。

在映像列表中也確認一下:

```bash
openstack image list
```

- 列表中 `cirros-lab` 顯示為 `active`,就可以用於建立例項。

用自己製作的映像啟動例項 `vm2`:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- 格式與模組 1 相同,但用 `--image cirros-lab` 指定自己製作的映像。規格必須滿足 `--min-disk`/`--min-ram` 條件才能建立。

檢視狀態和所用映像:

```bash
openstack server show vm2 -c status -c image
```

- `image` 列顯示 `cirros-lab` 及其 ID,說明例項是用剛上傳的映像建立的。
