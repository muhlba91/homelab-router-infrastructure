# Dedicated server (profile `server-zfs`)

A dedicated server with two NVMe disks (Hetzner, OVH; BIOS or UEFI) runs NixOS as router and hypervisor: the router
configuration on the host, guests as libvirt VMs. Both disks hold a BIOS boot partition, an ESP and a ZFS partition;
`rpool` mirrors the ZFS partitions. GRUB is installed on both disks (BIOS and UEFI), so either disk boots the box.

## Site file

Only what differs from the other sites:

```yaml
hardware:
  profile: server-zfs
  disks: [/dev/disk/by-id/nvme-<disk 1>, /dev/disk/by-id/nvme-<disk 2>]
  kernelParams: ["console=tty0", "console=ttyS1,115200n8"]  # OVH serial console
system:
  watchdog: 0s          # the provider's reset API recovers a hung box
  autoReboot: {enabled: true}  # reboots in a window after a kernel, initrd or module change
hypervisor: {enabled: true}
network:
  trustedNetworks: {wan: false}  # v4/v6 as before; was true for the transfer net
  wan:                  # static, as the provider documents it
    mac: "<NIC MAC>"
    v4: {method: static, address: <ip>, netmask: <n>, gateway: <gw>, onLink: true, announce: false}  # onLink for a /32
  lan:
    mac: "<LAN MAC>"    # unchanged: it becomes the MAC of the bridge
    bridge: true        # guests attach to the bridge `lan0`
firewall:
  hairpin: true         # LAN hosts reach the forwards on the WAN address
  services: {ssh: {from: [lan, trusted, wan]}}  # CI and `./router` use the management address
```

Public SSH is break-glass: keys only, the site's deploy key, watched by CrowdSec (if enabled); `virt` is reachable
wherever SSH is. Set `deploy.automated: false` before the site file changes for a reinstall (CI would deploy it to the
old system).

## Install from the provider's rescue system

1. In the rescue system, clear the old metadata so that nothing is active afterwards (`lsblk`):
   `mdadm --stop --scan`, `vgchange -an`, `zpool labelclear -f <old ZFS partitions>`, `wipefs -a` on all partitions and
   both disks.
2. Put the site's deploy public key into root's `authorized_keys` (`ssh-keygen -y -f
   ../infrastructure/outputs/keys/<site>/deploy-key` prints it).
3. On the workstation (in `nix/`): `./router install <site> <ip>`. It kexecs into an installer in RAM (the rescue
   system needs internet), installs and reboots (about 10 minutes). On a NixOS installer (an ISO) it skips the kexec.
4. If the installer's address differs after the kexec (a DHCP client id that the provider does not know), run the
   command again with the new address.

Then [validation.md](validation.md) sections 1-8.

## Disks

The host id of the pool derives from the host name: after a rename the root pool needs one `zpool import -f` from the
rescue system.

With one disk missing the box boots from the other, the pool is `DEGRADED` and `./router health` warns. A deploy then
fails in `grub-install` (it installs GRUB on both disks) and rolls back: replace the disk first.

## Guests

A guest repository defines its VMs as libvirt domains and manages them with `virsh` over SSH as the user `virt` (the
keys of `deploy`); the workstation needs the `virsh` client:

```bash
virsh -c qemu+ssh://virt@<management address>/system list
```

- Disks: zvols in the pool `guests` (`rpool/guests`, quota 360 GiB; the ARC caches metadata only). Create them sparse:
  `virsh vol-create-as guests <name> <size> --allocation 0` (the volblocksize is the OpenZFS default of 16K).
- Installer images: the directory pool `iso`.
- Network: a bridge interface on `lan0`; libvirt defines no networks.
- Firmware: `<os firmware='efi'>` with Secure Boot off selects OVMF and keeps the NVRAM per domain.
- On shutdown the guests get an ACPI shutdown and 300 s.
