# 启动第一台实例

本实验在 Pod 内运行的 **你专属的一体化 OpenStack**(Caracal)中进行。keystone、glance、
neutron、nova 都在其中运行,终端里已经配置好管理员凭据,可以直接使用 `openstack` CLI
(也有 `os` 别名)。

> 注意: 本实验的 nova 使用 **fake 驱动** — 实例没有真实的虚拟机,只按状态机启动,
> 因此能立即起来且几乎不占资源。无法使用控制台和 SSH,但 API、CLI 的流程与真实的 OpenStack 相同。

### 阅读服务目录

OpenStack 不是一个程序,而是 **一组各司其职的服务**。每个服务都有自己的 REST API,
相互调用时,会从 keystone 中登记的 **服务目录** 里查找对方的端点地址。`openstack service list`
会显示目录里登记了哪些服务。

本实验中会接触到的服务如下。

| 服务 | 类型 | 作用 |
|---|---|---|
| keystone | identity | 认证与授权。登录后签发令牌,其他服务用这个令牌确认请求者 |
| glance | image | 保存并分发创建实例时使用的磁盘镜像 |
| neutron | network | 负责网络、子网、端口等虚拟网络 |
| nova | compute | 负责实例(虚拟机)的创建、启动、停止等生命周期 |
| placement | placement | 跟踪哪些主机还有剩余资源(vCPU、内存、磁盘),协助 nova 做调度决策 |

查看服务目录:

```bash
openstack service list
```

- `openstack <对象> <动作>` — OpenStack CLI 的基本格式。这里对象是 `service`,动作是 `list`。
- 列出 keystone 服务目录中登记的服务。要看端点 URL,用 `openstack endpoint list`。

输出中的 `Name` 是服务名,`Type` 是表示角色的标准类型字符串。CLI 按这个 **类型** 查找端点。
例如 `openstack image list` 会在目录中查找 `image` 类型并调用 glance。也就是说,命令的第一个词
(`image`、`network`、`server`…)与这里看到的类型是对应的。

### 阅读计算服务的构成

nova 本身也 **拆分成了多个进程**。`openstack compute service list` 显示这些进程在哪台主机上存活。

| 组件 | 作用 |
|---|---|
| nova-scheduler | 决定新实例 **放到哪台计算主机上**,placement 会先缩小候选范围 |
| nova-conductor | 代为处理数据库访问和耗时任务,是防止计算节点直接连接数据库的中间层 |
| nova-compute | 操作真实的虚拟化层来启动、停止实例。每台计算主机上运行一个 |

查看计算主机:

```bash
openstack compute service list
```

- 显示 nova 的后台进程(scheduler、conductor、compute)及其主机、`Status`(enabled/disabled)、`State`(up/down)。

`State` 为 `up` 表示该进程存活,`Status` 表示运维人员是否将其关闭(disabled)。实例掉进 `ERROR` 时,
首先要看的就是这张表 — 如果 nova-compute 是 `down`,任何请求都到不了主机。

列表中 **看不到 nova-api。** API 服务以 Web 服务器形式运行,作为端点登记在目录(`openstack service list`)中;
这里显示的是后台进程。本实验是一体化部署,所以三个组件显示的都是同一个主机名。

> 参考: [OpenStack CLI 文档](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. 创建网络和子网

先创建用于挂接实例的租户网络。

创建网络 `net1`:

```bash
openstack network create net1
```

- 在 neutron 中创建 L2 虚拟网络 `net1`。此时还没有 IP 地址段,实例拿不到地址 — 需要下一条命令创建的子网。

在 `net1` 上创建 `192.168.100.0/24` 网段的子网 `subnet1`:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

- `--network net1` — 子网所属的网络。
- `--subnet-range 192.168.100.0/24` — CIDR 网段。网关(默认 `.1`)和 DHCP 分配范围会自动确定。
- 最后一个参数 `subnet1` — 子网名称。

查看创建的网络:

```bash
openstack network list
```

- `Subnets` 列出现刚才挂上的子网 ID,网络就准备好了。

## 2. 启动实例(ACTIVE)

用准备好的 `cirros` 镜像和 `m1.tiny` 规格启动实例 `vm1`。

查看可用镜像:

```bash
openstack image list
```

- glance 中登记的镜像列表。只有 `Status` 为 `active` 的镜像才能用来创建实例。

查看规格(flavor):

```bash
openstack flavor list
```

- 规格(flavor)= 实例硬件规格(vCPU、内存、磁盘)的模板。`m1.tiny` 是最小的规格。

启动实例:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

- `--flavor m1.tiny` — 硬件规格,`--image cirros` — 启动用的磁盘镜像,`--network net1` — 创建端口并挂接的网络。
- 最后一个参数 `vm1` — 实例名称。命令只是提交请求后立即返回(`BUILD`),状态需要另外查看。

查看直到状态变为 `ACTIVE`(可能需要几秒钟):

```bash
openstack server show vm1 -c status -c addresses
```

- `openstack server show <名称>` — 单个实例的详细信息。
- `-c <列>` — 只选择要输出的列(字段),可以指定多次。`addresses` 中会显示分配到的 IP,如 `net1=192.168.100.x`。

## 3. 查询所有项目的实例

之前用的 `openstack server list` 只显示 **你所属项目的实例**。

**项目(project)** 是 OpenStack 中拥有资源的单位(旧称 tenant)。网络、实例、卷、镜像等资源都属于某个项目,
配额也按项目来设。用户通过在项目中被授予 **角色(role)** 来访问,令牌也是"以某个项目的身份"签发的。
所以同一个人,以哪个项目登录,看到的资源就不同。

查看当前令牌是以哪个项目签发的:

```bash
openstack token issue -c project_id -f value
```

- `openstack token issue` — 用当前凭据向 keystone 申请令牌并显示其信息。
- `-c project_id -f value` — 只输出 `project_id` 列,以不带表格边框的值(`-f value`)形式。便于在脚本中使用。

本实验中已经创建了 `admin`、`service`、`demo` 等项目。查看项目列表:

```bash
openstack project list
```

- keystone 中的项目(ID、名称)列表。可以在这里对照上一条命令看到的 `project_id` 是哪个项目。

`--all-projects` 是"**一次显示所有项目的资源**"的参数。它是需要查看整个云的运维人员用的选项,
因此必须有 admin 角色才能使用,普通用户使用会报权限错误。

默认输出中没有项目 ID 列。因为需要知道实例属于哪个项目,所以用 `-c 'Project ID'` 直接选中这一列。
`--long` 是另一个选项,会附加任务状态、主机等运维信息。

包含项目 ID 进行查询:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

- `--all-projects` — 查询所有项目的实例(需要 admin 角色)。
- `-c <列>` — 只选择要输出的列(字段),可以指定多次。列名含空格时要加引号(`'Project ID'`)。

为了评分,把这个结果保存到文件:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

- `-f value` — 不输出表格,只输出以空格分隔的值。
- `> ~/all-servers.txt` — 把输出保存(覆盖)到文件。检查脚本会读取这个文件。

> 参考: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. 停止实例(SHUTOFF)

停止已启动的实例,完成整个生命周期。

停止实例:

```bash
openstack server stop vm1
```

- 正常关闭实例(关机)。磁盘、IP 等资源都保留,可以用 `openstack server start vm1` 再次开机。要彻底删除,用 `openstack server delete`。

确认状态为 `SHUTOFF`:

```bash
openstack server show vm1 -c status
```

- 确认 `status` 已变为 `SHUTOFF`。若没有立即变化,几秒后再执行一次。
