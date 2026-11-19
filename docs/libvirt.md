# VMs on a server

A VM of a [server](server.md) is a spec in the repository that owns it: `libvirt/<name>.yml`, from
[nix/libvirt/template.yml](../nix/libvirt/template.yml). This repository holds the domain template
([domain.nix](../nix/libvirt/domain.nix)) and the commands. Run them from `nix/`; `libvirt-deploy` needs the site data
like `./router deploy`.

```bash
# print the domain XML of a spec (changes nothing)
./router libvirt-render <spec>

# create what is missing on the site's host, define the domain, enable autostart, start it
./router libvirt-deploy <site> <spec>

# virsh on the site's host (as the user `virt`; runs in the container of ./nx, nothing to install)
./router virsh <site> list --all
```

`libvirt-deploy` is idempotent and deletes nothing:

1. It creates the missing disks as sparse zvols `<name>-disk0`, `<name>-disk1`, ... in the pool `guests`. The size of an
   existing disk is not changed. Only append disks to a spec: the order sets the device names and the boot disk.
2. It downloads the installer image (checked against `sha256`, if set) and uploads it to the pool `iso`, unless a volume
   of that name exists.
3. It defines the domain under its existing UUID and enables autostart.
4. It starts the domain. A running one keeps running and takes the new definition at its next start.

A VM is a q35 machine with OVMF (Secure Boot off), fixed memory, the host's CPU model and a virtio NIC with the MAC of
the spec on the bridge `lan0`. The disks are virtio-scsi (`cache=none`, `io=native`, `discard=unmap`), seen as `sda`,
`sdb`, ... and as `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`, `...-drive-scsi1`, ... The image is a SATA
CD-ROM (libvirt target `sdz`) with boot order 2, after the first disk. The console is VNC on the host's `127.0.0.1`;
tunnel it over SSH (`./router virsh <site> vncdisplay <name>` gives the display number).

After the install, eject the image and remove `iso` from the spec; the next deploy then drops the CD-ROM:

```bash
# eject the image from the running VM and from its definition
./router virsh <site> change-media <name> sdz --eject --live --config
```

Disks are never resized or removed by the commands above:

```bash
# grow a disk (the VM sees the new size after a reboot)
./router virsh <site> vol-resize --pool guests <name>-disk<N> <new size, for example 80G>

# remove a VM: stop it, drop its definition and NVRAM, delete each disk
./router virsh <site> destroy <name>
./router virsh <site> undefine --nvram <name>
./router virsh <site> vol-delete --pool guests <name>-disk<N>
```
