# 制作并上传 qcow2 镜像

实例都是从 **镜像** 启动的。镜像是把装好操作系统的磁盘固化成的单个文件,由 glance 保存。
本实验中你会亲手制作磁盘文件、转换格式,然后上传到 glance,并用这个镜像启动实例。

**qcow2**(QEMU Copy On Write 2)是 OpenStack 中最常用的磁盘格式。关键在于两个特性。

- **稀疏分配(sparse)** — 即使虚拟大小是 1GiB,文件也只占用实际写入的数据量。因此传输镜像时的
  数据量很小。
- **带有元数据** — 可以在文件内保存后端文件(backing file)、快照、压缩等信息。

相反,**raw** 是把磁盘字节原样排列的格式。它没有结构,处理简单、I/O 也少一层,但文件大小通常等于
虚拟大小。生产中常见的做法是"分发用 qcow2,放到存储上用 raw"。

> 参考: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> 注意: 本实验的 nova 使用 fake 驱动,实例内部并不会真正启动操作系统。验证的范围是:
> 镜像被正确登记,并且 nova 用这个镜像创建出实例的整个流程。

工作目录是 `~/images`,引导脚本已经提前创建好。用于挂接实例的网络 `net1` 也已准备好。

## 1. 创建空的 qcow2 磁盘

`qemu-img` 是用来创建和转换磁盘镜像的工具。先创建一个什么都没有的 qcow2 磁盘,看看文件结构。

创建虚拟大小为 1GiB 的空 qcow2 磁盘:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — 创建新的磁盘镜像文件。
- `-f qcow2` — 要创建的文件格式,接着是文件路径,最后的 `1G` — 客户机看到的虚拟大小。

查看刚创建的磁盘信息:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — 显示镜像的格式(`file format`)、虚拟大小、实际大小、簇大小等元数据。

`virtual size` 是客户机看到的磁盘大小,`disk size` 是文件实际占用的大小。刚创建的磁盘没有内容,
所以两者相差很大。这就是稀疏分配。

查看文件实际占用多少:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — 文件的详细信息(权限、所有者、大小、时间),`-h` — 以 K/M/G 等易读单位显示大小。
- 这里显示的是文件的"表面"大小。实际占用的块可以用 `du -h` 查看。

## 2. 转换磁盘格式(qcow2 ↔ raw)

这次来处理装有真实操作系统的磁盘。把 glance 中已有的 `cirros` 镜像下载下来,转换一下格式。

查看 glance 中登记的镜像格式:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <名称>` — glance 镜像的属性。用 `-c` 只选 `disk_format`、`container_format`、`size`(字节)列。

`disk_format` 是磁盘文件本身的格式(qcow2、raw、vmdk…),`container_format` 指包裹磁盘的元数据信封。
不带信封、只上传磁盘时用的值是 `bare`,实际工作中几乎都用这个值。

把镜像文件下载到本地:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <名称> --file <路径>` — 把 glance 中保存的镜像数据下载到本地文件。名字叫 save,实际上是"下载"命令。

查看下载文件的格式:

```bash
qemu-img info ~/images/cirros-src.img
```

- 即使扩展名是 `.img`,实际格式也是根据内容判断的。看 `file format` 这一行。

把 qcow2 转换为 raw(`-f` 是源格式,`-O` 是输出格式):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — 把镜像复制转换为另一种格式(源文件保持不变)。
- `-f qcow2` — 输入格式(小写 f),`-O raw` — 输出格式(大写 O)。之后依次是源路径、目标路径。

查看转换后的 raw 磁盘:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw 没有元数据,基本只显示 `file format: raw` 和大小信息。

raw 没有结构,所以 `disk size` 接近 `virtual size`。这样不利于传输,再转回 qcow2。

把 raw 再转回 qcow2:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 这次是输入 raw → 输出 qcow2。空块不会写入,所以文件又变小了(加 `-c` 还会压缩)。

一次比较三个文件的大小:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 一次列出多个文件,并排比较源文件、raw、重新转换的 qcow2 的大小。

## 3. 上传到 glance 并启动实例

把制作好的 qcow2 文件登记到 glance。上传时 **必须正确指定磁盘格式和容器格式**。
实际文件是 qcow2 却用 `--disk-format raw` 上传的话,虽然能登记成功,启动时却会出错。

一起指定的各个值含义如下。

- `--min-disk` / `--min-ram` — 提示使用此镜像至少需要多少磁盘、内存。不满足条件的规格会被
  nova 过滤掉。
- `--property` — 附加任意元数据。像 `os_distro` 这样的标准键,有时也会被用于调度或虚拟化层配置。

把 qcow2 文件登记为 glance 镜像:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — 登记新的 glance 镜像 `cirros-lab`。
- `--disk-format qcow2 --container-format bare` — 文件的实际格式和信封(无)。
- `--min-disk 1 --min-ram 64` — 所需的最小磁盘(GB)、内存(MB),`--property os_distro=cirros` — 任意元数据。
- `--file <路径>` — 要上传的本地文件。上传完成后 `status` 变为 `active`。

查看登记结果(`status` 必须为 `active`):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- 只选需要的列,确认登记时给的值是否原样保存。通过 `--property` 给的值在 `properties` 中。

在镜像列表中也确认一下:

```bash
openstack image list
```

- 列表中 `cirros-lab` 显示为 `active`,就可以用于创建实例。

用自己制作的镜像启动实例 `vm2`:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- 格式与模块 1 相同,但用 `--image cirros-lab` 指定自己制作的镜像。规格必须满足 `--min-disk`/`--min-ram` 条件才能创建。

查看状态和所用镜像:

```bash
openstack server show vm2 -c status -c image
```

- `image` 列显示 `cirros-lab` 及其 ID,说明实例是用刚上传的镜像创建的。
