# Build and Upload a qcow2 Image

Every instance starts from an **image** — a disk with an operating system on it, frozen into a
single file and kept by glance. In this lab you create disk files yourself, convert them between
formats, upload one to glance and boot an instance from it.

**qcow2** (QEMU Copy On Write 2) is the disk format most commonly used with OpenStack. Two
properties matter here:

- **Sparse allocation** — a disk with a 1 GiB virtual size only occupies as much file space as the
  data actually written to it, which keeps images small to move around.
- **It carries metadata** — backing files, snapshots and compression live inside the file.

**raw**, by contrast, is the plain byte-for-byte layout of the disk. It has no structure, so it is
simple and skips one layer on I/O, but the file usually takes up the full virtual size. A common
split in production is "ship qcow2, store raw".

> Reference: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> Note: nova runs the fake driver in this lab, so no operating system really boots inside the
> instance. What you are verifying is the full path from a disk file to a registered image to an
> instance created from it.

Work happens in `~/images`, which the bootstrap already created, along with the network `net1` to
attach the instance to.

## 1. Create an empty qcow2 disk

`qemu-img` is the tool that creates and converts disk images. Start with an empty qcow2 disk to see
how the format behaves.

Create an empty qcow2 disk with a 1 GiB virtual size:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — creates a new disk image file.
- `-f qcow2` — the file's format, then the path, and finally `1G` — the virtual size the guest will see.

Inspect the disk you just created:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — shows the image metadata: format (`file format`), virtual size, actual size, cluster size, …

`virtual size` is the disk the guest will see; `disk size` is what the file actually occupies. The
new disk holds no data, so the two differ wildly — that is sparse allocation.

Check the size on disk:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — detailed listing (permissions, owner, size, time); `-h` — human-readable sizes (K/M/G).
- This is the file's apparent size; the blocks actually used show with `du -h`.

## 2. Convert disk formats (qcow2 ↔ raw)

Now work with a disk that really has an OS on it: pull the `cirros` image out of glance and convert
it.

Check the formats of the registered image:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <name>` — properties of a glance image; `-c` picks the `disk_format`, `container_format` and `size` (bytes) columns.

`disk_format` is the format of the disk file itself (qcow2, raw, vmdk, …), while
`container_format` describes the metadata envelope wrapped around it. `bare` means there is no
envelope — just the disk — and it is what nearly everyone uses.

Download the image file:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <name> --file <path>` — downloads the image data stored in glance to a local file (despite the name, it's a download).

Check the format of the downloaded file:

```bash
qemu-img info ~/images/cirros-src.img
```

- Even with a `.img` extension the real format is detected from the content; check the `file format` line.

Convert qcow2 to raw (`-f` is the input format, `-O` the output format):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — copies an image into another format (the source is left untouched).
- `-f qcow2` — input format (lower-case f), `-O raw` — output format (upper-case O), followed by source and destination paths.

Inspect the raw disk:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw has no metadata, so you mostly see `file format: raw` and the sizes.

Raw has no structure, so `disk size` sits close to `virtual size`. That is poor for shipping, so
convert it back.

Convert raw back to qcow2:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- Now raw in, qcow2 out. Empty blocks aren't written, so the file shrinks again (add `-c` to compress as well).

Compare all three files side by side:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- Lists several files at once to compare the source, raw and re-converted qcow2 sizes side by side.

## 3. Upload to glance and boot an instance

Register the qcow2 file with glance. The **formats you declare must match the file**: uploading a
qcow2 file as `--disk-format raw` succeeds, and then breaks at boot.

The other options mean:

- `--min-disk` / `--min-ram` — hints about the minimum disk and memory this image needs. nova
  filters out flavors that cannot satisfy them.
- `--property` — arbitrary metadata. Well-known keys such as `os_distro` can feed scheduling and
  hypervisor settings.

Register the qcow2 file as a glance image:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — registers a new glance image `cirros-lab`.
- `--disk-format qcow2 --container-format bare` — the file's real format and envelope (none).
- `--min-disk 1 --min-ram 64` — minimum disk (GB) and RAM (MB); `--property os_distro=cirros` — arbitrary metadata.
- `--file <path>` — the local file to upload; `status` becomes `active` once the upload finishes.

Check the result (`status` must be `active`):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- Pick just the columns needed to confirm the values you registered; `--property` values appear under `properties`.

Confirm it appears in the image list:

```bash
openstack image list
```

- Once `cirros-lab` shows as `active` it can be used for instances.

Boot the instance `vm2` from the image you built:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- Same shape as in module 1, but `--image cirros-lab` points at your own image. The flavor must satisfy `--min-disk`/`--min-ram`.

Check its status and the image it used:

```bash
openstack server show vm2 -c status -c image
```

- If the `image` column shows `cirros-lab` and its ID, the instance was built from the image you uploaded.
