# Physical router

A physical router (hardware profile `n100`: an Intel N100/N150 mini PC, UEFI) is installed on the bench and then
swapped in for the old router; the rollback is swapping the old one back.

## Before the install

- BIOS: UEFI boot from USB, Secure Boot off, power on after AC loss, the board's own watchdog ("WDT") off (systemd
  uses the Intel TCO watchdog).
- Boot the NixOS minimal ISO from a USB stick (it runs from RAM and does not touch the disk) and collect the values of
  the site file:

  ```bash
  for i in /sys/class/net/en*; do echo "${i##*/} $(cat $i/address) carrier=$(cat $i/carrier)"; done
  ls -l /dev/disk/by-id/ | grep -v -- -part
  ```

  `network.wan.mac`/`lan.mac`: move a cable to see which port is which. `hardware.disk`: the
  `/dev/disk/by-id/nvme-…` path (USB disks, e.g. a KVM's virtual one, take `/dev/sda`).

## Install (on the bench)

The box keeps the keys it is installed with: commit `enabled: true` before the install (a `pulumi up` where the site is
disabled deletes its keys) and leave `deploy.automated` off until the swap (CI would deploy to the old router's address).

1. Connect one cable only, to a network with DHCP and internet (the installer builds the system on the box). Never
   connect the router's LAN port to the live LAN before the swap: it brings up the old router's LAN address, DHCP and
   router advertisements.
2. In the console (user `nixos`): `passwd` (temporary, only for copying the key), `ip -br a` (the installer's address).
3. On the workstation (in `nix/`): copy the site's deploy key to `root`, then install (wipes the disk, reboots):

   ```bash
   ssh-keygen -y -f ../infrastructure/outputs/keys/<site>/deploy-key | ssh -o StrictHostKeyChecking=no \
     -o UserKnownHostsFile=/dev/null nixos@<ip> 'sudo mkdir -p /root/.ssh && sudo tee /root/.ssh/authorized_keys'
   ./router install <site> <ip>
   ```

4. Pull the USB stick when the box reboots (or put the NVMe first in the boot order). systemd-boot is installed to the
   ESP's fallback path, so the firmware boots it without boot entries.
5. In the console: `cat /sys/class/watchdog/watchdog0/identity` must be `iTCO_wdt` (systemd uses `watchdog0`). Hang
   test: `echo c | sudo tee /proc/sysrq-trigger` crashes the kernel; the watchdog restarts the box within about a
   minute (`system.watchdog`).

The router is not reachable on the bench (its WAN waits for the site's real uplink, its LAN is not connected): use the
console.

## Swap

Power off the old router, move its WAN and LAN cables (and a UPS's USB cable) to the router's WAN and LAN ports, power
it on. Then [validation.md](validation.md) and commit `deploy.automated: true`. Rollback: the old router back on the same
cables.
