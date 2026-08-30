# Boot Your First Instance

This lab runs on **your own all-in-one OpenStack** (Caracal) inside the pod. keystone,
glance, neutron and nova are all running here, and the terminal already has admin
credentials configured — use the `openstack` CLI directly (an `os` alias exists too).

> Note: nova runs the **fake driver** in this lab — instances "boot" as pure state
> machines with no real VM behind them, so they start instantly and cost almost nothing.
> Console access and SSH won't work, but the API/CLI workflow is identical to real
> OpenStack.

Check the service catalog:

```bash
openstack service list
```

Check the compute host:

```bash
openstack compute service list
```

> Reference: [OpenStack CLI docs](https://docs.openstack.org/python-openstackclient/latest/)

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

## 3. Stop the instance (SHUTOFF)

Finish the lifecycle by stopping the instance.

Stop the instance:

```bash
openstack server stop vm1
```

Verify the status is `SHUTOFF`:

```bash
openstack server show vm1 -c status
```
