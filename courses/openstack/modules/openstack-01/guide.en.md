# Boot Your First Instance

This lab runs on **your own all-in-one OpenStack** (Caracal) inside the pod. keystone,
glance, neutron and nova are all running here, and the terminal already has admin
credentials configured — use the `openstack` CLI directly (an `os` alias exists too).

> Note: nova runs the **fake driver** in this lab — instances "boot" as pure state
> machines with no real VM behind them, so they start instantly and cost almost nothing.
> Console access and SSH won't work, but the API/CLI workflow is identical to real
> OpenStack.

### Reading the service catalog

OpenStack is not one program but **a set of services with different jobs**. Each one has its
own REST API, and they find each other through the **service catalog** kept by keystone.
`openstack service list` shows what is registered in that catalog.

These are the services you will meet in this lab:

| Service | Type | What it does |
|---|---|---|
| keystone | identity | Authentication and authorization. It issues the token every other service checks |
| glance | image | Stores and serves the disk images instances are created from |
| neutron | network | Virtual networking — networks, subnets, ports |
| nova | compute | Instance lifecycle: create, boot, stop, delete |
| placement | placement | Tracks which host still has capacity (vCPU, RAM, disk) so nova can place instances |

Check the service catalog:

```bash
openstack service list
```

`Name` is the service's name and `Type` is the standard string for its role. The CLI resolves
endpoints by **type**: `openstack image list` looks up the `image` type and calls glance. In other
words, the first word of a command (`image`, `network`, `server`, …) maps to a type in this table.

### Reading the compute service list

nova itself is **split into several processes**. `openstack compute service list` shows which of
them are alive and on which host.

| Component | What it does |
|---|---|
| nova-scheduler | Picks **which compute host** a new instance lands on; placement narrows the candidates |
| nova-conductor | Handles database access and long-running tasks so compute nodes never touch the DB directly |
| nova-compute | Drives the hypervisor to start and stop instances. One runs on every compute host |

Check the compute host:

```bash
openstack compute service list
```

`State` is `up` when the process is alive; `Status` tells you whether an operator has disabled it.
This is the first table to look at when instances fail to schedule — nothing reaches a host whose
nova-compute is `down`.

**nova-api is not in this list.** API services run as web servers and appear as endpoints in the
service catalog instead; what you see here are the background processes. This lab is all-in-one,
so all three components report the same host name.

> Reference: [OpenStack CLI docs](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. Create a network and subnet

Start with a tenant network to attach the instance to.

Create the network `net1`:

```bash
openstack network create net1
```

Create the subnet `subnet1` on `net1` with the `192.168.100.0/24` range:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

List networks to verify:

```bash
openstack network list
```

## 2. Boot an instance (ACTIVE)

Boot the instance `vm1` from the pre-loaded `cirros` image with the `m1.tiny` flavor.

List available images:

```bash
openstack image list
```

List flavors:

```bash
openstack flavor list
```

Boot the instance:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

Watch until the status is `ACTIVE` (it can take a few seconds):

```bash
openstack server show vm1 -c status -c addresses
```

## 3. List instances across projects

The `openstack server list` you have used so far only shows **instances in your own project**.

A **project** is the unit that owns resources in OpenStack (it used to be called a tenant).
Networks, instances, volumes and images all belong to a project, and quotas are applied per
project. Users reach a project through a **role**, and tokens are issued "as" a project — so the
same person sees different resources depending on which project they logged into.

See which project your current token belongs to:

```bash
openstack token issue -c project_id -f value
```

This lab already has projects such as `admin`, `service` and `demo`. List them:

```bash
openstack project list
```

`--all-projects` asks for **resources from every project at once**. It is an operator option for
looking at the whole cloud, so it needs the admin role; a regular user gets a permission error.

The default columns do not include the project. Since the point here is seeing who owns what, pick
that column explicitly with `-c 'Project ID'`. (`--long` is a separate option that adds operational
detail such as task state and host.)

Include the project ID:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

Save the result to a file for grading:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

> Reference: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. Stop the instance (SHUTOFF)

Finish the lifecycle by stopping the instance.

Stop the instance:

```bash
openstack server stop vm1
```

Verify the status is `SHUTOFF`:

```bash
openstack server show vm1 -c status
```
